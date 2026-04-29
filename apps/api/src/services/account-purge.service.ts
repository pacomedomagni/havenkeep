import { pool } from '../db';
import { logger } from '../utils/logger';
import {
  harvestUserKeys,
  flattenHarvest,
  removeKeysBestEffort,
} from '../utils/storage-cleanup';

// 1.4: hard-delete users whose 30-day cooling-off window has expired.
//
// `DELETE /me` (apps/api/src/routes/users.ts) sets
//   deleted_at = NOW(), deletion_scheduled_for = NOW() + INTERVAL '30 days'
// and emails the user "your account will be permanently deleted in 30
// days." Without this cron the row sits forever — GDPR/CCPA exposure +
// open-ended data retention.
//
// Process:
//   1. SELECT one expired user at a time (keeps the loop cancellable
//      under shutdown and stops one bad user from blocking the rest).
//   2. Inside a transaction, harvest every MinIO key the user owns,
//      run DELETE FROM users (FK CASCADE handles dependent tables),
//      COMMIT.
//   3. After COMMIT, best-effort remove the captured keys from MinIO.
//
// Errors on a single user are logged and skipped — the next cron run
// retries. The advisory lock at the cron level prevents two replicas
// from racing; we still serialize per-user inside this function.

export interface PurgeResult {
  candidates: number;
  purged: number;
  failed: number;
  storageRemoved: number;
  storageFailed: number;
}

const ADVISORY_LOCK_KEY = 0xa00d_4a13; // arbitrary 32-bit constant

export async function purgeExpiredSoftDeletedAccounts(): Promise<PurgeResult> {
  const result: PurgeResult = {
    candidates: 0,
    purged: 0,
    failed: 0,
    storageRemoved: 0,
    storageFailed: 0,
  };

  // Top-level advisory lock: only one replica's cron runs the purge at
  // a time. The lock is session-scoped, released when the connection
  // returns to the pool.
  const guard = await pool.connect();
  let acquired = false;
  try {
    const lockRes = await guard.query<{ pg_try_advisory_lock: boolean }>(
      `SELECT pg_try_advisory_lock($1) AS pg_try_advisory_lock`,
      [ADVISORY_LOCK_KEY],
    );
    acquired = lockRes.rows[0]?.pg_try_advisory_lock === true;
    if (!acquired) {
      logger.info('Soft-delete purge: another replica holds the lock; skipping run');
      return result;
    }

    // Loop one user at a time. Bound the per-run count so a backlog
    // (e.g. first run after the cron is wired) doesn't pin the worker.
    const MAX_PER_RUN = 100;
    while (result.purged + result.failed < MAX_PER_RUN) {
      const candidate = await pool.query<{ id: string; email: string }>(
        `SELECT id, email FROM users
           WHERE deleted_at IS NOT NULL
             AND deletion_scheduled_for IS NOT NULL
             AND deletion_scheduled_for < NOW()
           ORDER BY deletion_scheduled_for ASC
           LIMIT 1`,
      );
      if (candidate.rows.length === 0) break;
      result.candidates++;

      const userId = candidate.rows[0].id;
      const userEmail = candidate.rows[0].email;

      try {
        const txClient = await pool.connect();
        let harvest: Awaited<ReturnType<typeof harvestUserKeys>> | null = null;
        try {
          await txClient.query('BEGIN');
          harvest = await harvestUserKeys(txClient, userId);
          // Refresh-tokens have FK ON DELETE CASCADE; explicit DELETE
          // matches the admin path's belt-and-braces pattern.
          await txClient.query(`DELETE FROM refresh_tokens WHERE user_id = $1`, [userId]);
          const del = await txClient.query(`DELETE FROM users WHERE id = $1`, [userId]);
          if (del.rowCount === 0) {
            // Concurrent admin-delete or recovery beat us to it.
            await txClient.query('ROLLBACK');
            continue;
          }
          await txClient.query('COMMIT');
        } catch (err) {
          await txClient.query('ROLLBACK').catch(() => {});
          throw err;
        } finally {
          txClient.release();
        }

        if (harvest) {
          const cleanup = await removeKeysBestEffort(flattenHarvest(harvest));
          result.storageRemoved += cleanup.removed;
          result.storageFailed += cleanup.failed;
        }

        result.purged++;
        logger.info(
          { userId, userEmail },
          'Soft-deleted user permanently purged after 30-day cooling-off window',
        );
      } catch (err) {
        result.failed++;
        logger.error(
          { err, userId },
          'Soft-delete purge: per-user failure (will retry next run)',
        );
      }
    }
  } finally {
    if (acquired) {
      await guard
        .query(`SELECT pg_advisory_unlock($1)`, [ADVISORY_LOCK_KEY])
        .catch(() => {});
    }
    guard.release();
  }

  return result;
}
