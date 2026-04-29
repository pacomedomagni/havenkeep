// Validator runs FIRST and reads process.env directly (no `./config` import)
// so a misconfigured env fails before any other module touches a half-built
// config object. (Ch11-I050)
import { validateEnvironment } from './config/validator';
validateEnvironment();

import type { Server } from 'http';
import { config } from './config';
import { logger, fatalLogger } from './utils/logger';
import { initializeRateLimiter, closeRateLimiterRedis } from './middleware/rateLimiter';
import { initializeTokenBlacklist, closeTokenBlacklist } from './utils/token-blacklist';
import { closeRedisClient } from './utils/redis';
import { NotificationsService } from './services/notifications.service';
import { WarrantyPurchasesService } from './services/warranty-purchases.service';
import { ReconciliationService } from './services/reconciliation.service';
import { AuditService } from './services/audit.service';
import { pruneExpiredIdempotencyRows } from './middleware/idempotency';
import { purgeExpiredSoftDeletedAccounts } from './services/account-purge.service';
import { pool, isDatabaseReady } from './db';
import { createApp } from './app';
import { isShuttingDown, markShuttingDown } from './utils/lifecycle';

let server: Server | undefined;
const PORT = config.port;
const NOTIFICATION_JOB_LOCK = 93422874;
const MAINTENANCE_JOB_LOCK = 93422875;
const WARRANTY_OFFERS_JOB_LOCK = 93422876;

// ── Cron jobs ─────────────────────────────────────────────────────────────
// Each job acquires a Postgres advisory lock so multi-instance deploys only
// run one copy at a time. Failures inside a job are logged but never crash
// the process or block the next job (Ch11-I092).

async function runWithAdvisoryLock(lockId: number, label: string, fn: () => Promise<unknown>): Promise<void> {
  const client = await pool.connect();
  try {
    const lock = await client.query('SELECT pg_try_advisory_lock($1) AS locked', [lockId]);
    if (!lock.rows[0]?.locked) return;
    try {
      await fn();
    } finally {
      await client.query('SELECT pg_advisory_unlock($1)', [lockId]);
    }
  } catch (err) {
    logger.error({ err, label }, 'Cron job failed');
  } finally {
    client.release();
  }
}

const runExpirationNotificationsJob = () =>
  runWithAdvisoryLock(NOTIFICATION_JOB_LOCK, 'expiration-notifications',
    () => NotificationsService.checkAndNotifyExpirations());

const runMaintenanceDueJob = () =>
  runWithAdvisoryLock(MAINTENANCE_JOB_LOCK, 'maintenance-due',
    () => NotificationsService.checkAndNotifyMaintenanceDue());

const runWarrantyOffersJob = () =>
  runWithAdvisoryLock(WARRANTY_OFFERS_JOB_LOCK, 'warranty-offers',
    () => NotificationsService.checkAndNotifyWarrantyOffers());

const PARTNER_GIFT_EXPIRY_LOCK = 93422877;

/**
 * Auto-expire unactivated partner gifts whose expires_at is in the past
 * and cancel any matching pending commission (Ch03-F097). Runs daily under
 * an advisory lock so a multi-instance deploy doesn't race the same row.
 */
async function expireUnactivatedPartnerGifts(): Promise<void> {
  await runWithAdvisoryLock(PARTNER_GIFT_EXPIRY_LOCK, 'partner-gift-auto-expiry', async () => {
    const expired = await pool.query(
      `UPDATE partner_gifts
          SET status = 'expired', updated_at = NOW()
        WHERE status IN ('created', 'sent')
          AND is_activated = FALSE
          AND expires_at IS NOT NULL
          AND expires_at < NOW()
        RETURNING id, partner_id`,
    );
    if (expired.rowCount === 0) return;
    const giftIds = expired.rows.map((r: { id: string }) => r.id);
    const cancelled = await pool.query(
      `UPDATE partner_commissions
          SET status = 'cancelled', updated_at = NOW()
        WHERE reference_type = 'partner_gift'
          AND reference_id = ANY($1::uuid[])
          AND status = 'pending'
        RETURNING id`,
      [giftIds],
    );
    logger.info(
      { expiredGifts: expired.rowCount, cancelledCommissions: cancelled.rowCount },
      'Partner gifts auto-expired and pending commissions cancelled',
    );
  });
}

// ── Daily scheduler ───────────────────────────────────────────────────────
//
// Audit Ch11-I090 / I093: the prior `next.setHours(9,…)` ran in local TZ,
// which on a UTC server in production meant 9am UTC instead of 9am of the
// user's locale.  Use UTC accessors and a configurable hour
// (`NOTIFICATION_HOUR_UTC`, default 14 = 9am ET) so the scheduling is
// deterministic regardless of process TZ.
//
// Audit Ch11-I091: long setTimeout delays survive across kernel-level
// suspend / resume only if the OS timer subsystem keeps wall-clock parity.
// On Linux containers this is OK; on macOS dev laptops the timer can drift
// ~hours after a long sleep. Mitigation: every 30 minutes we re-check the
// deadline and reschedule if drift > 5 min.
const NOTIFICATION_HOUR_UTC = parseInt(process.env.NOTIFICATION_HOUR_UTC || '14', 10);
const SCHEDULER_DRIFT_CHECK_MS = 30 * 60 * 1000;
const SCHEDULER_DRIFT_THRESHOLD_MS = 5 * 60 * 1000;

function scheduleExpirationNotifications() {
  let driftCheckTimer: NodeJS.Timeout | undefined;
  let runTimer: NodeJS.Timeout | undefined;
  let nextDeadlineMs = 0;

  const computeNextDeadline = (): number => {
    const now = new Date();
    const next = new Date(Date.UTC(
      now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(),
      NOTIFICATION_HOUR_UTC, 0, 0, 0,
    ));
    if (next.getTime() <= now.getTime()) {
      next.setUTCDate(next.getUTCDate() + 1);
    }
    return next.getTime();
  };

  const runJobs = async () => {
    // Each job is independently try/catch'd inside runWithAdvisoryLock
    // so one hung handler can't block the others (Ch11-I092).
    await Promise.allSettled([
      runExpirationNotificationsJob(),
      runMaintenanceDueJob(),
      runWarrantyOffersJob(),
      WarrantyPurchasesService.expireOverdueWarranties().then(
        () => undefined,
        (err) => logger.error({ err }, 'Warranty auto-expiry job failed'),
      ),
      // Auto-expire unactivated partner gifts past their expires_at and
      // cancel the pending commission (Ch03-F097). A single SQL statement
      // moves every stale row in one trip; commission cancellation runs as
      // a follow-up so partners stop seeing pending commissions for gifts
      // the homebuyer never redeemed.
      expireUnactivatedPartnerGifts().catch((err) =>
        logger.error({ err }, 'Partner gift auto-expiry job failed'),
      ),
      // S2-K: daily audit log hash-chain check. A break here means a row
      // was tampered with after the fact; we surface as `error` so any
      // log forwarder pages on it.
      AuditService.verifyHashChain().then(
        (broken) => {
          if (broken.length > 0) {
            logger.error(
              { brokenCount: broken.length, firstBrokenAt: broken[0] },
              'Audit log hash chain INTEGRITY FAILURE — possible tampering',
            );
          } else {
            logger.info('Audit log hash chain verification passed');
          }
        },
        (err) => logger.error({ err }, 'Audit hash chain verification failed'),
      ),
      // S-HI-04: prune expired idempotency rows so the table doesn't grow
      // unbounded. The TTL on each row is set per-route (default 24h);
      // this delete just sweeps anything past its expiry.
      pruneExpiredIdempotencyRows().then(
        (deleted) => {
          if (deleted > 0) {
            logger.info({ deleted }, 'Pruned expired idempotency rows');
          }
        },
        (err) => logger.error({ err }, 'Idempotency prune failed'),
      ),
      // 1.4: hard-delete users whose 30-day cooling-off window has
      // expired. The DELETE /me handler stamps deletion_scheduled_for =
      // NOW() + 30 days and tells the user the account will be deleted
      // at that time; this is the job that honors the promise.
      purgeExpiredSoftDeletedAccounts().then(
        (result) => {
          if (result.candidates > 0 || result.purged > 0 || result.failed > 0) {
            logger.info(result, 'Soft-delete purge completed');
          }
        },
        (err) => logger.error({ err }, 'Soft-delete purge failed'),
      ),
    ]);

    // 3.12: audit log retention runs daily, not weekly. The
    // `cleanup_old_audit_logs()` Postgres function handles the actual
    // retention window — reading once a week was enough for sanity but
    // gave us 7 days of growth between sweeps on a busy table.
    try {
      await pool.query('SELECT cleanup_old_audit_logs()');
    } catch (err) {
      logger.error({ err }, 'Daily audit log cleanup failed');
    }

    // 3.10: bound notification_history + openai_usage growth. Both
    // tables are append-only on every notification send / OpenAI call;
    // without retention they balloon to multi-million-row scans on
    // common reads (notifications-list count query, OpenAI cost stats).
    // 90 days is enough for "did we email you about this last quarter?"
    // forensics and aligns with audit log + Loki retention.
    try {
      const result = await pool.query(
        `DELETE FROM notification_history WHERE created_at < NOW() - INTERVAL '90 days'`,
      );
      if (result.rowCount && result.rowCount > 0) {
        logger.info({ deleted: result.rowCount }, 'notification_history retention sweep');
      }
    } catch (err) {
      logger.error({ err }, 'notification_history retention sweep failed');
    }
    try {
      const result = await pool.query(
        `DELETE FROM openai_usage WHERE created_at < NOW() - INTERVAL '90 days'`,
      );
      if (result.rowCount && result.rowCount > 0) {
        logger.info({ deleted: result.rowCount }, 'openai_usage retention sweep');
      }
    } catch (err) {
      logger.error({ err }, 'openai_usage retention sweep failed');
    }

    // Sunday weekly sweep — `getUTCDay()` so the boundary is consistent.
    if (new Date().getUTCDay() === 0) {
      try {
        await ReconciliationService.reconcileUserAnalytics();
      } catch (err) {
        logger.error({ err }, 'Weekly analytics reconciliation failed');
      }
      try {
        const result = await pool.query(
          `DELETE FROM webhook_events WHERE processed_at < NOW() - INTERVAL '7 days'`,
        );
        logger.info({ deleted: result.rowCount }, 'Weekly webhook events cleanup completed');
      } catch (err) {
        logger.error({ err }, 'Weekly webhook events cleanup failed');
      }
    }
    scheduleNext();
  };

  const scheduleNext = () => {
    nextDeadlineMs = computeNextDeadline();
    const delay = nextDeadlineMs - Date.now();
    if (runTimer) clearTimeout(runTimer);
    runTimer = setTimeout(() => { runJobs().catch(() => {}); }, delay);
    runTimer.unref();
  };

  const driftCheck = () => {
    const now = Date.now();
    const expectedFireIn = nextDeadlineMs - now;
    // If the scheduled fire is more than the drift threshold off from the
    // recomputed deadline, our timer probably suffered suspend/resume drift.
    const recomputed = computeNextDeadline();
    if (Math.abs(recomputed - nextDeadlineMs) > SCHEDULER_DRIFT_THRESHOLD_MS) {
      logger.warn(
        { driftMs: recomputed - nextDeadlineMs, expectedFireIn },
        'Scheduler drift detected — rescheduling',
      );
      scheduleNext();
    }
  };

  scheduleNext();
  driftCheckTimer = setInterval(driftCheck, SCHEDULER_DRIFT_CHECK_MS);
  driftCheckTimer.unref();
}

// ── Notification digest tick (Ch04-F034) ─────────────────────────────────
// Outbox rows enqueued by `NotificationsService.createNotification` are due
// when `flush_at <= NOW()`; we tick every minute so the worst-case latency
// past a user's `digest_minutes` window is one minute. The flush is
// guarded by an advisory lock so multi-instance deploys converge on a
// single coalescer.
//
// 4.13: chain `setTimeout` from inside the handler instead of using
// `setInterval` so a long-running flush can't pile up overlapping
// invocations (V8's setInterval queues fixed slots; if a tick takes
// 90s the next one fires immediately, then again after 60s, etc.). The
// next deadline is computed off wall-clock at the start of each handler
// so a paused process catching up doesn't drift further than the
// flush itself takes. The timer is `unref()`'d so it doesn't hold the
// process alive on shutdown.
const DIGEST_TICK_INTERVAL_MS = 60_000;
const DIGEST_FLUSH_LOCK = 93422878;
function startDigestTick(): void {
  let timer: NodeJS.Timeout | undefined;
  const tick = async () => {
    const startedAt = Date.now();
    try {
      await runWithAdvisoryLock(
        DIGEST_FLUSH_LOCK,
        'notification-digest-flush',
        async () => {
          await NotificationsService.flushDigestOutbox();
        },
      );
    } catch (err) {
      logger.error({ err }, 'Digest flush tick failed');
    }
    // Schedule the next run relative to *when this run was supposed to
    // start*. If the flush ran 5s long, the next deadline is 55s out
    // — not 60s. Long-tail flushes converge instead of diverging.
    const delay = Math.max(
      0,
      DIGEST_TICK_INTERVAL_MS - (Date.now() - startedAt),
    );
    timer = setTimeout(() => {
      tick().catch(() => {});
    }, delay);
    timer.unref();
  };
  // Kick off the first tick after the standard interval. Process boot
  // already runs the daily cron once, which covers the first window.
  timer = setTimeout(() => {
    tick().catch(() => {});
  }, DIGEST_TICK_INTERVAL_MS);
  timer.unref();
}

async function waitForDatabase(maxAttempts = 30, intervalMs = 1000): Promise<void> {
  // Ch11-I088: don't bind the HTTP port until the DB is reachable.
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    if (await isDatabaseReady()) {
      logger.info({ attempt }, 'Database ready');
      return;
    }
    logger.warn({ attempt, maxAttempts }, 'Database not ready — retrying');
    await new Promise((r) => setTimeout(r, intervalMs));
  }
  throw new Error(`Database failed readiness probe after ${maxAttempts} attempts`);
}

async function start() {
  await waitForDatabase();

  const rateLimiter = await initializeRateLimiter();
  await initializeTokenBlacklist();

  const app = createApp({ rateLimiter });

  server = app.listen(PORT, () => {
    logger.info(`🚀 HavenKeep API running on port ${PORT}`);
    logger.info(`📦 Environment: ${config.env}`);
    logger.info(`🔒 CORS origins: ${config.cors.origins.join(', ')}`);
    logger.info(`✅ Environment validated`);
    logger.info(`🔐 Security: Helmet, CORS, Rate Limiting, CSRF Protection`);
    logger.info(`📊 Monitoring: Pino → Promtail → Loki`);
  });

  scheduleExpirationNotifications();
  startDigestTick();
}

start().catch((err) => {
  logger.error({ err }, 'Failed to start server');
  process.exit(1);
});

// ── Graceful shutdown ─────────────────────────────────────────────────────
//
// Audit Ch11-I094: kill timer is now `unref()`'d so it doesn't keep the
//   process alive after server.close() finishes cleanly.
// Audit Ch11-I095: re-entry guard (`isShuttingDown`) so a second SIGTERM (or
//   uncaughtException-triggered shutdown) doesn't recurse and exit twice.
// Audit Ch11-I100: SIGTERM may arrive before `server` is bound (very early
//   in start()). Guard the close path so we don't dereference undefined.

async function shutdown(signal: string, exitCode = 0): Promise<void> {
  if (isShuttingDown()) {
    logger.warn({ signal }, 'Shutdown already in progress, ignoring duplicate signal');
    return;
  }
  markShuttingDown();
  logger.info({ signal }, 'Shutdown initiated');

  const closeServer = (): Promise<void> =>
    new Promise((resolve) => {
      if (!server) return resolve();
      server.close((err) => {
        if (err) logger.warn({ err }, 'HTTP server close emitted error');
        resolve();
      });
    });

  // Wall-clock 30s kill timer — ensures we don't hang forever on a stuck
  // resource. unref()'d so a clean shutdown short-circuits it.
  const killTimer = setTimeout(() => {
    logger.error('Forced shutdown after 30s timeout');
    process.exit(exitCode === 0 ? 1 : exitCode);
  }, 30_000);
  killTimer.unref();

  // 2.7: hold for 5s after flipping `isShuttingDown` so the LB has time
  // to deregister this pod (its /ready now returns 503) before we close
  // the socket. Without this, server.close() races the LB health-check
  // poll and fresh requests get routed onto a dying pod.
  logger.info('Draining: /ready flipped to 503, waiting 5s for LB to deregister');
  await new Promise((r) => setTimeout(r, 5_000));

  await closeServer();
  logger.info('HTTP server closed');

  // Run the rest of the cleanup in parallel — if any individual close hangs
  // the kill timer takes over.
  await Promise.allSettled([
    pool.end().then(() => logger.info('Database pool closed')),
    closeTokenBlacklist().then(() => logger.info('Token blacklist Redis closed')),
    closeRedisClient().then(() => logger.info('Shared Redis closed')),
    closeRateLimiterRedis().then(() => logger.info('Rate limiter Redis closed')),
  ]);

  clearTimeout(killTimer);
  process.exit(exitCode);
}

process.on('SIGTERM', () => shutdown('SIGTERM').catch(() => process.exit(1)));
process.on('SIGINT', () => shutdown('SIGINT').catch(() => process.exit(1)));

// Audit Ch11-I096: unhandledRejection in production used to log-only, which
// left the process in an undefined state. Treat it as fatal — a clean
// shutdown gives Postgres / Redis a chance to release sockets.
process.on('unhandledRejection', (reason, promise) => {
  logger.error({ reason, promise }, 'Unhandled Promise Rejection');
  if (config.env === 'production') {
    fatalLogger.fatal({ reason }, 'Exiting on unhandledRejection');
    shutdown('UNHANDLED_REJECTION', 1).catch(() => process.exit(1));
  }
});

// Ch11-I058 / I095: pino.final ensures the log line lands before exit, and
// the shutdown re-entry guard prevents recursion.
process.on('uncaughtException', (error) => {
  fatalLogger.fatal({ err: error }, 'Uncaught Exception');
  shutdown('UNCAUGHT_EXCEPTION', 1).catch(() => process.exit(1));
});

export { createApp } from './app';
