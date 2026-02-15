import { pool } from '../db';
import { logger } from '../utils/logger';
import { DashboardStats, UserAnalytics } from '../types/database.types';

export class StatsService {
  /**
   * Get dashboard statistics for user
   */
  static async getDashboardStats(userId: string): Promise<DashboardStats> {
    try {
      const result = await pool.query(
        'SELECT get_dashboard_stats($1) as stats',
        [userId]
      );

      return result.rows[0].stats;
    } catch (error) {
      logger.error({ error, userId }, 'Error fetching dashboard stats');
      throw error;
    }
  }

  /**
   * Calculate and update health score for user
   */
  static async calculateHealthScore(userId: string): Promise<number> {
    try {
      const result = await pool.query(
        'SELECT calculate_health_score($1) as score',
        [userId]
      );

      return result.rows[0].score;
    } catch (error) {
      logger.error({ error, userId }, 'Error calculating health score');
      throw error;
    }
  }

  /**
   * Get user analytics
   */
  static async getUserAnalytics(userId: string): Promise<UserAnalytics> {
    try {
      // Ensure analytics record exists
      await pool.query(
        `INSERT INTO user_analytics (user_id)
         VALUES ($1)
         ON CONFLICT (user_id) DO NOTHING`,
        [userId]
      );

      const result = await pool.query(
        'SELECT * FROM user_analytics WHERE user_id = $1',
        [userId]
      );

      return result.rows[0];
    } catch (error) {
      logger.error({ error, userId }, 'Error fetching user analytics');
      throw error;
    }
  }

  /**
   * Update user engagement metrics
   */
  static async trackEngagement(
    userId: string,
    event: {
      type: 'app_open' | 'session_start' | 'session_end';
      sessionDuration?: number;
    }
  ): Promise<void> {
    try {
      // Ensure analytics record exists
      await pool.query(
        `INSERT INTO user_analytics (user_id)
         VALUES ($1)
         ON CONFLICT (user_id) DO NOTHING`,
        [userId]
      );

      if (event.type === 'app_open') {
        await pool.query(
          `UPDATE user_analytics
           SET total_app_opens = total_app_opens + 1,
               last_active_at = NOW(),
               updated_at = NOW()
           WHERE user_id = $1`,
          [userId]
        );
      } else if (event.type === 'session_start') {
        await pool.query(
          `UPDATE user_analytics
           SET total_sessions = total_sessions + 1,
               last_active_at = NOW(),
               updated_at = NOW()
           WHERE user_id = $1`,
          [userId]
        );
      } else if (event.type === 'session_end' && event.sessionDuration) {
        // Running average calculation: we use (total_sessions - 1) to get the previous
        // count of sessions (before the current one was incremented by session_start),
        // then divide by total_sessions. GREATEST(total_sessions, 1) is a defensive
        // guard against division by zero in case a session_end event arrives without
        // a preceding session_start (e.g., due to a race condition or missed event).
        // Under normal flow, total_sessions is always >= 1 after session_start increments it.
        await pool.query(
          `UPDATE user_analytics
           SET avg_session_duration_seconds =
               ((avg_session_duration_seconds * (total_sessions - 1)) + $2) / GREATEST(total_sessions, 1),
               updated_at = NOW()
           WHERE user_id = $1`,
          [userId, event.sessionDuration]
        );
      }

      logger.debug({ userId, event }, 'Engagement tracked');
    } catch (error) {
      logger.error({ error, userId, event }, 'Error tracking engagement');
      // Don't throw - analytics failures shouldn't break the app
    }
  }

  /**
   * Get items needing attention
   */
  static async getItemsNeedingAttention(userId: string, limit: number = 20): Promise<any[]> {
    try {
      const result = await pool.query(
        `SELECT
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
         LIMIT $2`,
        [userId, limit]
      );

      return result.rows;
    } catch (error) {
      logger.error({ error, userId }, 'Error fetching items needing attention');
      throw error;
    }
  }

  /**
   * Get health score breakdown/components
   *
   * NOTE: The overall `score` is computed by the DB function `calculate_health_score`,
   * while the `components` array is assembled in JS below. These two calculations
   * can drift out of sync if one is updated without the other. When changing the
   * scoring logic, make sure both the DB function and the JS component breakdown
   * are updated together to keep them consistent.
   */
  static async getHealthScoreBreakdown(userId: string): Promise<{
    score: number;
    components: Array<{
      name: string;
      points: number;
      max_points: number;
      status: 'good' | 'warning' | 'needs_improvement';
      suggestion?: string;
    }>;
  }> {
    try {
      const analytics = await this.getUserAnalytics(userId);
      const score = await this.calculateHealthScore(userId);

      // Get item counts for breakdown
      const itemStats = await pool.query(
        `SELECT
           COUNT(*) as total_items,
           COUNT(*) FILTER (WHERE warranty_end_date > CURRENT_DATE) as active_warranties,
           COUNT(*) FILTER (WHERE warranty_end_date <= CURRENT_DATE) as expired_warranties,
           COUNT(DISTINCT CASE WHEN d.id IS NOT NULL THEN i.id END) as documented_items
         FROM items i
         LEFT JOIN documents d ON d.item_id = i.id
         WHERE i.user_id = $1 AND i.is_archived = FALSE`,
        [userId]
      );

      const stats = itemStats.rows[0];
      const totalItems = parseInt(stats.total_items, 10);
      const activeWarranties = parseInt(stats.active_warranties, 10);
      const expiredWarranties = parseInt(stats.expired_warranties, 10);
      const documentedItems = parseInt(stats.documented_items, 10);

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
          points: Math.min(analytics.total_maintenance_completed, 15),
          max_points: 15,
          status: analytics.total_maintenance_completed >= 10 ? 'good' :
                  analytics.total_maintenance_completed >= 5 ? 'warning' : 'needs_improvement',
          suggestion: analytics.total_maintenance_completed < 10 ? 'Complete regular maintenance tasks' : undefined,
        },
        {
          name: 'Expired Warranties',
          points: Math.max(0, 10 - (expiredWarranties * 2)),
          max_points: 10,
          status: expiredWarranties === 0 ? 'good' : expiredWarranties <= 2 ? 'warning' : 'needs_improvement',
          suggestion: expiredWarranties > 0 ? `${expiredWarranties} items have expired warranties. Consider extending or replacing.` : undefined,
        },
      ];

      return {
        score,
        components: components as any,
      };
    } catch (error) {
      logger.error({ error, userId }, 'Error getting health score breakdown');
      throw error;
    }
  }

  /**
   * Track feature usage
   */
  static async trackFeatureUsage(
    userId: string,
    feature:
      | 'email_scan'
      | 'manual_add'
      | 'email_add'
      | 'barcode_add'
      | 'document_upload'
      | 'report_generated'
      | 'claim_filed'
  ): Promise<void> {
    try {
      // Ensure analytics record exists
      await pool.query(
        `INSERT INTO user_analytics (user_id)
         VALUES ($1)
         ON CONFLICT (user_id) DO NOTHING`,
        [userId]
      );

      const fieldMap: Record<string, string> = {
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
        logger.warn({ feature }, 'Unknown feature for tracking');
        return;
      }

      // Use explicit column references instead of interpolation for safety
      const updateQueries: Record<string, string> = {
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
        logger.warn({ feature, field }, 'Unknown analytics field');
        return;
      }

      await pool.query(updateSql, [userId]);

      // Update engagement flags
      if (feature === 'email_scan') {
        await pool.query(
          `UPDATE user_analytics
           SET has_scanned_email = TRUE,
               updated_at = NOW()
           WHERE user_id = $1`,
          [userId]
        );
      } else if (feature === 'claim_filed') {
        await pool.query(
          `UPDATE user_analytics
           SET has_filed_claim = TRUE,
               updated_at = NOW()
           WHERE user_id = $1`,
          [userId]
        );
      } else if (['manual_add', 'email_add', 'barcode_add'].includes(feature)) {
        await pool.query(
          `UPDATE user_analytics
           SET has_added_first_item = TRUE,
               updated_at = NOW()
           WHERE user_id = $1`,
          [userId]
        );
      }

      logger.debug({ userId, feature }, 'Feature usage tracked');
    } catch (error) {
      logger.error({ error, userId, feature }, 'Error tracking feature usage');
      // Don't throw - analytics failures shouldn't break the app
    }
  }
}
