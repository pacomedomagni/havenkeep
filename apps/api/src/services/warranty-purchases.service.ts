import { pool } from '../db';
import { logger } from '../utils/logger';
import { WarrantyPurchase } from '../types/database.types';
import { AppError } from '../utils/errors';
import { addMonthsSafe } from '../utils/dates';
import { decimalToCents, dollarsToCents, commissionCents } from '../utils/money';
import { createStripeClient } from '../utils/stripe-client';

const stripe = createStripeClient();

/**
 * Compute prorated refund (cents) for a cancelled active warranty.
 * Refunds the unused fraction: priceCents * (daysRemaining / totalCoverageDays).
 * Callers cap to the captured charge amount; Stripe enforces the same.
 */
function proratedRefundCents(
  priceDollars: number,
  startsAt: Date,
  expiresAt: Date,
  cancelledAt: Date,
): number {
  const totalDays = Math.max(1, Math.round((expiresAt.getTime() - startsAt.getTime()) / 86_400_000));
  const usedDays = Math.max(0, Math.round((cancelledAt.getTime() - startsAt.getTime()) / 86_400_000));
  const remainingDays = Math.max(0, totalDays - usedDays);
  const fraction = remainingDays / totalDays;
  const cents = Math.round(priceDollars * 100 * fraction);
  return Math.max(0, cents);
}

interface CreateWarrantyPurchaseData {
  itemId: string;
  provider: string;
  planName: string;
  externalPolicyId?: string;
  durationMonths: number;
  startsAt: string;
  coverageDetails?: Record<string, any>;
  price: number;
  deductible?: number;
  claimLimit?: number;
  commissionAmount?: number;
  // F019: deliberately omitted — commission_rate is server-derived.
  stripePaymentIntentId?: string;
}

export class WarrantyPurchasesService {
  /**
   * Get all warranty purchases for a user with pagination and optional filters.
   *
   * 2.13: optional [homeId] scopes the rows + count to items in that home
   * so the mobile coverage tab agrees with the home-switcher.
   */
  static async getUserPurchases(
    userId: string,
    options: {
      limit?: number;
      offset?: number;
      itemId?: string;
      homeId?: string;
      status?: string;
    } = {}
  ): Promise<{ purchases: WarrantyPurchase[]; total: number }> {
    const { itemId, homeId, status } = options;
    // MED-2: Clamp pagination params to safe bounds
    const limit = Math.min(options.limit || 50, 100);
    const offset = Math.max(options.offset || 0, 0);

    try {
      let query = `
        SELECT wp.*,
               i.name as item_name,
               i.category as item_category,
               i.brand as item_brand,
               i.model_number as item_model_number
        FROM warranty_purchases wp
        JOIN items i ON i.id = wp.item_id
        WHERE wp.user_id = $1
      `;
      const params: any[] = [userId];

      if (itemId) {
        query += ` AND wp.item_id = $${params.length + 1}`;
        params.push(itemId);
      }
      if (homeId) {
        query += ` AND i.home_id = $${params.length + 1}`;
        params.push(homeId);
      }
      if (status) {
        query += ` AND wp.status = $${params.length + 1}`;
        params.push(status);
      }

      query += ` ORDER BY wp.purchase_date DESC, wp.created_at DESC`;
      query += ` LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
      params.push(limit, offset);

      const result = await pool.query(query, params);

      // Mirror the JOIN + filters in the count query so pagination.total
      // doesn't drift when the home filter narrows results.
      let countQuery = `
        SELECT COUNT(*)
          FROM warranty_purchases wp
          JOIN items i ON i.id = wp.item_id
         WHERE wp.user_id = $1
      `;
      const countParams: any[] = [userId];

      if (itemId) {
        countQuery += ` AND wp.item_id = $${countParams.length + 1}`;
        countParams.push(itemId);
      }
      if (homeId) {
        countQuery += ` AND i.home_id = $${countParams.length + 1}`;
        countParams.push(homeId);
      }
      if (status) {
        countQuery += ` AND wp.status = $${countParams.length + 1}`;
        countParams.push(status);
      }

      const countResult = await pool.query(countQuery, countParams);

      return {
        purchases: result.rows,
        total: parseInt(countResult.rows[0].count, 10),
      };
    } catch (error) {
      logger.error({ error, userId, options }, 'Error fetching user warranty purchases');
      throw error;
    }
  }

  /**
   * Get a single warranty purchase by ID with ownership check
   */
  static async getPurchaseById(purchaseId: string, userId: string): Promise<WarrantyPurchase> {
    try {
      const result = await pool.query(
        `SELECT wp.*,
                i.name as item_name,
                i.category as item_category,
                i.brand as item_brand,
                i.model_number as item_model_number
         FROM warranty_purchases wp
         JOIN items i ON i.id = wp.item_id
         WHERE wp.id = $1 AND wp.user_id = $2`,
        [purchaseId, userId]
      );

      if (result.rows.length === 0) {
        throw new AppError('Warranty purchase not found', 404);
      }

      return result.rows[0];
    } catch (error) {
      logger.error({ error, purchaseId, userId }, 'Error fetching warranty purchase');
      throw error;
    }
  }

  /**
   * Create a new warranty purchase
   *
   * F018: durationMonths is validated by Joi only (1..240). The duplicate
   * service-side bound is removed.
   * F017: startsAt may not be more than 1 year in the future.
   * F019: commissionRate is NEVER trusted from the client — derived from
   *       partner tier server-side. The DTO drops the field.
   * F020: stripe_payment_intent_id idempotency is enforced by the partial
   *       UNIQUE in migration 061; we surface a 409 if the same intent
   *       arrives twice.
   */
  static async createPurchase(
    userId: string,
    data: CreateWarrantyPurchaseData
  ): Promise<WarrantyPurchase> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // F017: startsAt sanity bound
      const startsAt = new Date(data.startsAt);
      const oneYearAhead = new Date();
      oneYearAhead.setUTCFullYear(oneYearAhead.getUTCFullYear() + 1);
      if (startsAt.getTime() > oneYearAhead.getTime()) {
        throw new AppError('startsAt cannot be more than 1 year in the future', 400);
      }

      // F016: a 'pending' purchase blocks a new one too — otherwise a user
      // can double-tap and end up with two policies once Stripe settles.
      const duplicateCheck = await client.query(
        `SELECT id, status FROM warranty_purchases
         WHERE item_id = $1 AND user_id = $2 AND status IN ('active', 'pending') FOR UPDATE`,
        [data.itemId, userId]
      );

      if (duplicateCheck.rows.length > 0) {
        throw new AppError('A warranty purchase for this item is already in progress', 409);
      }

      // F020: idempotency check on payment intent — surface a clean 409
      // before we hit the partial UNIQUE in migration 061.
      if (data.stripePaymentIntentId) {
        const existing = await client.query(
          `SELECT id FROM warranty_purchases
            WHERE user_id = $1 AND stripe_payment_intent_id = $2`,
          [userId, data.stripePaymentIntentId],
        );
        if (existing.rows.length > 0) {
          throw new AppError('Warranty purchase with this payment intent already exists', 409);
        }
      }

      // Verify item belongs to user and is not archived. Buying a warranty
      // on an archived item creates orphaned policy records that UI can't
      // render because the item is treated as historical.
      const itemCheck = await client.query(
        'SELECT id, is_archived FROM items WHERE id = $1 AND user_id = $2',
        [data.itemId, userId]
      );

      if (itemCheck.rows.length === 0) {
        throw new AppError('Item not found or does not belong to user', 404);
      }
      if (itemCheck.rows[0].is_archived) {
        throw new AppError('Cannot purchase a warranty for an archived item. Restore the item first.', 400);
      }

      const expiresAt = addMonthsSafe(startsAt, data.durationMonths);

      // F019: derive commissionRate server-side from the provider config or
      // existing partner row. We never read data.commissionRate from input.
      // For now we leave commissionRate NULL on direct purchases and let the
      // partner-attribution job populate it; F022 still uses the stored
      // value for cancel.
      const result = await client.query(
        `INSERT INTO warranty_purchases (
          item_id, user_id, provider, plan_name, external_policy_id,
          duration_months, starts_at, expires_at, coverage_details,
          price, deductible, claim_limit, commission_amount, commission_rate,
          stripe_payment_intent_id, status
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
        RETURNING *`,
        [
          data.itemId,
          userId,
          data.provider,
          data.planName,
          data.externalPolicyId || null,
          data.durationMonths,
          startsAt,
          expiresAt,
          data.coverageDetails ? JSON.stringify(data.coverageDetails) : null,
          data.price,
          data.deductible || 0,
          data.claimLimit || null,
          data.commissionAmount || null,
          // F019: never accept a client-supplied rate.
          null,
          data.stripePaymentIntentId || null,
          'active',
        ]
      );

      const purchase = result.rows[0];

      await client.query('COMMIT');

      logger.info({ purchaseId: purchase.id, userId, itemId: data.itemId }, 'Warranty purchase created');

      return purchase;
    } catch (error: any) {
      await client.query('ROLLBACK');
      // Surface migration 061 idempotency hits as a clean 409 if we ever
      // race past the explicit check above.
      if (error?.code === '23505') {
        throw new AppError('Warranty purchase with this payment intent already exists', 409);
      }
      logger.error({ error, userId, data }, 'Error creating warranty purchase');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Cancel a warranty purchase
   */
  static async cancelPurchase(
    purchaseId: string,
    userId: string,
    reason?: string
  ): Promise<WarrantyPurchase> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // Lock the row for the entire cancel + refund flow so a concurrent
      // cancel can't double-refund.
      const purchaseCheck = await client.query(
        `SELECT id, status, price, starts_at, expires_at, stripe_payment_intent_id,
                stripe_refund_id
           FROM warranty_purchases
          WHERE id = $1 AND user_id = $2
          FOR UPDATE`,
        [purchaseId, userId],
      );

      if (purchaseCheck.rows.length === 0) {
        throw new AppError('Warranty purchase not found', 404);
      }

      const existing = purchaseCheck.rows[0];

      if (existing.status === 'cancelled') {
        throw new AppError('Warranty purchase is already cancelled', 400);
      }

      if (existing.status === 'expired') {
        throw new AppError('Cannot cancel an expired warranty purchase', 400);
      }

      // Block cancel after a claim has been opened — the warranty has paid
      // out and the carrier won't honor a refund on used coverage.
      const hasClaim = await client.query(
        `SELECT 1 FROM warranty_claims WHERE item_id = (SELECT item_id FROM warranty_purchases WHERE id = $1) AND user_id = $2 LIMIT 1`,
        [purchaseId, userId],
      );
      if (hasClaim.rows.length > 0) {
        throw new AppError('Cannot cancel a warranty that has been claimed', 400);
      }

      const refundCents = proratedRefundCents(
        Number(existing.price),
        new Date(existing.starts_at),
        new Date(existing.expires_at),
        new Date(),
      );

      // Issue Stripe refund first when there's something to refund and we
      // have a payment_intent on file. If Stripe rejects, the cancel rolls
      // back so the user can retry.
      let stripeRefundId: string | null = existing.stripe_refund_id ?? null;
      if (refundCents > 0 && existing.stripe_payment_intent_id && !stripeRefundId) {
        try {
          const refund = await stripe.refunds.create(
            {
              payment_intent: existing.stripe_payment_intent_id,
              amount: refundCents,
              reason: 'requested_by_customer',
              metadata: { warranty_purchase_id: purchaseId, user_id: userId },
            },
            { idempotencyKey: `warranty-refund-${purchaseId}` },
          );
          stripeRefundId = refund.id;
        } catch (refundErr) {
          logger.error(
            { err: refundErr, purchaseId, userId, refundCents },
            'Stripe refund failed for warranty cancel — aborting',
          );
          throw new AppError('Refund failed; please try again or contact support', 502);
        }
      }

      const result = await client.query(
        `UPDATE warranty_purchases
            SET status = 'cancelled',
                cancelled_at = NOW(),
                cancellation_reason = $3,
                updated_at = NOW(),
                stripe_refund_id = $4,
                refund_amount_cents = $5,
                refunded_at = CASE WHEN $5::int > 0 THEN NOW() ELSE refunded_at END
          WHERE id = $1 AND user_id = $2
          RETURNING *`,
        [purchaseId, userId, reason || null, stripeRefundId, refundCents],
      );

      // F022: when the warranty is cancelled, mark any pending commission
      // attached to the same warranty purchase as 'cancelled' so partner
      // payouts don't include refunded sales. Settled commissions stay put
      // and ride the clawback path established in migration 030b.
      await client.query(
        `UPDATE partner_commissions
            SET status = 'cancelled', updated_at = NOW()
          WHERE warranty_purchase_id = $1
            AND status IN ('pending', 'approved')`,
        [purchaseId],
      );

      await client.query('COMMIT');

      logger.info({ purchaseId, userId, reason, refundCents, stripeRefundId }, 'Warranty purchase cancelled');

      return result.rows[0];
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error({ error, purchaseId, userId }, 'Error cancelling warranty purchase');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Get all active warranty coverage grouped by item
   */
  static async getActiveCoverage(userId: string): Promise<any[]> {
    try {
      const result = await pool.query(
        `SELECT
           i.id as item_id,
           i.name as item_name,
           i.category as item_category,
           i.brand as item_brand,
           json_agg(
             json_build_object(
               'id', wp.id,
               'provider', wp.provider,
               'plan_name', wp.plan_name,
               'starts_at', wp.starts_at,
               'expires_at', wp.expires_at,
               'coverage_details', wp.coverage_details,
               'price', wp.price,
               'deductible', wp.deductible,
               'claim_limit', wp.claim_limit,
               'duration_months', wp.duration_months
             ) ORDER BY wp.expires_at DESC
           ) as warranties
         FROM warranty_purchases wp
         JOIN items i ON i.id = wp.item_id
         WHERE wp.user_id = $1 AND wp.status = 'active'
         GROUP BY i.id, i.name, i.category, i.brand
         ORDER BY i.name`,
        [userId]
      );

      return result.rows;
    } catch (error) {
      logger.error({ error, userId }, 'Error fetching active warranty coverage');
      throw error;
    }
  }

  /**
   * Get warranties expiring within N days
   */
  static async getExpiringWarranties(
    userId: string,
    daysAhead: number = 30
  ): Promise<WarrantyPurchase[]> {
    try {
      const result = await pool.query(
        `SELECT wp.*,
                i.name as item_name,
                i.category as item_category,
                i.brand as item_brand
         FROM warranty_purchases wp
         JOIN items i ON i.id = wp.item_id
         WHERE wp.user_id = $1
           AND wp.status = 'active'
           AND wp.expires_at >= CURRENT_DATE
           AND wp.expires_at <= CURRENT_DATE + INTERVAL '1 day' * $2
         ORDER BY wp.expires_at ASC`,
        [userId, daysAhead]
      );

      return result.rows;
    } catch (error) {
      logger.error({ error, userId, daysAhead }, 'Error fetching expiring warranties');
      throw error;
    }
  }

  /**
   * Expire all overdue active warranties in a single batch update.
   * F013: emit a `warranty_expired` notification for each row that flips
   * from active → expired so the user knows the policy is no longer in
   * force. Designed to be called from a daily scheduled job.
   */
  static async expireOverdueWarranties(): Promise<number> {
    try {
      const result = await pool.query(
        `UPDATE warranty_purchases
         SET status = 'expired', updated_at = NOW()
         WHERE status = 'active' AND expires_at < CURRENT_DATE
         RETURNING id, user_id, item_id, provider, plan_name`
      );

      const count = result.rowCount ?? 0;
      if (count > 0) {
        logger.info({ count }, 'Expired overdue warranty purchases');

        // Emit a warranty_expired notification per expired row. Lazy-import
        // to avoid the warranty-purchases ↔ notifications circular import.
        const { NotificationsService } = await import('./notifications.service');
        for (const row of result.rows) {
          try {
            await NotificationsService.createNotification({
              user_id: row.user_id,
              item_id: row.item_id,
              type: 'warranty_expired',
              title: 'Extended warranty expired',
              body: `Your ${row.provider} ${row.plan_name} coverage just ended.`,
              data: { warranty_purchase_id: row.id },
            });
          } catch (notifyErr) {
            logger.error(
              { err: notifyErr, purchaseId: row.id },
              'Failed to emit warranty_expired notification (status flip persisted)',
            );
          }
        }
      }
      return count;
    } catch (error) {
      logger.error({ error }, 'Error expiring overdue warranty purchases');
      throw error;
    }
  }

  /**
   * Generate extended warranty quote plans for an item. Centralized here
   * so the route can stay thin and the math (cents-only, F014/F015) is
   * exercised by tests.
   *
   * F014: returns 0-priced plans when the item has no price (rather than
   *       NaN propagating into the response).
   * F015: math runs through dollarsToCents → integer arithmetic →
   *       centsToDecimal, never `priceFloat * 0.05 * 100`.
   */
  static generateQuotes(itemPriceDollars: unknown, ageInYears: number): Array<{
    provider: string;
    plan_name: string;
    duration_months: number;
    price: number;
    deductible: number;
  }> {
    const priceCents = (() => {
      try {
        return dollarsToCents(itemPriceDollars as any);
      } catch {
        return 0;
      }
    })();

    const plans = [
      { provider: 'HavenShield Basic',   plan_name: '1 Year Protection', duration_months: 12, price: commissionCents(priceCents, 0.05) / 100, deductible: 75 },
      { provider: 'HavenShield Plus',    plan_name: '2 Year Protection', duration_months: 24, price: commissionCents(priceCents, 0.08) / 100, deductible: 50 },
      { provider: 'HavenShield Premium', plan_name: '3 Year Protection', duration_months: 36, price: commissionCents(priceCents, 0.12) / 100, deductible: 0 },
    ];

    if (ageInYears > 5) {
      return plans.filter((p) => p.duration_months === 12);
    }
    return plans;
  }
}
