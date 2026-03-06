import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import compression from 'compression';
import cookieParser from 'cookie-parser';
import { config } from './config';
import { errorHandler } from './middleware/errorHandler';
import { requestLogger } from './middleware/requestLogger';
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
import webhooksRoutes from './routes/webhooks';
import newsletterRoutes from './routes/newsletter';
import contactRoutes from './routes/contact';

export interface CreateAppOptions {
  rateLimiter?: express.RequestHandler;
}

export function createApp(options: CreateAppOptions = {}) {
  const app = express();

  // Trust the first proxy (nginx) so X-Forwarded-For is used correctly
  app.set('trust proxy', 1);

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
  app.use(
    '/api/v1/webhooks/stripe',
    express.raw({ type: 'application/json' })
  );

  // Body parsing
  app.use(express.json({ limit: '1mb' }));
  app.use(express.urlencoded({ extended: true, limit: '1mb' }));

  // Webhooks — mounted AFTER body parsing so RevenueCat gets parsed JSON.
  app.use('/api/v1/webhooks', webhooksRoutes);

  // Cookie parser for CSRF
  app.use(cookieParser());

  // Request logging
  app.use(requestLogger);

  // CSRF token generation
  app.use(setCsrfToken);

  // Rate limiter (optional — skipped in tests)
  if (options.rateLimiter) {
    app.use(options.rateLimiter);
  }

  // Register routes
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
  apiV1.use('/newsletter', newsletterRoutes);
  apiV1.use('/contact', contactRoutes);

  app.use('/api/v1', apiV1);

  // 404 handler
  app.use((req: express.Request, res: express.Response) => {
    res.status(404).json({
      error: 'Not found',
      suggestion: 'Check API documentation for available endpoints'
    });
  });

  // Error handler (must be last)
  app.use(errorHandler);

  return app;
}
