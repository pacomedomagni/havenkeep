"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.StatsService = void 0;
const db_1 = require("../db");
const logger_1 = require("../utils/logger");
class StatsService {
    /**
     * Get dashboard statistics for user
     */
    static async getDashboardStats(userId) {
        try {
            const result = await db_1.pool.query('SELECT get_dashboard_stats($1) as stats', [userId]);
            return result.rows[0].stats;
        }
        catch (error) {
            logger_1.logger.error({ error, userId }, 'Error fetching dashboard stats');
            throw error;
        }
    }
    /**
     * Calculate and update health score for user
     */
    static async calculateHealthScore(userId) {
        try {
            const result = await db_1.pool.query('SELECT calculate_health_score($1) as score', [userId]);
            return result.rows[0].score;
        }
        catch (error) {
            logger_1.logger.error({ error, userId }, 'Error calculating health score');
            throw error;
        }
    }
    /**
     * Get user analytics
     */
    static async getUserAnalytics(userId) {
        try {
            // Ensure analytics record exists
            await db_1.pool.query(`INSERT INTO user_analytics (user_id)
         VALUES ($1)
         ON CONFLICT (user_id) DO NOTHING`, [userId]);
            const result = await db_1.pool.query('SELECT * FROM user_analytics WHERE user_id = $1', [userId]);
            return result.rows[0];
        }
        catch (error) {
            logger_1.logger.error({ error, userId }, 'Error fetching user analytics');
            throw error;
        }
    }
    /**
     * Update user engagement metrics
     */
    static async trackEngagement(userId, event) {
        try {
            // Ensure analytics record exists
            await db_1.pool.query(`INSERT INTO user_analytics (user_id)
         VALUES ($1)
         ON CONFLICT (user_id) DO NOTHING`, [userId]);
            if (event.type === 'app_open') {
                await db_1.pool.query(`UPDATE user_analytics
           SET total_app_opens = total_app_opens + 1,
               last_active_at = NOW(),
               updated_at = NOW()
           WHERE user_id = $1`, [userId]);
            }
            else if (event.type === 'session_start') {
                await db_1.pool.query(`UPDATE user_analytics
           SET total_sessions = total_sessions + 1,
               last_active_at = NOW(),
               updated_at = NOW()
           WHERE user_id = $1`, [userId]);
            }
            else if (event.type === 'session_end' && event.sessionDuration) {
                // Running average calculation: we use (total_sessions - 1) to get the previous
                // count of sessions (before the current one was incremented by session_start),
                // then divide by total_sessions. GREATEST(total_sessions, 1) is a defensive
                // guard against division by zero in case a session_end event arrives without
                // a preceding session_start (e.g., due to a race condition or missed event).
                // Under normal flow, total_sessions is always >= 1 after session_start increments it.
                await db_1.pool.query(`UPDATE user_analytics
           SET avg_session_duration_seconds =
               ((avg_session_duration_seconds * (total_sessions - 1)) + $2) / GREATEST(total_sessions, 1),
               updated_at = NOW()
           WHERE user_id = $1`, [userId, event.sessionDuration]);
            }
            logger_1.logger.debug({ userId, event }, 'Engagement tracked');
        }
        catch (error) {
            logger_1.logger.error({ error, userId, event }, 'Error tracking engagement');
            // Don't throw - analytics failures shouldn't break the app
        }
    }
    /**
     * Get items needing attention
     */
    static async getItemsNeedingAttention(userId, limit = 20) {
        try {
            const result = await db_1.pool.query(`SELECT
           i.*,
           CASE
             WHEN i.warranty_end_date < CURRENT_DATE THEN 'expired'
             WHEN i.warranty_end_date <= CURRENT_DATE + INTERVAL '7 days' THEN 'expiring_urgent'
             WHEN i.warranty_end_date <= CURRENT_DATE + INTERVAL '30 days' THEN 'expiring_soon'
             WHEN i.warranty_end_date <= CURRENT_DATE + INTERVAL '90 days' THEN 'expiring_90_days'
           END as attention_reason,
           i.warranty_end_date - CURRENT_DATE as days_until_expiry
         FROM items i
         WHERE i.user_id = $1
           AND i.is_archived = FALSE
           AND i.warranty_end_date <= CURRENT_DATE + INTERVAL '90 days'
         ORDER BY i.warranty_end_date ASC
         LIMIT $2`, [userId, limit]);
            return result.rows;
        }
        catch (error) {
            logger_1.logger.error({ error, userId }, 'Error fetching items needing attention');
            throw error;
        }
    }
    /**
     * Get health score breakdown/components
     *
     * NOTE: The overall `score` is the single source of truth and is computed by
     * the DB function `calculate_health_score` (see migration 002_enhanced_features.sql).
     * The `components` array below mirrors that function's logic for display purposes.
     *
     * IMPORTANT: If the scoring logic changes, update BOTH the DB function AND the
     * component breakdown below to keep them consistent. The DB function is authoritative;
     * the JS breakdown is derived from the same inputs to show users how their score
     * breaks down.
     *
     * Current scoring formula (must match DB function):
     *   Items Tracked:         min(total_items * 2, 30)               max 30 pts
     *   Active Warranties:     min(active_warranties * 3, 25)         max 25 pts
     *   Documentation:         min(floor(documented/total * 20), 20)  max 20 pts
     *   Maintenance (6mo):     min(recent_maintenance_count, 15)      max 15 pts
     *   Expired Penalty:       -min(expired_count * 2, 10)            max -10 pts
     *   Final score clamped to [0, 100].
     */
    static async getHealthScoreBreakdown(userId) {
        try {
            const score = await this.calculateHealthScore(userId);
            // Get item counts for breakdown -- mirrors the queries used by
            // the DB function calculate_health_score (migration 002).
            const itemStats = await db_1.pool.query(`SELECT
           COUNT(*) as total_items,
           COUNT(*) FILTER (WHERE warranty_end_date >= CURRENT_DATE) as active_warranties,
           COUNT(*) FILTER (WHERE warranty_end_date < CURRENT_DATE) as expired_warranties,
           COUNT(DISTINCT CASE WHEN d.id IS NOT NULL THEN i.id END) as documented_items
         FROM items i
         LEFT JOIN documents d ON d.item_id = i.id
         WHERE i.user_id = $1 AND i.is_archived = FALSE`, [userId]);
            // Maintenance count: only tasks completed in the last 6 months,
            // matching the DB function's WHERE completed_date >= CURRENT_DATE - INTERVAL '6 months'.
            const maintenanceStats = await db_1.pool.query(`SELECT COUNT(*) as recent_maintenance_count
         FROM maintenance_history
         WHERE user_id = $1
           AND completed_date >= CURRENT_DATE - INTERVAL '6 months'`, [userId]);
            const stats = itemStats.rows[0];
            const totalItems = parseInt(stats.total_items, 10);
            const activeWarranties = parseInt(stats.active_warranties, 10);
            const expiredWarranties = parseInt(stats.expired_warranties, 10);
            const documentedItems = parseInt(stats.documented_items, 10);
            const recentMaintenanceCount = parseInt(maintenanceStats.rows[0].recent_maintenance_count, 10);
            const components = [
                {
                    name: 'Items Tracked',
                    points: Math.min(totalItems * 2, 30),
                    max_points: 30,
                    status: totalItems >= 15 ? 'good' : totalItems >= 10 ? 'warning' : 'needs_improvement',
                    suggestion: totalItems < 15 ? `Add ${15 - totalItems} more items to max out this component` : undefined,
                },
                {
                    name: 'Active Warranties',
                    points: Math.min(activeWarranties * 3, 25),
                    max_points: 25,
                    status: activeWarranties >= 8 ? 'good' : activeWarranties >= 5 ? 'warning' : 'needs_improvement',
                    suggestion: activeWarranties < 8 ? 'Register more items with active warranties' : undefined,
                },
                {
                    name: 'Documentation',
                    points: totalItems > 0 ? Math.min(Math.floor((documentedItems / totalItems) * 20), 20) : 0,
                    max_points: 20,
                    status: (documentedItems / Math.max(totalItems, 1)) >= 0.8 ? 'good' :
                        (documentedItems / Math.max(totalItems, 1)) >= 0.5 ? 'warning' : 'needs_improvement',
                    suggestion: documentedItems < totalItems ? `Upload receipts for ${totalItems - documentedItems} more items` : undefined,
                },
                {
                    name: 'Maintenance Completed',
                    points: Math.min(recentMaintenanceCount, 15),
                    max_points: 15,
                    status: recentMaintenanceCount >= 10 ? 'good' :
                        recentMaintenanceCount >= 5 ? 'warning' : 'needs_improvement',
                    suggestion: recentMaintenanceCount < 10 ? 'Complete regular maintenance tasks' : undefined,
                },
                {
                    name: 'Expired Warranties',
                    points: -Math.min(expiredWarranties * 2, 10),
                    max_points: 0,
                    status: expiredWarranties === 0 ? 'good' : expiredWarranties <= 2 ? 'warning' : 'needs_improvement',
                    suggestion: expiredWarranties > 0 ? `${expiredWarranties} items have expired warranties. Consider extending or replacing.` : undefined,
                },
            ];
            return {
                score,
                components: components,
            };
        }
        catch (error) {
            logger_1.logger.error({ error, userId }, 'Error getting health score breakdown');
            throw error;
        }
    }
    /**
     * Track feature usage
     */
    static async trackFeatureUsage(userId, feature) {
        try {
            // Ensure analytics record exists
            await db_1.pool.query(`INSERT INTO user_analytics (user_id)
         VALUES ($1)
         ON CONFLICT (user_id) DO NOTHING`, [userId]);
            const fieldMap = {
                email_scan: 'email_scans_completed',
                manual_add: 'items_added_manually',
                email_add: 'items_added_via_email',
                barcode_add: 'items_added_via_barcode',
                document_upload: 'documents_uploaded',
                report_generated: 'reports_generated',
                claim_filed: 'total_claims_filed',
            };
            const field = fieldMap[feature];
            if (!field) {
                throw new Error(`Unknown feature for tracking: ${feature}`);
            }
            // Use explicit column references instead of interpolation for safety
            const updateQueries = {
                email_scans_completed: `UPDATE user_analytics SET email_scans_completed = email_scans_completed + 1, updated_at = NOW() WHERE user_id = $1`,
                items_added_manually: `UPDATE user_analytics SET items_added_manually = items_added_manually + 1, updated_at = NOW() WHERE user_id = $1`,
                items_added_via_email: `UPDATE user_analytics SET items_added_via_email = items_added_via_email + 1, updated_at = NOW() WHERE user_id = $1`,
                items_added_via_barcode: `UPDATE user_analytics SET items_added_via_barcode = items_added_via_barcode + 1, updated_at = NOW() WHERE user_id = $1`,
                documents_uploaded: `UPDATE user_analytics SET documents_uploaded = documents_uploaded + 1, updated_at = NOW() WHERE user_id = $1`,
                reports_generated: `UPDATE user_analytics SET reports_generated = reports_generated + 1, updated_at = NOW() WHERE user_id = $1`,
                total_claims_filed: `UPDATE user_analytics SET total_claims_filed = total_claims_filed + 1, updated_at = NOW() WHERE user_id = $1`,
            };
            const updateSql = updateQueries[field];
            if (!updateSql) {
                throw new Error(`Unknown analytics field: ${field} (feature: ${feature})`);
            }
            await db_1.pool.query(updateSql, [userId]);
            // Update engagement flags
            if (feature === 'email_scan') {
                await db_1.pool.query(`UPDATE user_analytics
           SET has_scanned_email = TRUE,
               updated_at = NOW()
           WHERE user_id = $1`, [userId]);
            }
            else if (feature === 'claim_filed') {
                await db_1.pool.query(`UPDATE user_analytics
           SET has_filed_claim = TRUE,
               updated_at = NOW()
           WHERE user_id = $1`, [userId]);
            }
            else if (['manual_add', 'email_add', 'barcode_add'].includes(feature)) {
                await db_1.pool.query(`UPDATE user_analytics
           SET has_added_first_item = TRUE,
               updated_at = NOW()
           WHERE user_id = $1`, [userId]);
            }
            logger_1.logger.debug({ userId, feature }, 'Feature usage tracked');
        }
        catch (error) {
            logger_1.logger.error({ error, userId, feature }, 'Error tracking feature usage');
            // Don't throw - analytics failures shouldn't break the app
        }
    }
}
exports.StatsService = StatsService;
//# sourceMappingURL=stats.service.js.map