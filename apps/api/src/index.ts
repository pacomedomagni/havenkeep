import { config } from './config';
import { validateEnvironment } from './config/validator';
import { logger } from './utils/logger';
import { initializeRateLimiter, closeRateLimiterRedis } from './middleware/rateLimiter';
import { initializeTokenBlacklist, closeTokenBlacklist } from './utils/token-blacklist';
import { closeRedisClient } from './utils/redis';
import { NotificationsService } from './services/notifications.service';
import { WarrantyPurchasesService } from './services/warranty-purchases.service';
import { ReconciliationService } from './services/reconciliation.service';
import { pool } from './db';
import { createApp } from './app';

// Validate environment before starting
validateEnvironment();

let server: ReturnType<typeof import('http').createServer>;
const PORT = config.port;
const NOTIFICATION_JOB_LOCK = 93422874;
const MAINTENANCE_JOB_LOCK = 93422875;
const WARRANTY_OFFERS_JOB_LOCK = 93422876;

async function runExpirationNotificationsJob() {
  const client = await pool.connect();
  try {
    const lockResult = await client.query(
      'SELECT pg_try_advisory_lock($1) AS locked',
      [NOTIFICATION_JOB_LOCK]
    );
    if (!lockResult.rows[0]?.locked) {
      return;
    }

    try {
      await NotificationsService.checkAndNotifyExpirations();
    } finally {
      await client.query('SELECT pg_advisory_unlock($1)', [NOTIFICATION_JOB_LOCK]);
    }
  } catch (error) {
    logger.error({ error }, 'Expiration notification job failed');
  } finally {
    client.release();
  }
}

async function runMaintenanceDueJob() {
  const client = await pool.connect();
  try {
    const lockResult = await client.query(
      'SELECT pg_try_advisory_lock($1) AS locked',
      [MAINTENANCE_JOB_LOCK]
    );
    if (!lockResult.rows[0]?.locked) {
      return;
    }

    try {
      await NotificationsService.checkAndNotifyMaintenanceDue();
    } finally {
      await client.query('SELECT pg_advisory_unlock($1)', [MAINTENANCE_JOB_LOCK]);
    }
  } catch (error) {
    logger.error({ error }, 'Maintenance due notification job failed');
  } finally {
    client.release();
  }
}

async function runWarrantyOffersJob() {
  const client = await pool.connect();
  try {
    const lockResult = await client.query(
      'SELECT pg_try_advisory_lock($1) AS locked',
      [WARRANTY_OFFERS_JOB_LOCK]
    );
    if (!lockResult.rows[0]?.locked) {
      return;
    }

    try {
      await NotificationsService.checkAndNotifyWarrantyOffers();
    } finally {
      await client.query('SELECT pg_advisory_unlock($1)', [WARRANTY_OFFERS_JOB_LOCK]);
    }
  } catch (error) {
    logger.error({ error }, 'Warranty offers notification job failed');
  } finally {
    client.release();
  }
}

function scheduleExpirationNotifications() {
  const scheduleNext = () => {
    const now = new Date();
    const next = new Date(now);
    next.setHours(9, 0, 0, 0);
    if (next <= now) {
      next.setDate(next.getDate() + 1);
    }
    const delay = next.getTime() - now.getTime();

    setTimeout(async () => {
      try {
        await runExpirationNotificationsJob();
      } catch (error) {
        logger.error({ error }, 'Expiration notification job failed');
      }
      // Also run maintenance due check at the same time
      try {
        await runMaintenanceDueJob();
      } catch (error) {
        logger.error({ error }, 'Maintenance due notification job failed');
      }
      // Send extended warranty offer notifications for high-value items
      try {
        await runWarrantyOffersJob();
      } catch (error) {
        logger.error({ error }, 'Warranty offers notification job failed');
      }
      // Auto-expire overdue extended warranties
      try {
        await WarrantyPurchasesService.expireOverdueWarranties();
      } catch (error) {
        logger.error({ error }, 'Warranty auto-expiry job failed');
      }

      // Weekly jobs — only on Sundays
      if (new Date().getDay() === 0) {
        // Audit log cleanup using the DB function from migration 004
        try {
          await pool.query('SELECT cleanup_old_audit_logs()');
          logger.info('Weekly audit log cleanup completed');
        } catch (error) {
          logger.error({ error }, 'Weekly audit log cleanup failed');
        }

        // Reconcile analytics counters against source tables
        try {
          await ReconciliationService.reconcileUserAnalytics();
        } catch (error) {
          logger.error({ error }, 'Weekly analytics reconciliation failed');
        }

        // Clean up old webhook event records (older than 7 days)
        try {
          const result = await pool.query(
            `DELETE FROM webhook_events WHERE processed_at < NOW() - INTERVAL '7 days'`
          );
          logger.info({ deleted: result.rowCount }, 'Weekly webhook events cleanup completed');
        } catch (error) {
          logger.error({ error }, 'Weekly webhook events cleanup failed');
        }
      }

      // Always schedule next, even if current run failed
      scheduleNext();
    }, delay);
  };

  scheduleNext();
}

async function start() {
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
}

start().catch((err) => {
  logger.error({ err }, 'Failed to start server');
  process.exit(1);
});

// Graceful shutdown
const gracefulShutdown = (signal: string) => {
  logger.info(`${signal} received, shutting down gracefully`);
  server.close(async () => {
    logger.info('HTTP server closed');
    try {
      await pool.end();
      logger.info('Database pool closed');
    } catch (err) {
      logger.error({ err }, 'Error closing database pool');
    }
    try {
      await closeTokenBlacklist();
      logger.info('Token blacklist Redis connection closed');
    } catch (err) {
      logger.error({ err }, 'Error closing token blacklist Redis');
    }
    try {
      await closeRedisClient();
      logger.info('Shared Redis connection closed');
    } catch (err) {
      logger.error({ err }, 'Error closing shared Redis');
    }
    try {
      await closeRateLimiterRedis();
      logger.info('Rate limiter Redis connection closed');
    } catch (err) {
      logger.error({ err }, 'Error closing rate limiter Redis');
    }
    process.exit(0);
  });

  // Force shutdown after 30 seconds
  setTimeout(() => {
    logger.error('Forced shutdown after timeout');
    process.exit(1);
  }, 30000);
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// Handle unhandled promise rejections
process.on('unhandledRejection', (reason, promise) => {
  logger.error({ reason, promise }, 'Unhandled Promise Rejection');
});

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
  logger.error({ error }, 'Uncaught Exception');
  gracefulShutdown('UNCAUGHT_EXCEPTION');
});

export { createApp } from './app';
