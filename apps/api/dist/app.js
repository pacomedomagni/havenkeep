"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.createApp = createApp;
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const helmet_1 = __importDefault(require("helmet"));
const compression_1 = __importDefault(require("compression"));
const cookie_parser_1 = __importDefault(require("cookie-parser"));
const config_1 = require("./config");
const errorHandler_1 = require("./middleware/errorHandler");
const requestLogger_1 = require("./middleware/requestLogger");
const csrf_1 = require("./middleware/csrf");
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
const newsletter_1 = __importDefault(require("./routes/newsletter"));
const contact_1 = __importDefault(require("./routes/contact"));
function createApp(options = {}) {
    const app = (0, express_1.default)();
    // Trust the first proxy (nginx) so X-Forwarded-For is used correctly
    app.set('trust proxy', 1);
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
    app.use('/api/v1/webhooks/stripe', express_1.default.raw({ type: 'application/json' }));
    // Body parsing
    app.use(express_1.default.json({ limit: '1mb' }));
    app.use(express_1.default.urlencoded({ extended: true, limit: '1mb' }));
    // Webhooks — mounted AFTER body parsing so RevenueCat gets parsed JSON.
    app.use('/api/v1/webhooks', webhooks_1.default);
    // Cookie parser for CSRF
    app.use((0, cookie_parser_1.default)());
    // Request logging
    app.use(requestLogger_1.requestLogger);
    // CSRF token generation & validation
    app.use(csrf_1.setCsrfToken);
    app.use(csrf_1.validateCsrfToken);
    // Rate limiter (optional — skipped in tests)
    if (options.rateLimiter) {
        app.use(options.rateLimiter);
    }
    // Register routes
    // Health checks (no versioning, no auth required)
    app.use('/', health_1.default);
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
    apiV1.use('/newsletter', newsletter_1.default);
    apiV1.use('/contact', contact_1.default);
    app.use('/api/v1', apiV1);
    // 404 handler
    app.use((req, res) => {
        res.status(404).json({
            error: 'Not found',
            suggestion: 'Check API documentation for available endpoints'
        });
    });
    // Error handler (must be last)
    app.use(errorHandler_1.errorHandler);
    return app;
}
//# sourceMappingURL=app.js.map