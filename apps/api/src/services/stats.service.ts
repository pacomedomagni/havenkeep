import { pool } from '../db';
import { logger } from '../utils/logger';
import { DashboardStats, UserAnalytics } from '../types/database.types';

// Cached health score is treated as fresh for this many seconds; after that
// the dashboard request triggers a recompute. Mutations to items, warranties,
// or maintenance call invalidateHealthScoreCache(userId) to force the next
// read to recompute even if still inside the TTL window.
const HEALTH_SCORE_CACHE_TTL_SEC = 600;

/**
 * F058: schema version stamped on the dashboard payload. Mobile + web
 * clients can guard against unexpected shape changes by refusing payloads
 * with a higher major version than they understand. Bump the major when
 * removing or renaming a field; bump minor when adding.
 */
export const DASHBOARD_SCHEMA_VERSION = '1.0.0';

export class StatsService {
  /**
   * Get dashboard statistics for user. Uses the cached health score when
   * fresh; only recomputes when the cache is missing/stale (audit Ch04-F048
   * — recomputing on every dashboard hit was thrashing the DB).
   */
  static async getDashboardStats(userId: string): Promise<DashboardStats> {
    try {
      const result = await pool.query(
        'SELECT get_dashboard_stats($1) as stats',
        [userId]
      );

      const stats: any = result.rows[0].stats || {};
      stats.health_score = await this.getCachedHealthScore(userId);
      // F058: stamp the schema version so a client can guard against shape
      // changes without falling over on an unknown field.
      stats.schema_version = DASHBOARD_SCHEMA_VERSION;
      return stats;
    } catch (error) {
      logger.error({ error, userId }, 'Error fetching dashboard stats');
      throw error;
    }
  }

  /**
   * Calculate and update health score for user, bypassing any cached value.
   */
  static async calculateHealthScore(userId: string): Promise<number> {
    try {
      const result = await pool.query(
        'SELECT calculate_health_score($1) as score',
        [userId]
      );

      const score = result.rows[0].score ?? 0;
      // Persist into the cache so the next dashboard read is free.
      await pool.query(
        `INSERT INTO user_analytics (user_id, cached_health_score, cached_health_score_at)
         VALUES ($1, $2, NOW())
         ON CONFLICT (user_id)
         DO UPDATE SET cached_health_score = EXCLUDED.cached_health_score,
                       cached_health_score_at = NOW(),
                       updated_at = NOW()`,
        [userId, score],
      );
      return score;
    } catch (error) {
      logger.error({ error, userId }, 'Error calculating health score');
      throw error;
    }
  }

  /**
   * Return cached health score if it's within the TTL, else recompute.
   */
  static async getCachedHealthScore(userId: string): Promise<number> {
    const cached = await pool.query(
      `SELECT cached_health_score, cached_health_score_at
         FROM user_analytics
        WHERE user_id = $1`,
      [userId],
    );
    const row = cached.rows[0];
    if (
      row?.cached_health_score != null &&
      row?.cached_health_score_at &&
      (Date.now() - new Date(row.cached_health_score_at).getTime()) / 1000 < HEALTH_SCORE_CACHE_TTL_SEC
    ) {
      return Number(row.cached_health_score);
    }
    return this.calculateHealthScore(userId);
  }

  /**
   * Force the next read to recompute. Called from item / warranty / claim /
   * maintenance mutations.
   */
  static async invalidateHealthScoreCache(userId: string): Promise<void> {
    await pool.query(
      `UPDATE user_analytics
          SET cached_health_score = NULL,
              cached_health_score_at = NULL
        WHERE user_id = $1`,
      [userId],
    );
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
        // Running average calculation: see GREATEST guard explanation above.
        // F052: also clamp the incoming session duration to >=0 so a clock
        // skew on the client (session_end timestamp older than session_start
        // because of NTP correction) can't yield a negative duration that
        // poisons the running average. Cap at 24h (86400s) defensively too;
        // a real session shouldn't exceed that.
        const clampedDuration = Math.max(0, Math.min(86400, event.sessionDuration));
        await pool.query(
          `UPDATE user_analytics
           SET avg_session_duration_seconds =
               GREATEST(0, ((avg_session_duration_seconds * (total_sessions - 1)) + $2) / GREATEST(total_sessions, 1)),
               updated_at = NOW()
           WHERE user_id = $1`,
          [userId, clampedDuration]
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
    // F055: bound the limit so a misbehaving caller can't ask for the full
    // table. 100 covers the dashboard "all attention" view; anything more
    // is paginated up the stack.
    const safeLimit = Math.min(Math.max(1, limit), 100);
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
        [userId, safeLimit]
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
      // F050: GET /stats/health-score must be read-only — it powers a
      // dashboard refresh on every screen open and shouldn't churn the
      // cache row on each call. Use the cached score; a force-recalc is
      // available via POST /stats/health-score/calculate.
      const score = await this.getCachedHealthScore(userId);

      // Get item counts for breakdown -- mirrors the queries used by
      // the DB function calculate_health_score (migration 002).
      const itemStats = await pool.query(
        `SELECT
           COUNT(*) as total_items,
           COUNT(*) FILTER (WHERE warranty_end_date >= CURRENT_DATE) as active_warranties,
           COUNT(*) FILTER (WHERE warranty_end_date < CURRENT_DATE) as expired_warranties,
           COUNT(DISTINCT CASE WHEN d.id IS NOT NULL THEN i.id END) as documented_items
         FROM items i
         LEFT JOIN documents d ON d.item_id = i.id
         WHERE i.user_id = $1 AND i.is_archived = FALSE`,
        [userId]
      );

      // Maintenance count: only tasks completed in the last 6 months,
      // matching the DB function's WHERE completed_date >= CURRENT_DATE - INTERVAL '6 months'.
      const maintenanceStats = await pool.query(
        `SELECT COUNT(*) as recent_maintenance_count
         FROM maintenance_history
         WHERE user_id = $1
           AND completed_date >= CURRENT_DATE - INTERVAL '6 months'`,
        [userId]
      );

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
        throw new Error(`Unknown feature for tracking: ${feature}`);
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
        throw new Error(`Unknown analytics field: ${field} (feature: ${feature})`);
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
