"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createApp = void 0;
const config_1 = require("./config");
const validator_1 = require("./config/validator");
const logger_1 = require("./utils/logger");
const rateLimiter_1 = require("./middleware/rateLimiter");
const token_blacklist_1 = require("./utils/token-blacklist");
const redis_1 = require("./utils/redis");
const notifications_service_1 = require("./services/notifications.service");
const warranty_purchases_service_1 = require("./services/warranty-purchases.service");
const reconciliation_service_1 = require("./services/reconciliation.service");
const db_1 = require("./db");
const app_1 = require("./app");
// Validate environment before starting
(0, validator_1.validateEnvironment)();
let server;
const PORT = config_1.config.port;
const NOTIFICATION_JOB_LOCK = 93422874;
const MAINTENANCE_JOB_LOCK = 93422875;
const WARRANTY_OFFERS_JOB_LOCK = 93422876;
async function runExpirationNotificationsJob() {
    const client = await db_1.pool.connect();
    try {
        const lockResult = await client.query('SELECT pg_try_advisory_lock($1) AS locked', [NOTIFICATION_JOB_LOCK]);
        if (!lockResult.rows[0]?.locked) {
            return;
        }
        try {
            await notifications_service_1.NotificationsService.checkAndNotifyExpirations();
        }
        finally {
            await client.query('SELECT pg_advisory_unlock($1)', [NOTIFICATION_JOB_LOCK]);
        }
    }
    catch (error) {
        logger_1.logger.error({ error }, 'Expiration notification job failed');
    }
    finally {
        client.release();
    }
}
async function runMaintenanceDueJob() {
    const client = await db_1.pool.connect();
    try {
        const lockResult = await client.query('SELECT pg_try_advisory_lock($1) AS locked', [MAINTENANCE_JOB_LOCK]);
        if (!lockResult.rows[0]?.locked) {
            return;
        }
        try {
            await notifications_service_1.NotificationsService.checkAndNotifyMaintenanceDue();
        }
        finally {
            await client.query('SELECT pg_advisory_unlock($1)', [MAINTENANCE_JOB_LOCK]);
        }
    }
    catch (error) {
        logger_1.logger.error({ error }, 'Maintenance due notification job failed');
    }
    finally {
        client.release();
    }
}
async function runWarrantyOffersJob() {
    const client = await db_1.pool.connect();
    try {
        const lockResult = await client.query('SELECT pg_try_advisory_lock($1) AS locked', [WARRANTY_OFFERS_JOB_LOCK]);
        if (!lockResult.rows[0]?.locked) {
            return;
        }
        try {
            await notifications_service_1.NotificationsService.checkAndNotifyWarrantyOffers();
        }
        finally {
            await client.query('SELECT pg_advisory_unlock($1)', [WARRANTY_OFFERS_JOB_LOCK]);
        }
    }
    catch (error) {
        logger_1.logger.error({ error }, 'Warranty offers notification job failed');
    }
    finally {
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
            }
            catch (error) {
                logger_1.logger.error({ error }, 'Expiration notification job failed');
            }
            // Also run maintenance due check at the same time
            try {
                await runMaintenanceDueJob();
            }
            catch (error) {
                logger_1.logger.error({ error }, 'Maintenance due notification job failed');
            }
            // Send extended warranty offer notifications for high-value items
            try {
                await runWarrantyOffersJob();
            }
            catch (error) {
                logger_1.logger.error({ error }, 'Warranty offers notification job failed');
            }
            // Auto-expire overdue extended warranties
            try {
                await warranty_purchases_service_1.WarrantyPurchasesService.expireOverdueWarranties();
            }
            catch (error) {
                logger_1.logger.error({ error }, 'Warranty auto-expiry job failed');
            }
            // Weekly jobs — only on Sundays
            if (new Date().getDay() === 0) {
                // Audit log cleanup using the DB function from migration 004
                try {
                    await db_1.pool.query('SELECT cleanup_old_audit_logs()');
                    logger_1.logger.info('Weekly audit log cleanup completed');
                }
                catch (error) {
                    logger_1.logger.error({ error }, 'Weekly audit log cleanup failed');
                }
                // Reconcile analytics counters against source tables
                try {
                    await reconciliation_service_1.ReconciliationService.reconcileUserAnalytics();
                }
                catch (error) {
                    logger_1.logger.error({ error }, 'Weekly analytics reconciliation failed');
                }
                // Clean up old webhook event records (older than 7 days)
                try {
                    const result = await db_1.pool.query(`DELETE FROM webhook_events WHERE processed_at < NOW() - INTERVAL '7 days'`);
                    logger_1.logger.info({ deleted: result.rowCount }, 'Weekly webhook events cleanup completed');
                }
                catch (error) {
                    logger_1.logger.error({ error }, 'Weekly webhook events cleanup failed');
                }
            }
            // Always schedule next, even if current run failed
            scheduleNext();
        }, delay);
    };
    scheduleNext();
}
async function start() {
    const rateLimiter = await (0, rateLimiter_1.initializeRateLimiter)();
    await (0, token_blacklist_1.initializeTokenBlacklist)();
    const app = (0, app_1.createApp)({ rateLimiter });
    server = app.listen(PORT, () => {
        logger_1.logger.info(`🚀 HavenKeep API running on port ${PORT}`);
        logger_1.logger.info(`📦 Environment: ${config_1.config.env}`);
        logger_1.logger.info(`🔒 CORS origins: ${config_1.config.cors.origins.join(', ')}`);
        logger_1.logger.info(`✅ Environment validated`);
        logger_1.logger.info(`🔐 Security: Helmet, CORS, Rate Limiting, CSRF Protection`);
        logger_1.logger.info(`📊 Monitoring: Pino → Promtail → Loki`);
    });
    scheduleExpirationNotifications();
}
start().catch((err) => {
    logger_1.logger.error({ err }, 'Failed to start server');
    process.exit(1);
});
// Graceful shutdown
const gracefulShutdown = (signal) => {
    logger_1.logger.info(`${signal} received, shutting down gracefully`);
    server.close(async () => {
        logger_1.logger.info('HTTP server closed');
        try {
            await db_1.pool.end();
            logger_1.logger.info('Database pool closed');
        }
        catch (err) {
            logger_1.logger.error({ err }, 'Error closing database pool');
        }
        try {
            await (0, token_blacklist_1.closeTokenBlacklist)();
            logger_1.logger.info('Token blacklist Redis connection closed');
        }
        catch (err) {
            logger_1.logger.error({ err }, 'Error closing token blacklist Redis');
        }
        try {
            await (0, redis_1.closeRedisClient)();
            logger_1.logger.info('Shared Redis connection closed');
        }
        catch (err) {
            logger_1.logger.error({ err }, 'Error closing shared Redis');
        }
        try {
            await (0, rateLimiter_1.closeRateLimiterRedis)();
            logger_1.logger.info('Rate limiter Redis connection closed');
        }
        catch (err) {
            logger_1.logger.error({ err }, 'Error closing rate limiter Redis');
        }
        process.exit(0);
    });
    // Force shutdown after 30 seconds
    setTimeout(() => {
        logger_1.logger.error('Forced shutdown after timeout');
        process.exit(1);
    }, 30000);
};
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));
// Handle unhandled promise rejections
process.on('unhandledRejection', (reason, promise) => {
    logger_1.logger.error({ reason, promise }, 'Unhandled Promise Rejection');
});
// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
    logger_1.logger.error({ error }, 'Uncaught Exception');
    gracefulShutdown('UNCAUGHT_EXCEPTION');
});
var app_2 = require("./app");
Object.defineProperty(exports, "createApp", { enumerable: true, get: function () { return app_2.createApp; } });
//# sourceMappingURL=index.js.map