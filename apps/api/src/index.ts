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
import { setCsrfToken } from './middleware/csrf';

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

// Body parsing
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Cookie parser for CSRF
app.use(cookieParser());

// Request logging
app.use(requestLogger);

// CSRF token generation (for non-API routes)
app.use(setCsrfToken);

// Health checks (no versioning, no auth required)
app.use('/', healthRoutes);

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

app.use('/api/v1', apiV1);

// Legacy routes (redirect to v1)
app.use('/api/auth', authRoutes);
app.use('/api/users', usersRoutes);
app.use('/api/homes', homesRoutes);
app.use('/api/items', itemsRoutes);
app.use('/api/documents', documentsRoutes);
app.use('/api/barcode', barcodeRoutes);
app.use('/api/admin', adminRoutes);

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Not found',
    path: req.path,
    suggestion: 'Check API documentation for available endpoints'
  });
});

// Error handler (must be last)
app.use(errorHandler);

// Start server (async to initialize rate limiter)
let server: ReturnType<typeof app.listen>;
const PORT = config.port;

async function start() {
  const rateLimiter = await initializeRateLimiter();
  // Insert rate limiter before routes (after requestLogger)
  app.use(rateLimiter);

  server = app.listen(PORT, () => {
    logger.info(`🚀 HavenKeep API running on port ${PORT}`);
    logger.info(`📦 Environment: ${config.env}`);
    logger.info(`🔒 CORS origins: ${config.cors.origins.join(', ')}`);
    logger.info(`✅ Environment validated`);
    logger.info(`🔐 Security: Helmet, CORS, Rate Limiting, CSRF Protection`);
    logger.info(`📊 Monitoring: Pino → Promtail → Loki`);
  });
}

start().catch((err) => {
  logger.error({ err }, 'Failed to start server');
  process.exit(1);
});

// Graceful shutdown
const gracefulShutdown = (signal: string) => {
  logger.info(`${signal} received, shutting down gracefully`);
  server.close(() => {
    logger.info('HTTP server closed');
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
