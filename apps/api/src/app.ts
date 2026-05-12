import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import compression from 'compression';
import cookieParser from 'cookie-parser';
import { config } from './config';
import { errorHandler } from './middleware/errorHandler';
import { requestLogger } from './middleware/requestLogger';
import { setCsrfToken, validateCsrfToken } from './middleware/csrf';

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
import mfaRoutes from './routes/mfa';
import { revenueCatWebhookRouter } from './routes/webhooks';
import newsletterRoutes from './routes/newsletter';
import contactRoutes from './routes/contact';
import csrfRoutes from './routes/csrf';

export interface CreateAppOptions {
  rateLimiter?: express.RequestHandler;
}

export function createApp(options: CreateAppOptions = {}) {
  const app = express();

  // Audit Ch11-I005: trust proxy=1 is OK behind a single Caddy in front of
  // the app. If a deploy ever introduces a 2-hop proxy chain, set
  // `TRUST_PROXY_HOPS` to the number of trusted proxies so Express picks
  // the correct X-Forwarded-For entry.
  const trustProxyHops = parseInt(process.env.TRUST_PROXY_HOPS || '1', 10);
  app.set('trust proxy', Number.isFinite(trustProxyHops) ? trustProxyHops : 1);

  // Security middleware. CSP is tightened to only the origins this API
  // actually talks to — RevenueCat (entitlements) — so an XSS in an
  // error page can't exfiltrate to arbitrary hosts.
  app.use(helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
        scriptSrc: ["'self'"],
        // S-LO-06: tightened from `https:` (any HTTPS host) to the actual
        // sources we render images from. The API doesn't render HTML so
        // this is mostly belt-and-braces, but keeping the directive
        // narrow ensures a future error-page template can't quietly load
        // images from arbitrary hosts.
        imgSrc: [
          "'self'",
          'data:',
          'https://lh3.googleusercontent.com',
          'https://lh4.googleusercontent.com',
          'https://lh5.googleusercontent.com',
          'https://lh6.googleusercontent.com',
        ],
        connectSrc: [
          "'self'",
          'https://api.revenuecat.com',
        ],
        frameAncestors: ["'none'"],
        objectSrc: ["'none'"],
        baseUri: ["'self'"],
        formAction: ["'self'"],
      },
    },
    hsts: {
      maxAge: 31536000,
      includeSubDomains: true,
      preload: true,
    },
    referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
    // Audit Ch11-I001: COOP / COEP / CORP made explicit instead of relying
    // on Helmet defaults. COEP=require-corp + CORP=same-origin form a strict
    // cross-origin posture; COOP=same-origin opens isolation for window
    // references.
    crossOriginOpenerPolicy: { policy: 'same-origin' },
    crossOriginEmbedderPolicy: { policy: 'require-corp' },
    crossOriginResourcePolicy: { policy: 'same-origin' },
  }));

  // CORS — origin allowlist with explicit ACAO for credentialed requests.
  // Audit Ch11-I006: passing the array form to `cors()` would silently
  // accept any origin not on the list (no ACAO header sent → CORS reject in
  // browser, but no server-side trace). We use a function so non-allowed
  // origins are explicitly rejected with an error logged.
  app.use(cors({
    origin: (origin, cb) => {
      if (!origin) return cb(null, true); // server-to-server, curl, mobile
      if (config.cors.origins.includes(origin)) return cb(null, true);
      return cb(new Error(`CORS: origin not allowed (${origin})`));
    },
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
    // Audit Ch11-I007: x-request-id allowed so client-set request ids
    // round-trip through CORS preflight.
    allowedHeaders: ['Content-Type', 'Authorization', 'x-csrf-token', 'x-request-id', 'idempotency-key'],
    exposedHeaders: ['x-request-id'],
  }));

  // Body parsing.  Audit Ch11-I003: JSON parser limited
  // to 1MB AND `strict: true` so only `[`/`{` are accepted (defends against
  // some HPP-style abuse where a number/string body produces a misparsed
  // payload).
  app.use(express.json({ limit: '1mb', strict: true }));
  app.use(express.urlencoded({ extended: true, limit: '1mb' }));

  // Audit Ch11-I004: compression mounted AFTER body parsing so a
  // BREACH-style attack can't leverage compressed-response gadgets that
  // mix attacker- and victim-controlled bytes in the same response (the
  // CSRF cookie is set in the response, the attacker's body could come
  // through compression-on-request).  Order: body → compression → routes.
  app.use(compression());

  // RevenueCat webhook — JSON-parsed body is fine.
  app.use('/api/v1/webhooks/revenuecat', revenueCatWebhookRouter);

  // Cookie parser for CSRF
  app.use(cookieParser());

  // Request logging — installed BEFORE rate limiter so 429s also get a log
  // line with the standard requestId.
  app.use(requestLogger);

  // Audit Ch11-I008: rate limiter mounted before the per-route handlers.
  // Body parsing already ran above; the limiter still rejects pre-handler.
  if (options.rateLimiter) {
    app.use(options.rateLimiter);
  }

  // CSRF token generation & validation — runs on cookie-bearing requests
  // only, after body parser so error responses still carry parsed fields.
  app.use(setCsrfToken);
  app.use(validateCsrfToken);

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
  apiV1.use('/mfa', mfaRoutes);
  apiV1.use('/newsletter', newsletterRoutes);
  apiV1.use('/contact', contactRoutes);
  apiV1.use('/csrf', csrfRoutes);

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
