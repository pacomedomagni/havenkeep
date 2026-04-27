import { pool } from '../db';
import { logger } from '../utils/logger';
import { decimalToCents, centsToDecimalString } from '../utils/money';

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
          -- S2-I: claims for archived items shouldn't count toward the
          -- "lifetime savings" headline. mig 028 changed item_id to ON
          -- DELETE SET NULL, so a claim whose item was deleted survives
          -- with item_id=NULL — keep those (they represent real savings).
          -- Only filter where the join finds an *archived* item.
          SELECT
            wc.user_id,
            SUM(wc.amount_saved)  AS actual_savings,
            COUNT(*)              AS actual_claims
          FROM warranty_claims wc
          LEFT JOIN items i ON i.id = wc.item_id
          WHERE i.id IS NULL OR i.is_archived = FALSE
          GROUP BY wc.user_id
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

        // S1-E: compare in integer cents. parseFloat on a DECIMAL string can
        // produce values that don't equal each other across recomputes
        // (e.g. 19.99 vs 19.989999999999998), causing phantom drift.
        const storedSavingsCents = decimalToCents(row.stored_savings);
        const actualSavingsCents = decimalToCents(row.actual_savings);
        const storedClaims = parseInt(row.stored_claims, 10) || 0;
        const actualClaims = parseInt(row.actual_claims, 10) || 0;
        const storedMaintenance = parseInt(row.stored_maintenance, 10) || 0;
        const actualMaintenance = parseInt(row.actual_maintenance, 10) || 0;

        if (storedSavingsCents !== actualSavingsCents) {
          drifts.push(
            `total_warranty_savings: stored=${storedSavingsCents}c, actual=${actualSavingsCents}c`
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
            [
              centsToDecimalString(actualSavingsCents),
              actualClaims,
              actualMaintenance,
              row.user_id,
            ]
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
