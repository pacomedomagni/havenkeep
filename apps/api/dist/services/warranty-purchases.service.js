"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.WarrantyPurchasesService = void 0;
const db_1 = require("../db");
const logger_1 = require("../utils/logger");
const errors_1 = require("../utils/errors");
class WarrantyPurchasesService {
    /**
     * Get all warranty purchases for a user with pagination and optional filters
     */
    static async getUserPurchases(userId, options = {}) {
        const { itemId, status } = options;
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
            const params = [userId];
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
            const result = await db_1.pool.query(query, params);
            // Get total count
            let countQuery = 'SELECT COUNT(*) FROM warranty_purchases WHERE user_id = $1';
            const countParams = [userId];
            if (itemId) {
                countQuery += ` AND item_id = $${countParams.length + 1}`;
                countParams.push(itemId);
            }
            if (status) {
                countQuery += ` AND status = $${countParams.length + 1}`;
                countParams.push(status);
            }
            const countResult = await db_1.pool.query(countQuery, countParams);
            return {
                purchases: result.rows,
                total: parseInt(countResult.rows[0].count, 10),
            };
        }
        catch (error) {
            logger_1.logger.error({ error, userId, options }, 'Error fetching user warranty purchases');
            throw error;
        }
    }
    /**
     * Get a single warranty purchase by ID with ownership check
     */
    static async getPurchaseById(purchaseId, userId) {
        try {
            const result = await db_1.pool.query(`SELECT wp.*,
                i.name as item_name,
                i.category as item_category,
                i.brand as item_brand,
                i.model_number as item_model_number
         FROM warranty_purchases wp
         JOIN items i ON i.id = wp.item_id
         WHERE wp.id = $1 AND wp.user_id = $2`, [purchaseId, userId]);
            if (result.rows.length === 0) {
                throw new errors_1.AppError('Warranty purchase not found', 404);
            }
            return result.rows[0];
        }
        catch (error) {
            logger_1.logger.error({ error, purchaseId, userId }, 'Error fetching warranty purchase');
            throw error;
        }
    }
    /**
     * Create a new warranty purchase
     */
    static async createPurchase(userId, data) {
        const client = await db_1.pool.connect();
        try {
            // BE-18/MED-12: Validate durationMonths is within acceptable range (1-240 months / 20 years)
            if (data.durationMonths !== undefined) {
                if (data.durationMonths < 1 || data.durationMonths > 240) {
                    throw new errors_1.AppError('durationMonths must be between 1 and 240', 400);
                }
            }
            await client.query('BEGIN');
            // Check for duplicate active warranty on the same item
            const duplicateCheck = await client.query(`SELECT id FROM warranty_purchases
         WHERE item_id = $1 AND user_id = $2 AND status = 'active' FOR UPDATE`, [data.itemId, userId]);
            if (duplicateCheck.rows.length > 0) {
                throw new errors_1.AppError('An active extended warranty already exists for this item', 409);
            }
            // Verify item belongs to user
            const itemCheck = await client.query('SELECT id FROM items WHERE id = $1 AND user_id = $2', [data.itemId, userId]);
            if (itemCheck.rows.length === 0) {
                throw new errors_1.AppError('Item not found or does not belong to user', 404);
            }
            // Calculate expires_at from startsAt + durationMonths
            // Uses safe month addition to handle overflow (e.g., Jan 31 + 1 month = Feb 28)
            const startsAt = new Date(data.startsAt);
            const expiresAt = new Date(startsAt);
            expiresAt.setMonth(expiresAt.getMonth() + data.durationMonths);
            // Clamp day to avoid month overflow (e.g., Jan 31 + 1 month should be Feb 28, not Mar 3)
            const expectedMonth = (startsAt.getMonth() + data.durationMonths) % 12;
            if (expiresAt.getMonth() !== expectedMonth) {
                expiresAt.setDate(0); // Roll back to the last day of the previous month
            }
            const result = await client.query(`INSERT INTO warranty_purchases (
          item_id, user_id, provider, plan_name, external_policy_id,
          duration_months, starts_at, expires_at, coverage_details,
          price, deductible, claim_limit, commission_amount, commission_rate,
          stripe_payment_intent_id, status
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
        RETURNING *`, [
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
                data.commissionRate || null,
                data.stripePaymentIntentId || null,
                'active',
            ]);
            const purchase = result.rows[0];
            await client.query('COMMIT');
            logger_1.logger.info({ purchaseId: purchase.id, userId, itemId: data.itemId }, 'Warranty purchase created');
            return purchase;
        }
        catch (error) {
            await client.query('ROLLBACK');
            logger_1.logger.error({ error, userId, data }, 'Error creating warranty purchase');
            throw error;
        }
        finally {
            client.release();
        }
    }
    /**
     * Cancel a warranty purchase
     */
    static async cancelPurchase(purchaseId, userId, reason) {
        const client = await db_1.pool.connect();
        try {
            await client.query('BEGIN');
            // Verify purchase belongs to user and is active
            const purchaseCheck = await client.query('SELECT id, status FROM warranty_purchases WHERE id = $1 AND user_id = $2', [purchaseId, userId]);
            if (purchaseCheck.rows.length === 0) {
                throw new errors_1.AppError('Warranty purchase not found', 404);
            }
            if (purchaseCheck.rows[0].status === 'cancelled') {
                throw new errors_1.AppError('Warranty purchase is already cancelled', 400);
            }
            if (purchaseCheck.rows[0].status === 'expired') {
                throw new errors_1.AppError('Cannot cancel an expired warranty purchase', 400);
            }
            const result = await client.query(`UPDATE warranty_purchases
         SET status = 'cancelled',
             cancelled_at = NOW(),
             cancellation_reason = $3,
             updated_at = NOW()
         WHERE id = $1 AND user_id = $2
         RETURNING *`, [purchaseId, userId, reason || null]);
            await client.query('COMMIT');
            logger_1.logger.info({ purchaseId, userId, reason }, 'Warranty purchase cancelled');
            return result.rows[0];
        }
        catch (error) {
            await client.query('ROLLBACK');
            logger_1.logger.error({ error, purchaseId, userId }, 'Error cancelling warranty purchase');
            throw error;
        }
        finally {
            client.release();
        }
    }
    /**
     * Get all active warranty coverage grouped by item
     */
    static async getActiveCoverage(userId) {
        try {
            const result = await db_1.pool.query(`SELECT
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
         ORDER BY i.name`, [userId]);
            return result.rows;
        }
        catch (error) {
            logger_1.logger.error({ error, userId }, 'Error fetching active warranty coverage');
            throw error;
        }
    }
    /**
     * Get warranties expiring within N days
     */
    static async getExpiringWarranties(userId, daysAhead = 30) {
        try {
            const result = await db_1.pool.query(`SELECT wp.*,
                i.name as item_name,
                i.category as item_category,
                i.brand as item_brand
         FROM warranty_purchases wp
         JOIN items i ON i.id = wp.item_id
         WHERE wp.user_id = $1
           AND wp.status = 'active'
           AND wp.expires_at >= CURRENT_DATE
           AND wp.expires_at <= CURRENT_DATE + INTERVAL '1 day' * $2
         ORDER BY wp.expires_at ASC`, [userId, daysAhead]);
            return result.rows;
        }
        catch (error) {
            logger_1.logger.error({ error, userId, daysAhead }, 'Error fetching expiring warranties');
            throw error;
        }
    }
    /**
     * Expire all overdue active warranties in a single batch update.
     * Designed to be called from a daily scheduled job.
     */
    static async expireOverdueWarranties() {
        try {
            const result = await db_1.pool.query(`UPDATE warranty_purchases
         SET status = 'expired', updated_at = NOW()
         WHERE status = 'active' AND expires_at < CURRENT_DATE
         RETURNING id`);
            const count = result.rowCount ?? 0;
            if (count > 0) {
                logger_1.logger.info({ count }, 'Expired overdue warranty purchases');
            }
            return count;
        }
        catch (error) {
            logger_1.logger.error({ error }, 'Error expiring overdue warranty purchases');
            throw error;
        }
    }
}
exports.WarrantyPurchasesService = WarrantyPurchasesService;
//# sourceMappingURL=warranty-purchases.service.js.map