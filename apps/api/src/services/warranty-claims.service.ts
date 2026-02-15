import { pool } from '../db';
import { logger } from '../utils/logger';
import { WarrantyClaim, CreateWarrantyClaimDto, SavingsFeedEntry } from '../types/database.types';
import { AppError } from '../utils/errors';

export class WarrantyClaimsService {
  /**
   * Create a new warranty claim
   */
  static async createClaim(
    userId: string,
    data: CreateWarrantyClaimDto
  ): Promise<WarrantyClaim> {
    const client = await pool.connect();

    try {
      // BE-17: Validate amount_saved is non-negative
      if (data.amount_saved !== undefined && data.amount_saved < 0) {
        throw new AppError('amount_saved cannot be negative', 400);
      }

      await client.query('BEGIN ISOLATION LEVEL SERIALIZABLE');

      // Verify item belongs to user
      const itemCheck = await client.query(
        'SELECT id FROM items WHERE id = $1 AND user_id = $2',
        [data.item_id, userId]
      );

      if (itemCheck.rows.length === 0) {
        throw new AppError('Item not found or does not belong to user', 404);
      }

      // Create claim
      const result = await client.query(
        `INSERT INTO warranty_claims (
          item_id, user_id, claim_date, issue_description, repair_description,
          repair_cost, amount_saved, out_of_pocket, status, filed_with, claim_number, notes
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
        RETURNING *`,
        [
          data.item_id,
          userId,
          data.claim_date || new Date(),
          data.issue_description,
          data.repair_description,
          data.repair_cost,
          data.amount_saved,
          data.out_of_pocket || 0,
          data.status || 'completed',
          data.filed_with,
          data.claim_number,
          data.notes,
        ]
      );

      const claim = result.rows[0];

      // Update user analytics
      await client.query(
        `UPDATE user_analytics
         SET total_warranty_savings = total_warranty_savings + $1,
             total_claims_filed = total_claims_filed + 1,
             has_filed_claim = TRUE,
             updated_at = NOW()
         WHERE user_id = $2`,
        [data.amount_saved, userId]
      );

      // Add to savings feed (anonymized)
      const userLocation = await client.query(
        `SELECT h.city, h.state
         FROM items i
         JOIN homes h ON h.id = i.home_id
         WHERE i.id = $1`,
        [data.item_id]
      );

      if (userLocation.rows.length > 0) {
        const { city, state } = userLocation.rows[0];

        await client.query(
          `INSERT INTO savings_feed (user_city, user_state, amount_saved, item_category, claim_type, display_text)
           SELECT $1, $2, $3, i.category, 'Warranty claim',
                  $4 || ' just saved $' || $3 || ' on a ' || i.category || ' repair'
           FROM items i
           WHERE i.id = $5`,
          [city, state, data.amount_saved, city, data.item_id]
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
    const client = await pool.connect();

    try {
      // BE-17: Validate amount_saved is non-negative
      if (data.amount_saved !== undefined && data.amount_saved < 0) {
        throw new AppError('amount_saved cannot be negative', 400);
      }

      await client.query('BEGIN');

      // Verify claim belongs to user
      const claimCheck = await client.query(
        'SELECT id, amount_saved FROM warranty_claims WHERE id = $1 AND user_id = $2',
        [claimId, userId]
      );

      if (claimCheck.rows.length === 0) {
        throw new AppError('Claim not found', 404);
      }

      const oldAmountSaved = parseFloat(claimCheck.rows[0].amount_saved);

      // Build update query dynamically
      const updates: string[] = [];
      const values: any[] = [];
      let paramIndex = 1;

      if (data.claim_date !== undefined) {
        updates.push(`claim_date = $${paramIndex++}`);
        values.push(data.claim_date);
      }
      if (data.issue_description !== undefined) {
        updates.push(`issue_description = $${paramIndex++}`);
        values.push(data.issue_description);
      }
      if (data.repair_description !== undefined) {
        updates.push(`repair_description = $${paramIndex++}`);
        values.push(data.repair_description);
      }
      if (data.repair_cost !== undefined) {
        updates.push(`repair_cost = $${paramIndex++}`);
        values.push(data.repair_cost);
      }
      if (data.amount_saved !== undefined) {
        updates.push(`amount_saved = $${paramIndex++}`);
        values.push(data.amount_saved);
      }
      if (data.out_of_pocket !== undefined) {
        updates.push(`out_of_pocket = $${paramIndex++}`);
        values.push(data.out_of_pocket);
      }
      if (data.status !== undefined) {
        updates.push(`status = $${paramIndex++}`);
        values.push(data.status);
      }
      if (data.filed_with !== undefined) {
        updates.push(`filed_with = $${paramIndex++}`);
        values.push(data.filed_with);
      }
      if (data.claim_number !== undefined) {
        updates.push(`claim_number = $${paramIndex++}`);
        values.push(data.claim_number);
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

      // Update user analytics if amount_saved changed
      if (data.amount_saved !== undefined && data.amount_saved !== oldAmountSaved) {
        const diff = data.amount_saved - oldAmountSaved;
        await client.query(
          `UPDATE user_analytics
           SET total_warranty_savings = total_warranty_savings + $1,
               updated_at = NOW()
           WHERE user_id = $2`,
          [diff, userId]
        );
      }

      await client.query('COMMIT');

      logger.info({ claimId, userId }, 'Warranty claim updated');

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
   * Delete warranty claim
   */
  static async deleteClaim(claimId: string, userId: string): Promise<void> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // Get amount saved before deleting
      const result = await client.query(
        'SELECT amount_saved FROM warranty_claims WHERE id = $1 AND user_id = $2',
        [claimId, userId]
      );

      if (result.rows.length === 0) {
        throw new AppError('Claim not found', 404);
      }

      const amountSaved = parseFloat(result.rows[0].amount_saved);

      // Delete claim
      await client.query(
        'DELETE FROM warranty_claims WHERE id = $1 AND user_id = $2',
        [claimId, userId]
      );

      // Update user analytics
      await client.query(
        `UPDATE user_analytics
         SET total_warranty_savings = GREATEST(0, total_warranty_savings - $1),
             total_claims_filed = GREATEST(0, total_claims_filed - 1),
             updated_at = NOW()
         WHERE user_id = $2`,
        [amountSaved, userId]
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

      return result.rows[0];
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
