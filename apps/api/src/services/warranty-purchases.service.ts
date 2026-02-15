import { pool } from '../db';
import { logger } from '../utils/logger';
import { WarrantyPurchase } from '../types/database.types';
import { AppError } from '../utils/errors';

interface CreateWarrantyPurchaseData {
  item_id: string;
  provider: string;
  plan_name: string;
  external_policy_id?: string;
  duration_months: number;
  starts_at: string;
  coverage_details?: Record<string, any>;
  price: number;
  deductible?: number;
  claim_limit?: number;
  commission_amount?: number;
  commission_rate?: number;
  stripe_payment_intent_id?: string;
}

export class WarrantyPurchasesService {
  /**
   * Get all warranty purchases for a user with pagination and optional filters
   */
  static async getUserPurchases(
    userId: string,
    options: {
      limit?: number;
      offset?: number;
      itemId?: string;
      status?: string;
    } = {}
  ): Promise<{ purchases: WarrantyPurchase[]; total: number }> {
    const { itemId, status } = options;
    // MED-2: Clamp pagination params to safe bounds
    const limit = Math.min(options.limit || 50, 100);
    const offset = Math.max(options.offset || 0, 0);

    try {
      let query = `
        SELECT wp.*,
               i.name as item_name,
               i.category as item_category,
               i.brand as item_brand
        FROM warranty_purchases wp
        JOIN items i ON i.id = wp.item_id
        WHERE wp.user_id = $1
      `;
      const params: any[] = [userId];

      if (itemId) {
        query += ` AND wp.item_id = $${params.length + 1}`;
        params.push(itemId);
      }

      if (status) {
        query += ` AND wp.status = $${params.length + 1}`;
        params.push(status);
      }

      query += ` ORDER BY wp.purchase_date DESC, wp.created_at DESC`;
      query += ` LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
      params.push(limit, offset);

      const result = await pool.query(query, params);

      // Get total count
      let countQuery = 'SELECT COUNT(*) FROM warranty_purchases WHERE user_id = $1';
      const countParams: any[] = [userId];

      if (itemId) {
        countQuery += ` AND item_id = $${countParams.length + 1}`;
        countParams.push(itemId);
      }

      if (status) {
        countQuery += ` AND status = $${countParams.length + 1}`;
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
   */
  static async createPurchase(
    userId: string,
    data: CreateWarrantyPurchaseData
  ): Promise<WarrantyPurchase> {
    const client = await pool.connect();

    try {
      // BE-18/MED-12: Validate duration_months is within acceptable range (1-600 months / 50 years)
      if (data.duration_months !== undefined) {
        if (data.duration_months < 1 || data.duration_months > 600) {
          throw new AppError('duration_months must be between 1 and 600', 400);
        }
      }

      await client.query('BEGIN');

      // Verify item belongs to user
      const itemCheck = await client.query(
        'SELECT id FROM items WHERE id = $1 AND user_id = $2',
        [data.item_id, userId]
      );

      if (itemCheck.rows.length === 0) {
        throw new AppError('Item not found or does not belong to user', 404);
      }

      // Calculate expires_at from starts_at + duration_months
      const startsAt = new Date(data.starts_at);
      const expiresAt = new Date(startsAt);
      expiresAt.setMonth(expiresAt.getMonth() + data.duration_months);

      const result = await client.query(
        `INSERT INTO warranty_purchases (
          item_id, user_id, provider, plan_name, external_policy_id,
          duration_months, starts_at, expires_at, coverage_details,
          price, deductible, claim_limit, commission_amount, commission_rate,
          stripe_payment_intent_id, status
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
        RETURNING *`,
        [
          data.item_id,
          userId,
          data.provider,
          data.plan_name,
          data.external_policy_id || null,
          data.duration_months,
          startsAt,
          expiresAt,
          data.coverage_details ? JSON.stringify(data.coverage_details) : null,
          data.price,
          data.deductible || 0,
          data.claim_limit || null,
          data.commission_amount || null,
          data.commission_rate || null,
          data.stripe_payment_intent_id || null,
          'active',
        ]
      );

      const purchase = result.rows[0];

      await client.query('COMMIT');

      logger.info({ purchaseId: purchase.id, userId, itemId: data.item_id }, 'Warranty purchase created');

      return purchase;
    } catch (error) {
      await client.query('ROLLBACK');
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

      // Verify purchase belongs to user and is active
      const purchaseCheck = await client.query(
        'SELECT id, status FROM warranty_purchases WHERE id = $1 AND user_id = $2',
        [purchaseId, userId]
      );

      if (purchaseCheck.rows.length === 0) {
        throw new AppError('Warranty purchase not found', 404);
      }

      if (purchaseCheck.rows[0].status === 'cancelled') {
        throw new AppError('Warranty purchase is already cancelled', 400);
      }

      if (purchaseCheck.rows[0].status === 'expired') {
        throw new AppError('Cannot cancel an expired warranty purchase', 400);
      }

      const result = await client.query(
        `UPDATE warranty_purchases
         SET status = 'cancelled',
             cancelled_at = NOW(),
             cancellation_reason = $3,
             updated_at = NOW()
         WHERE id = $1 AND user_id = $2
         RETURNING *`,
        [purchaseId, userId, reason || null]
      );

      await client.query('COMMIT');

      logger.info({ purchaseId, userId, reason }, 'Warranty purchase cancelled');

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
   * Update warranty purchase status (internal method, e.g., for auto-expiring)
   */
  static async updatePurchaseStatus(
    purchaseId: string,
    status: 'active' | 'expired' | 'cancelled' | 'pending'
  ): Promise<WarrantyPurchase> {
    try {
      const result = await pool.query(
        `UPDATE warranty_purchases
         SET status = $2, updated_at = NOW()
         WHERE id = $1
         RETURNING *`,
        [purchaseId, status]
      );

      if (result.rows.length === 0) {
        throw new AppError('Warranty purchase not found', 404);
      }

      logger.info({ purchaseId, status }, 'Warranty purchase status updated');

      return result.rows[0];
    } catch (error) {
      logger.error({ error, purchaseId, status }, 'Error updating warranty purchase status');
      throw error;
    }
  }
}
