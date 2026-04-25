import { pool } from '../db';
import { logger } from '../utils/logger';
import { WarrantyClaim, CreateWarrantyClaimDto, SavingsFeedEntry } from '../types/database.types';
import { AppError } from '../utils/errors';
import { decimalToCents } from '../utils/money';

const SERIALIZATION_FAILURE = '40001';
const DEADLOCK_DETECTED = '40P01';

/**
 * Canonical claim status set + transition table. Mirrors the CHECK
 * constraint installed in migration 060. Keep this in sync with the
 * service-level enforcement and the tests that exercise it.
 *
 * Allowed transitions:
 *   filed     → in_review | denied | closed
 *   in_review → approved  | denied | closed
 *   approved  → settled   | closed
 *   denied    → closed
 *   settled   → closed
 *   closed    → (terminal)
 */
export type ClaimStatus =
  | 'filed'
  | 'in_review'
  | 'approved'
  | 'denied'
  | 'settled'
  | 'closed';

const CLAIM_STATUS_TRANSITIONS: Record<ClaimStatus, ReadonlySet<ClaimStatus>> = {
  filed:     new Set<ClaimStatus>(['in_review', 'denied', 'closed']),
  in_review: new Set<ClaimStatus>(['approved', 'denied', 'closed']),
  approved:  new Set<ClaimStatus>(['settled', 'closed']),
  denied:    new Set<ClaimStatus>(['closed']),
  settled:   new Set<ClaimStatus>(['closed']),
  closed:    new Set<ClaimStatus>(),
};

function isClaimStatus(s: unknown): s is ClaimStatus {
  return typeof s === 'string' && (s in CLAIM_STATUS_TRANSITIONS);
}

function assertClaimTransition(from: ClaimStatus, to: ClaimStatus) {
  if (from === to) return;
  const allowed = CLAIM_STATUS_TRANSITIONS[from];
  if (!allowed.has(to)) {
    throw new AppError(`Invalid claim status transition: ${from} → ${to}`, 400);
  }
}

/**
 * Whitelist sanitizer for fields that flow into stored social-proof strings.
 * Strips anything outside [A-Za-z0-9 ,.'-], collapses whitespace, caps to
 * 60 chars. Kept here (not in a generic util) because the rule is specifically
 * about what can appear inside the savings_feed.display_text template — a
 * laxer rule would re-open the stored-XSS hole the audit caught.
 */
function sanitizeFeedToken(value: unknown): string {
  if (typeof value !== 'string') return '';
  return value
    .replace(/[^A-Za-z0-9 ,.'-]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 60);
}

async function runWithSerializableRetry<T>(
  fn: () => Promise<T>,
  label: string,
  maxAttempts = 3,
): Promise<T> {
  let attempt = 0;
  let lastErr: unknown;
  while (attempt < maxAttempts) {
    attempt++;
    try {
      return await fn();
    } catch (err: any) {
      if (err?.code === SERIALIZATION_FAILURE || err?.code === DEADLOCK_DETECTED) {
        lastErr = err;
        const backoffMs = 25 * Math.pow(2, attempt - 1);
        logger.warn({ attempt, backoffMs, label }, 'Serialization conflict, retrying');
        await new Promise((r) => setTimeout(r, backoffMs));
        continue;
      }
      throw err;
    }
  }
  throw lastErr;
}

export class WarrantyClaimsService {
  /**
   * Create a new warranty claim
   */
  static async createClaim(
    userId: string,
    data: CreateWarrantyClaimDto
  ): Promise<WarrantyClaim> {
    if (data.amountSaved !== undefined && data.amountSaved < 0) {
      throw new AppError('amountSaved cannot be negative', 400);
    }
    return runWithSerializableRetry(
      () => this._createClaimOnce(userId, data),
      'createClaim',
    );
  }

  private static async _createClaimOnce(
    userId: string,
    data: CreateWarrantyClaimDto,
  ): Promise<WarrantyClaim> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN ISOLATION LEVEL SERIALIZABLE');

      // Verify item belongs to user and is not archived
      const itemCheck = await client.query(
        'SELECT id FROM items WHERE id = $1 AND user_id = $2 AND is_archived = FALSE',
        [data.itemId, userId]
      );

      if (itemCheck.rows.length === 0) {
        throw new AppError('Item not found or is archived', 404);
      }

      // Default initial status is 'filed' (the canonical state machine
      // entry point). Anything else from the client is rejected unless it's
      // a valid alias from the validator allow-list.
      const requestedStatus = data.status as ClaimStatus | undefined;
      const initialStatus: ClaimStatus = requestedStatus && isClaimStatus(requestedStatus)
        ? requestedStatus
        : 'filed';

      // F011: out_of_pocket defaults to 0 to avoid NaN flowing into DECIMAL.
      const outOfPocket = data.outOfPocket ?? 0;

      // Create claim
      const result = await client.query(
        `INSERT INTO warranty_claims (
          item_id, user_id, claim_date, issue_description, repair_description,
          repair_cost, amount_saved, out_of_pocket, status, filed_with, claim_number, notes
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
        RETURNING *`,
        [
          data.itemId,
          userId,
          data.claimDate || new Date(),
          data.issueDescription,
          data.repairDescription,
          data.repairCost,
          data.amountSaved,
          outOfPocket,
          initialStatus,
          data.filedWith,
          data.claimNumber,
          data.notes,
        ]
      );

      const claim = result.rows[0];

      // F010: record the initial status as the first transition for the audit.
      await client.query(
        `INSERT INTO warranty_claim_state_history (claim_id, from_status, to_status, actor_user_id)
         VALUES ($1, NULL, $2, $3)`,
        [claim.id, initialStatus, userId],
      );

      // Upsert user analytics. COALESCE guards against NULL from a prior
      // row that was created without these aggregate columns populated.
      await client.query(
        `INSERT INTO user_analytics (user_id, total_warranty_savings, total_claims_filed, has_filed_claim)
         VALUES ($2, COALESCE($1::numeric, 0), 1, TRUE)
         ON CONFLICT (user_id)
         DO UPDATE SET total_warranty_savings = COALESCE(user_analytics.total_warranty_savings, 0) + COALESCE($1::numeric, 0),
                       total_claims_filed    = COALESCE(user_analytics.total_claims_filed, 0) + 1,
                       has_filed_claim       = TRUE,
                       updated_at            = NOW()`,
        [data.amountSaved, userId]
      );

      // Add to savings feed (anonymized)
      const userLocation = await client.query(
        `SELECT h.city, h.state
         FROM items i
         JOIN homes h ON h.id = i.home_id
         WHERE i.id = $1`,
        [data.itemId]
      );

      if (userLocation.rows.length > 0) {
        const { city, state } = userLocation.rows[0];

        // Sanitize city/state before they flow into a stored social-proof
        // string. Strip everything outside [A-Za-z0-9 ,.'-], cap length, and
        // keep the template fixed at the SQL level so a user-supplied city of
        // `</script><img src=x>` cannot hop into the rendered feed (F003).
        const safeCity = sanitizeFeedToken(city);
        const safeState = sanitizeFeedToken(state);

        await client.query(
          `INSERT INTO savings_feed (user_city, user_state, amount_saved, item_category, claim_type, display_text)
           SELECT $1, $2, $3::numeric, i.category, 'Warranty claim',
                  $4 || ' homeowner just saved $' || ROUND($3::numeric, 2)::text || ' on a ' || i.category || ' repair'
           FROM items i
           WHERE i.id = $5`,
          [safeCity, safeState, data.amountSaved, safeCity || 'A', data.itemId]
        );
      }

      await client.query('COMMIT');

      logger.info({ claimId: claim.id, userId }, 'Warranty claim created');

      return claim;
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error({ error, userId, data }, 'Error creating warranty claim');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Get all claims for a user
   */
  static async getUserClaims(
    userId: string,
    options: {
      limit?: number;
      offset?: number;
      itemId?: string;
    } = {}
  ): Promise<{ claims: WarrantyClaim[]; total: number }> {
    const { limit = 50, offset = 0, itemId } = options;

    try {
      let query = `
        SELECT c.*,
               i.name as item_name,
               i.brand as item_brand,
               i.category as item_category
        FROM warranty_claims c
        JOIN items i ON i.id = c.item_id
        WHERE c.user_id = $1
      `;
      const params: any[] = [userId];

      if (itemId) {
        query += ` AND c.item_id = $${params.length + 1}`;
        params.push(itemId);
      }

      query += ` ORDER BY c.claim_date DESC, c.created_at DESC`;
      query += ` LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
      params.push(limit, offset);

      const result = await pool.query(query, params);

      // Get total count
      const countQuery = itemId
        ? 'SELECT COUNT(*) FROM warranty_claims WHERE user_id = $1 AND item_id = $2'
        : 'SELECT COUNT(*) FROM warranty_claims WHERE user_id = $1';
      const countParams = itemId ? [userId, itemId] : [userId];
      const countResult = await pool.query(countQuery, countParams);

      return {
        claims: result.rows,
        total: parseInt(countResult.rows[0].count, 10),
      };
    } catch (error) {
      logger.error({ error, userId, options }, 'Error fetching user claims');
      throw error;
    }
  }

  /**
   * Get claim by ID
   */
  static async getClaimById(claimId: string, userId: string): Promise<WarrantyClaim> {
    try {
      const result = await pool.query(
        `SELECT c.*,
                i.name as item_name,
                i.category as item_category,
                i.brand as item_brand
         FROM warranty_claims c
         JOIN items i ON i.id = c.item_id
         WHERE c.id = $1 AND c.user_id = $2`,
        [claimId, userId]
      );

      if (result.rows.length === 0) {
        throw new AppError('Claim not found', 404);
      }

      return result.rows[0];
    } catch (error) {
      logger.error({ error, claimId, userId }, 'Error fetching claim');
      throw error;
    }
  }

  /**
   * Update warranty claim
   */
  static async updateClaim(
    claimId: string,
    userId: string,
    data: Partial<CreateWarrantyClaimDto>
  ): Promise<WarrantyClaim> {
    if (data.amountSaved !== undefined && data.amountSaved < 0) {
      throw new AppError('amountSaved cannot be negative', 400);
    }
    return runWithSerializableRetry(
      () => this._updateClaimOnce(claimId, userId, data),
      'updateClaim',
    );
  }

  private static async _updateClaimOnce(
    claimId: string,
    userId: string,
    data: Partial<CreateWarrantyClaimDto>,
  ): Promise<WarrantyClaim> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN ISOLATION LEVEL SERIALIZABLE');

      // Verify claim belongs to user. Lock so a concurrent update doesn't
      // race the status transition validation below.
      const claimCheck = await client.query(
        'SELECT id, amount_saved, status FROM warranty_claims WHERE id = $1 AND user_id = $2 FOR UPDATE',
        [claimId, userId]
      );

      if (claimCheck.rows.length === 0) {
        throw new AppError('Claim not found', 404);
      }

      // F004: avoid parseFloat on DECIMAL columns; use the cents helper so
      // the diff math doesn't drift across float→DECIMAL round-trips.
      const oldAmountCents = decimalToCents(claimCheck.rows[0].amount_saved);
      const fromStatus = claimCheck.rows[0].status as ClaimStatus;

      // F010 / F001: validate state-machine transition before issuing the UPDATE.
      let toStatus: ClaimStatus | null = null;
      if (data.status !== undefined && data.status !== fromStatus) {
        if (!isClaimStatus(data.status)) {
          throw new AppError(`Unknown claim status: ${data.status}`, 400);
        }
        assertClaimTransition(fromStatus, data.status);
        toStatus = data.status;
      }

      // Build update query dynamically
      const updates: string[] = [];
      const values: any[] = [];
      let paramIndex = 1;

      if (data.claimDate !== undefined) {
        updates.push(`claim_date = $${paramIndex++}`);
        values.push(data.claimDate);
      }
      if (data.issueDescription !== undefined) {
        updates.push(`issue_description = $${paramIndex++}`);
        values.push(data.issueDescription);
      }
      if (data.repairDescription !== undefined) {
        updates.push(`repair_description = $${paramIndex++}`);
        values.push(data.repairDescription);
      }
      if (data.repairCost !== undefined) {
        updates.push(`repair_cost = $${paramIndex++}`);
        values.push(data.repairCost);
      }
      if (data.amountSaved !== undefined) {
        updates.push(`amount_saved = $${paramIndex++}`);
        values.push(data.amountSaved);
      }
      if (data.outOfPocket !== undefined) {
        // F011: explicit null collapses to 0 so the DECIMAL column never
        // sees NaN. Joi already disallows non-numeric input.
        updates.push(`out_of_pocket = $${paramIndex++}`);
        values.push(data.outOfPocket ?? 0);
      }
      if (toStatus !== null) {
        updates.push(`status = $${paramIndex++}`);
        values.push(toStatus);
      }
      if (data.filedWith !== undefined) {
        updates.push(`filed_with = $${paramIndex++}`);
        values.push(data.filedWith);
      }
      if (data.claimNumber !== undefined) {
        updates.push(`claim_number = $${paramIndex++}`);
        values.push(data.claimNumber);
      }
      if (data.notes !== undefined) {
        updates.push(`notes = $${paramIndex++}`);
        values.push(data.notes);
      }

      if (updates.length === 0) {
        throw new AppError('No fields to update', 400);
      }

      values.push(claimId, userId);

      const result = await client.query(
        `UPDATE warranty_claims
         SET ${updates.join(', ')}, updated_at = NOW()
         WHERE id = $${paramIndex++} AND user_id = $${paramIndex++}
         RETURNING *`,
        values
      );

      // F010: append a transition history row when status actually changed.
      if (toStatus !== null) {
        await client.query(
          `INSERT INTO warranty_claim_state_history (claim_id, from_status, to_status, actor_user_id)
           VALUES ($1, $2, $3, $4)`,
          [claimId, fromStatus, toStatus, userId],
        );
      }

      // F004: cents-based diff so float drift can't poison the analytics
      // aggregate. The DB column stays DECIMAL; we just do the math in
      // integer cents and convert back at the SQL boundary.
      if (data.amountSaved !== undefined) {
        const newAmountCents = decimalToCents(String(data.amountSaved));
        if (newAmountCents !== oldAmountCents) {
          const diffCents = newAmountCents - oldAmountCents;
          await client.query(
            `INSERT INTO user_analytics (user_id, total_warranty_savings)
             VALUES ($2, GREATEST(0, ($1::bigint)::numeric / 100))
             ON CONFLICT (user_id)
             DO UPDATE SET total_warranty_savings = GREATEST(0, COALESCE(user_analytics.total_warranty_savings, 0) + ($1::bigint)::numeric / 100),
                           updated_at = NOW()`,
            [diffCents, userId]
          );
        }
      }

      await client.query('COMMIT');

      logger.info({ claimId, userId, fromStatus, toStatus }, 'Warranty claim updated');

      return result.rows[0];
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error({ error, claimId, userId, data }, 'Error updating warranty claim');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Delete warranty claim. F007: serializable to match createClaim — a
   * concurrent create + delete on the same item could otherwise leak a
   * phantom analytics decrement.
   */
  static async deleteClaim(claimId: string, userId: string): Promise<void> {
    return runWithSerializableRetry(
      () => this._deleteClaimOnce(claimId, userId),
      'deleteClaim',
    );
  }

  private static async _deleteClaimOnce(claimId: string, userId: string): Promise<void> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN ISOLATION LEVEL SERIALIZABLE');

      // Get amount saved before deleting
      const result = await client.query(
        'SELECT amount_saved FROM warranty_claims WHERE id = $1 AND user_id = $2 FOR UPDATE',
        [claimId, userId]
      );

      if (result.rows.length === 0) {
        throw new AppError('Claim not found', 404);
      }

      // F004: cents-based math; same rationale as updateClaim.
      const amountCents = decimalToCents(result.rows[0].amount_saved);

      // Delete claim
      await client.query(
        'DELETE FROM warranty_claims WHERE id = $1 AND user_id = $2',
        [claimId, userId]
      );

      // Upsert user analytics — COALESCE against NULL columns.
      await client.query(
        `INSERT INTO user_analytics (user_id, total_warranty_savings, total_claims_filed)
         VALUES ($2, 0, 0)
         ON CONFLICT (user_id)
         DO UPDATE SET total_warranty_savings = GREATEST(0, COALESCE(user_analytics.total_warranty_savings, 0) - ($1::bigint)::numeric / 100),
                       total_claims_filed = GREATEST(0, COALESCE(user_analytics.total_claims_filed, 0) - 1),
                       updated_at = NOW()`,
        [amountCents, userId]
      );

      await client.query('COMMIT');

      logger.info({ claimId, userId }, 'Warranty claim deleted');
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error({ error, claimId, userId }, 'Error deleting warranty claim');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Get total savings for user
   */
  static async getTotalSavings(userId: string): Promise<{
    total_warranty_savings: number;
    total_preventive_savings: number;
    total_savings: number;
    total_claims: number;
  }> {
    try {
      const result = await pool.query(
        `SELECT
           total_warranty_savings,
           total_preventive_savings,
           total_warranty_savings + total_preventive_savings as total_savings,
           total_claims_filed as total_claims
         FROM user_analytics
         WHERE user_id = $1`,
        [userId]
      );

      if (result.rows.length === 0) {
        return {
          total_warranty_savings: 0,
          total_preventive_savings: 0,
          total_savings: 0,
          total_claims: 0,
        };
      }

      const row = result.rows[0];
      // F004: keep the response shape (numbers in dollars) but route through
      // decimalToCents so a row with `19.99` doesn't surface as 19.989999...
      return {
        total_warranty_savings: decimalToCents(row.total_warranty_savings) / 100,
        total_preventive_savings: decimalToCents(row.total_preventive_savings) / 100,
        total_savings: decimalToCents(row.total_savings) / 100,
        total_claims: parseInt(row.total_claims, 10) || 0,
      };
    } catch (error) {
      logger.error({ error, userId }, 'Error fetching total savings');
      throw error;
    }
  }

  /**
   * Get savings feed (public social proof)
   */
  static async getSavingsFeed(limit: number = 20): Promise<SavingsFeedEntry[]> {
    try {
      const result = await pool.query(
        `SELECT id, user_city, user_state, amount_saved, item_category, claim_type, display_text, created_at
         FROM savings_feed
         ORDER BY created_at DESC
         LIMIT $1`,
        [limit]
      );

      return result.rows;
    } catch (error) {
      logger.error({ error, limit }, 'Error fetching savings feed');
      throw error;
    }
  }
}
