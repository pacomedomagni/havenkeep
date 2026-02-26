import { pool } from '../db';
import { logger } from '../utils/logger';

/**
 * ReconciliationService — detects and fixes drift between source tables
 * and the denormalized `user_analytics` counters.
 *
 * Designed to run periodically (e.g., weekly) to ensure analytics accuracy.
 */
export class ReconciliationService {
  /**
   * Reconcile `total_warranty_savings`, `total_claims_filed`, and
   * `total_maintenance_completed` in `user_analytics` by recalculating
   * from the source-of-truth tables (warranty_claims, maintenance_history).
   *
   * Any discrepancy is logged and corrected in-place.
   */
  static async reconcileUserAnalytics(): Promise<{
    usersChecked: number;
    discrepanciesFound: number;
    discrepanciesFixed: number;
  }> {
    const stats = {
      usersChecked: 0,
      discrepanciesFound: 0,
      discrepanciesFixed: 0,
    };

    try {
      // Fetch all user_analytics rows alongside recalculated values from source tables
      const result = await pool.query(`
        SELECT
          ua.user_id,
          ua.total_warranty_savings       AS stored_savings,
          ua.total_claims_filed           AS stored_claims,
          ua.total_maintenance_completed  AS stored_maintenance,
          COALESCE(wc.actual_savings, 0)        AS actual_savings,
          COALESCE(wc.actual_claims, 0)         AS actual_claims,
          COALESCE(mh.actual_maintenance, 0)    AS actual_maintenance
        FROM user_analytics ua
        LEFT JOIN (
          SELECT
            user_id,
            SUM(amount_saved)  AS actual_savings,
            COUNT(*)           AS actual_claims
          FROM warranty_claims
          GROUP BY user_id
        ) wc ON wc.user_id = ua.user_id
        LEFT JOIN (
          SELECT
            user_id,
            COUNT(*) AS actual_maintenance
          FROM maintenance_history
          GROUP BY user_id
        ) mh ON mh.user_id = ua.user_id
      `);

      stats.usersChecked = result.rows.length;

      for (const row of result.rows) {
        const drifts: string[] = [];

        const storedSavings = parseFloat(row.stored_savings) || 0;
        const actualSavings = parseFloat(row.actual_savings) || 0;
        const storedClaims = parseInt(row.stored_claims, 10) || 0;
        const actualClaims = parseInt(row.actual_claims, 10) || 0;
        const storedMaintenance = parseInt(row.stored_maintenance, 10) || 0;
        const actualMaintenance = parseInt(row.actual_maintenance, 10) || 0;

        if (storedSavings !== actualSavings) {
          drifts.push(
            `total_warranty_savings: stored=${storedSavings}, actual=${actualSavings}`
          );
        }
        if (storedClaims !== actualClaims) {
          drifts.push(
            `total_claims_filed: stored=${storedClaims}, actual=${actualClaims}`
          );
        }
        if (storedMaintenance !== actualMaintenance) {
          drifts.push(
            `total_maintenance_completed: stored=${storedMaintenance}, actual=${actualMaintenance}`
          );
        }

        if (drifts.length > 0) {
          stats.discrepanciesFound += drifts.length;

          logger.warn(
            {
              userId: row.user_id,
              drifts,
            },
            'Analytics drift detected — fixing'
          );

          await pool.query(
            `UPDATE user_analytics
             SET total_warranty_savings      = $1,
                 total_claims_filed          = $2,
                 total_maintenance_completed = $3,
                 updated_at                  = NOW()
             WHERE user_id = $4`,
            [actualSavings, actualClaims, actualMaintenance, row.user_id]
          );

          stats.discrepanciesFixed += drifts.length;
        }
      }

      if (stats.discrepanciesFound > 0) {
        logger.info(
          stats,
          'Analytics reconciliation completed with fixes'
        );
      } else {
        logger.info(
          { usersChecked: stats.usersChecked },
          'Analytics reconciliation completed — no drift detected'
        );
      }

      return stats;
    } catch (error) {
      logger.error({ error }, 'Analytics reconciliation failed');
      throw error;
    }
  }
}
