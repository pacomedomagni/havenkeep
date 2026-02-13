"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const helmet_1 = __importDefault(require("helmet"));
const compression_1 = __importDefault(require("compression"));
const cookie_parser_1 = __importDefault(require("cookie-parser"));
const config_1 = require("./config");
const validator_1 = require("./config/validator");
const logger_1 = require("./utils/logger");
const errorHandler_1 = require("./middleware/errorHandler");
const requestLogger_1 = require("./middleware/requestLogger");
const rateLimiter_1 = require("./middleware/rateLimiter");
const csrf_1 = require("./middleware/csrf");
const notifications_service_1 = require("./services/notifications.service");
const db_1 = require("./db");
// Routes
const auth_1 = __importDefault(require("./routes/auth"));
const users_1 = __importDefault(require("./routes/users"));
const homes_1 = __importDefault(require("./routes/homes"));
const items_1 = __importDefault(require("./routes/items"));
const documents_1 = __importDefault(require("./routes/documents"));
const barcode_1 = __importDefault(require("./routes/barcode"));
const admin_1 = __importDefault(require("./routes/admin"));
const health_1 = __importDefault(require("./routes/health"));
const warranty_claims_1 = __importDefault(require("./routes/warranty-claims"));
const stats_1 = __importDefault(require("./routes/stats"));
const email_scanner_1 = __importDefault(require("./routes/email-scanner"));
const partners_1 = __importDefault(require("./routes/partners"));
const maintenance_1 = __importDefault(require("./routes/maintenance"));
const notifications_1 = __importDefault(require("./routes/notifications"));
const warranty_purchases_1 = __importDefault(require("./routes/warranty-purchases"));
const categories_1 = __importDefault(require("./routes/categories"));
const uploads_1 = __importDefault(require("./routes/uploads"));
const receipts_1 = __importDefault(require("./routes/receipts"));
const audit_1 = __importDefault(require("./routes/audit"));
const webhooks_1 = __importDefault(require("./routes/webhooks"));
// Validate environment before starting
(0, validator_1.validateEnvironment)();
const app = (0, express_1.default)();
// Security middleware
app.use((0, helmet_1.default)({
    contentSecurityPolicy: {
        directives: {
            defaultSrc: ["'self'"],
            styleSrc: ["'self'", "'unsafe-inline'"],
            scriptSrc: ["'self'"],
            imgSrc: ["'self'", "data:", "https:"],
        },
    },
    hsts: {
        maxAge: 31536000,
        includeSubDomains: true,
        preload: true
    }
}));
// CORS
app.use((0, cors_1.default)({
    origin: config_1.config.cors.origins,
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
    allowedHeaders: ['Content-Type', 'Authorization', 'x-csrf-token']
}));
// Compression
app.use((0, compression_1.default)());
// Stripe webhooks — mounted BEFORE body parsing because Stripe
// signature verification requires the raw (unparsed) request body.
// Only the /stripe sub-path needs raw body; RevenueCat uses Bearer token auth.
app.use('/api/v1/webhooks/stripe', express_1.default.raw({ type: 'application/json' }));
// Body parsing
app.use(express_1.default.json({ limit: '10mb' }));
app.use(express_1.default.urlencoded({ extended: true, limit: '10mb' }));
// Webhooks — mounted AFTER body parsing so RevenueCat gets parsed JSON.
// Stripe's raw body was already handled above, and express.json won't overwrite it.
app.use('/api/v1/webhooks', webhooks_1.default);
// Cookie parser for CSRF
app.use((0, cookie_parser_1.default)());
// Request logging
app.use(requestLogger_1.requestLogger);
// CSRF token generation (for non-API routes)
app.use(csrf_1.setCsrfToken);
function registerRoutes(appInstance) {
    // Health checks (no versioning, no auth required)
    appInstance.use('/', health_1.default);
    // API v1 routes
    const apiV1 = express_1.default.Router();
    apiV1.use('/auth', auth_1.default);
    apiV1.use('/users', users_1.default);
    apiV1.use('/homes', homes_1.default);
    apiV1.use('/items', items_1.default);
    apiV1.use('/documents', documents_1.default);
    apiV1.use('/barcode', barcode_1.default);
    apiV1.use('/admin', admin_1.default);
    apiV1.use('/warranty-claims', warranty_claims_1.default);
    apiV1.use('/stats', stats_1.default);
    apiV1.use('/email-scanner', email_scanner_1.default);
    apiV1.use('/partners', partners_1.default);
    apiV1.use('/maintenance', maintenance_1.default);
    apiV1.use('/notifications', notifications_1.default);
    apiV1.use('/warranty-purchases', warranty_purchases_1.default);
    apiV1.use('/categories', categories_1.default);
    apiV1.use('/uploads', uploads_1.default);
    apiV1.use('/receipts', receipts_1.default);
    apiV1.use('/audit', audit_1.default);
    appInstance.use('/api/v1', apiV1);
    // Legacy routes (redirect to v1)
    appInstance.use('/api/auth', auth_1.default);
    appInstance.use('/api/users', users_1.default);
    appInstance.use('/api/homes', homes_1.default);
    appInstance.use('/api/items', items_1.default);
    appInstance.use('/api/documents', documents_1.default);
    appInstance.use('/api/barcode', barcode_1.default);
    appInstance.use('/api/admin', admin_1.default);
    // 404 handler
    appInstance.use((req, res) => {
        res.status(404).json({
            error: 'Not found',
            path: req.path,
            suggestion: 'Check API documentation for available endpoints'
        });
    });
    // Error handler (must be last)
    appInstance.use(errorHandler_1.errorHandler);
}
// Start server (async to initialize rate limiter)
let server;
const PORT = config_1.config.port;
const NOTIFICATION_JOB_LOCK = 93422874;
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
            await runExpirationNotificationsJob();
            scheduleNext();
        }, delay);
    };
    scheduleNext();
}
async function start() {
    const rateLimiter = await (0, rateLimiter_1.initializeRateLimiter)();
    // Insert rate limiter before routes (after requestLogger)
    app.use(rateLimiter);
    registerRoutes(app);
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
    server.close(() => {
        logger_1.logger.info('HTTP server closed');
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
exports.default = app;
//# sourceMappingURL=index.js.map