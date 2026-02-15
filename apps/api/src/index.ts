import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import compression from 'compression';
import cookieParser from 'cookie-parser';
import { config } from './config';
import { validateEnvironment } from './config/validator';
import { logger } from './utils/logger';
import { errorHandler } from './middleware/errorHandler';
import { requestLogger } from './middleware/requestLogger';
import { initializeRateLimiter } from './middleware/rateLimiter';
import { initializeTokenBlacklist, closeTokenBlacklist } from './utils/token-blacklist';
import { setCsrfToken } from './middleware/csrf';
import { NotificationsService } from './services/notifications.service';
import { pool } from './db';

// Routes
import authRoutes from './routes/auth';
import usersRoutes from './routes/users';
import homesRoutes from './routes/homes';
import itemsRoutes from './routes/items';
import documentsRoutes from './routes/documents';
import barcodeRoutes from './routes/barcode';
import adminRoutes from './routes/admin';
import healthRoutes from './routes/health';
import warrantyClaimsRoutes from './routes/warranty-claims';
import statsRoutes from './routes/stats';
import emailScannerRoutes from './routes/email-scanner';
import partnersRoutes from './routes/partners';
import maintenanceRoutes from './routes/maintenance';
import notificationsRoutes from './routes/notifications';
import warrantyPurchasesRoutes from './routes/warranty-purchases';
import categoriesRoutes from './routes/categories';
import uploadsRoutes from './routes/uploads';
import receiptsRoutes from './routes/receipts';
import auditRoutes from './routes/audit';
import webhooksRoutes from './routes/webhooks';

// Validate environment before starting
validateEnvironment();

const app = express();

// Security middleware
app.use(helmet({
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
app.use(cors({
  origin: config.cors.origins,
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
  allowedHeaders: ['Content-Type', 'Authorization', 'x-csrf-token']
}));

// Compression
app.use(compression());

// Stripe webhooks — mounted BEFORE body parsing because Stripe
// signature verification requires the raw (unparsed) request body.
// Only the /stripe sub-path needs raw body; RevenueCat uses Bearer token auth.
app.use(
  '/api/v1/webhooks/stripe',
  express.raw({ type: 'application/json' })
);

// Body parsing
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true, limit: '1mb' }));

// Webhooks — mounted AFTER body parsing so RevenueCat gets parsed JSON.
// Stripe's raw body was already handled above, and express.json won't overwrite it.
app.use('/api/v1/webhooks', webhooksRoutes);

// Cookie parser for CSRF
app.use(cookieParser());

// Request logging
app.use(requestLogger);

// CSRF token generation (for non-API routes)
app.use(setCsrfToken);

function registerRoutes(appInstance: express.Express) {
  // Health checks (no versioning, no auth required)
  appInstance.use('/', healthRoutes);

  // API v1 routes
  const apiV1 = express.Router();

  apiV1.use('/auth', authRoutes);
  apiV1.use('/users', usersRoutes);
  apiV1.use('/homes', homesRoutes);
  apiV1.use('/items', itemsRoutes);
  apiV1.use('/documents', documentsRoutes);
  apiV1.use('/barcode', barcodeRoutes);
  apiV1.use('/admin', adminRoutes);
  apiV1.use('/warranty-claims', warrantyClaimsRoutes);
  apiV1.use('/stats', statsRoutes);
  apiV1.use('/email-scanner', emailScannerRoutes);
  apiV1.use('/partners', partnersRoutes);
  apiV1.use('/maintenance', maintenanceRoutes);
  apiV1.use('/notifications', notificationsRoutes);
  apiV1.use('/warranty-purchases', warrantyPurchasesRoutes);
  apiV1.use('/categories', categoriesRoutes);
  apiV1.use('/uploads', uploadsRoutes);
  apiV1.use('/receipts', receiptsRoutes);
  apiV1.use('/audit', auditRoutes);

  appInstance.use('/api/v1', apiV1);

  // DEPRECATED: Legacy unversioned routes. Will be removed in a future release.
  // Clients should use /api/v1/* endpoints instead.
  appInstance.use('/api/auth', authRoutes);
  appInstance.use('/api/users', usersRoutes);
  appInstance.use('/api/homes', homesRoutes);
  appInstance.use('/api/items', itemsRoutes);
  appInstance.use('/api/documents', documentsRoutes);
  appInstance.use('/api/barcode', barcodeRoutes);
  appInstance.use('/api/admin', adminRoutes);

  // 404 handler
  appInstance.use((req, res) => {
    res.status(404).json({
      error: 'Not found',
      path: req.path,
      suggestion: 'Check API documentation for available endpoints'
    });
  });

  // Error handler (must be last)
  appInstance.use(errorHandler);
}

// Start server (async to initialize rate limiter)
let server: ReturnType<typeof app.listen>;
const PORT = config.port;
const NOTIFICATION_JOB_LOCK = 93422874;

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
      // Always schedule next, even if current run failed
      scheduleNext();
    }, delay);
  };

  scheduleNext();
}

async function start() {
  const rateLimiter = await initializeRateLimiter();
  await initializeTokenBlacklist();
  // Insert rate limiter before routes (after requestLogger)
  app.use(rateLimiter);
  registerRoutes(app);

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
      logger.info('Redis connection closed');
    } catch (err) {
      logger.error({ err }, 'Error closing Redis');
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

export default app;
