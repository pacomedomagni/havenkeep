import dotenv from 'dotenv';
import fs from 'fs';
import type { SignOptions } from 'jsonwebtoken';
import path from 'path';

// Load environment variables
dotenv.config({ path: path.join(__dirname, '../../.env') });

/**
 * Parse `process.env[name]` as a positive integer.  If the env var is unset,
 * empty, or not a finite number, return `fallback`.  Without this guard,
 * `parseInt(undefined as any, 10)` returns NaN and code like `count >= NaN`
 * silently evaluates false — disabling free-tier gates and rate-limit caps.
 */
function intFromEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw.trim() === '') return fallback;
  const n = parseInt(raw, 10);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}

// Resolve a secret from either `${name}` or `${name}_FILE` (Docker secrets pattern).
// Precedence: the `_FILE` variant wins when present, since Docker secrets mount
// files read-only at a deterministic path.
function readSecret(name: string): string | undefined {
  const filePath = process.env[`${name}_FILE`];
  if (filePath && filePath.trim() !== '') {
    try {
      return fs.readFileSync(filePath, 'utf8').trim();
    } catch (err) {
      throw new Error(
        `Failed to read secret file for ${name} at ${filePath}: ${(err as Error).message}`,
      );
    }
  }
  const direct = process.env[name];
  return direct && direct.trim() !== '' ? direct : undefined;
}

export const config = {
  env: process.env.NODE_ENV || 'development',
  port: intFromEnv('PORT', 3000),

  database: {
    url: readSecret('DATABASE_URL') || '',
    host: process.env.DB_HOST || 'localhost',
    port: intFromEnv('DB_PORT', 5432),
    name: process.env.DB_NAME || 'havenkeep',
    user: process.env.DB_USER || 'havenkeep',
    password: readSecret('DB_PASSWORD') || readSecret('POSTGRES_PASSWORD') || '',
    // SSL is required to the DB only when DB_SSL=true (e.g. RDS / Aiven /
    // managed Postgres reachable over the public internet). Staging runs
    // Postgres on the same Docker private network behind Caddy — there is
    // no plaintext-on-the-wire risk and forcing SSL only causes
    // ECONNREFUSED against a non-SSL Postgres listener.
    ssl: process.env.DB_SSL === 'true',
  },

  jwt: {
    get secret(): string {
      const secret = readSecret('JWT_SECRET');
      if (process.env.NODE_ENV === 'production' && !secret) {
        throw new Error('JWT_SECRET (or JWT_SECRET_FILE) must be set in production');
      }
      if (!secret) {
        if (process.env.NODE_ENV === 'development' || process.env.NODE_ENV === 'test') {
          return 'dev-only-secret-do-not-use-in-production';
        }
        throw new Error('JWT_SECRET must be set');
      }
      return secret;
    },
    expiresIn: (process.env.JWT_EXPIRES_IN || '1h') as SignOptions['expiresIn'],
    get refreshSecret(): string {
      const secret = readSecret('REFRESH_TOKEN_SECRET');
      if (process.env.NODE_ENV === 'production' && !secret) {
        throw new Error('REFRESH_TOKEN_SECRET (or REFRESH_TOKEN_SECRET_FILE) must be set in production');
      }
      if (!secret) {
        if (process.env.NODE_ENV === 'development' || process.env.NODE_ENV === 'test') {
          return 'dev-only-refresh-secret';
        }
        throw new Error('REFRESH_TOKEN_SECRET must be set');
      }
      return secret;
    },
    refreshExpiresIn: (process.env.REFRESH_TOKEN_EXPIRES_IN || '7d') as SignOptions['expiresIn'],
  },

  redis: {
    url: readSecret('REDIS_URL') || 'redis://localhost:6379',
    password: readSecret('REDIS_PASSWORD'),
  },

  minio: {
    endpoint: process.env.MINIO_ENDPOINT || 'localhost',
    port: intFromEnv('MINIO_PORT', 9000),
    useSSL: process.env.MINIO_USE_SSL === 'true',
    accessKey: readSecret('MINIO_ACCESS_KEY') || 'minioadmin',
    secretKey: readSecret('MINIO_SECRET_KEY') || 'minioadmin',
    bucket: process.env.MINIO_BUCKET || 'havenkeep',
  },

  stripe: {
    // S-ME-10: required-in-prod. Pre-fix this defaulted to '' silently;
    // a misconfigured prod deploy passed health-checks and broke on
    // first paid action with a generic 500 ("Stripe.accounts.create:
    // Invalid API Key"). Fail-fast at startup instead.
    get secretKey(): string {
      const secret = readSecret('STRIPE_SECRET_KEY');
      if (process.env.NODE_ENV === 'production' && !secret) {
        throw new Error('STRIPE_SECRET_KEY (or _FILE) must be set in production');
      }
      return secret || '';
    },
    // STRIPE_WEBHOOK_SECRET is required in production. The Stripe handler
    // refuses to start if it's empty so a misconfigured prod deploy fails
    // loudly instead of silently accepting unsigned webhooks.
    get webhookSecret(): string {
      const secret = readSecret('STRIPE_WEBHOOK_SECRET');
      if (process.env.NODE_ENV === 'production' && !secret) {
        throw new Error('STRIPE_WEBHOOK_SECRET (or _FILE) must be set in production');
      }
      return secret || '';
    },
    get premiumPriceId(): string {
      const v = process.env.STRIPE_PRICE_ID_PREMIUM;
      if (process.env.NODE_ENV === 'production' && !v) {
        throw new Error('STRIPE_PRICE_ID_PREMIUM must be set in production');
      }
      return v || '';
    },
    // OAuth-style server-side env to allow sandbox webhooks during local
    // dev/test. Production never honors this flag.
    allowSandboxWebhooks: process.env.NODE_ENV !== 'production'
      && process.env.STRIPE_ALLOW_SANDBOX !== 'false',
  },

  sendgrid: {
    apiKey: readSecret('SENDGRID_API_KEY') || '',
    fromEmail: process.env.SENDGRID_FROM_EMAIL || 'noreply@havenkeep.com',
    replyToEmail: process.env.SENDGRID_REPLY_TO_EMAIL || 'support@havenkeep.com',
  },

  google: {
    clientId: process.env.GOOGLE_CLIENT_ID || '',
    // Used by the email-scanner OAuth code exchange to mint Gmail access
    // tokens server-side. Empty if Gmail scanning is not deployed.
    clientSecret: readSecret('GOOGLE_CLIENT_SECRET') || '',
  },

  microsoft: {
    clientId: process.env.MICROSOFT_CLIENT_ID || '',
    clientSecret: readSecret('MICROSOFT_CLIENT_SECRET') || '',
    // Tenant ID for Outlook OAuth. Defaults to 'common' so personal +
    // school/work accounts both authenticate without per-tenant config.
    tenant: process.env.MICROSOFT_TENANT || 'common',
  },

  apple: {
    bundleId: process.env.APPLE_BUNDLE_ID || '',
    // Comma-separated Apple Services IDs used by the Android / web Sign-in
    // with Apple flow. iOS native flow's identity token is `aud`-stamped with
    // the bundle ID; the Android web flow's token is `aud`-stamped with the
    // Services ID configured in the Apple Developer Portal. Both are
    // accepted here so a single backend endpoint validates either path.
    servicesIds: (process.env.APPLE_SERVICES_IDS || '')
      .split(',')
      .map((s) => s.trim())
      .filter((s) => s.length > 0),
  },

  openai: {
    // S-ME-10: required-in-prod so receipt scan / email scanner don't
    // 500 on the first request after a misconfigured deploy.
    get apiKey(): string {
      const key = readSecret('OPENAI_API_KEY');
      if (process.env.NODE_ENV === 'production' && !key) {
        throw new Error('OPENAI_API_KEY (or _FILE) must be set in production');
      }
      return key || '';
    },
  },

  revenuecat: {
    get apiKey(): string {
      const key = readSecret('REVENUECAT_SECRET_API_KEY');
      if (!key && process.env.NODE_ENV === 'production') {
        throw new Error('REVENUECAT_SECRET_API_KEY must be set in production');
      }
      return key || '';
    },
    get webhookSecret(): string {
      const secret = readSecret('REVENUECAT_WEBHOOK_SECRET');
      if (!secret && process.env.NODE_ENV === 'production') {
        throw new Error('REVENUECAT_WEBHOOK_SECRET must be set in production');
      }
      return secret || '';
    },
  },

  firebase: {
    // JSON string of the Firebase service account credentials.
    // Set FIREBASE_SERVICE_ACCOUNT_JSON or FIREBASE_SERVICE_ACCOUNT_JSON_FILE.
    // If not set, FCM push delivery is silently disabled.
    serviceAccountJson: readSecret('FIREBASE_SERVICE_ACCOUNT_JSON') || '',
  },

  app: {
    baseUrl: process.env.APP_BASE_URL || 'http://localhost:3000',
    frontendUrl: process.env.FRONTEND_URL || 'http://localhost:3000',
    dashboardUrl: process.env.DASHBOARD_URL || 'http://localhost:3001',
    apiUrl: process.env.API_URL || 'http://localhost:3000',
  },

  freeTier: {
    itemLimit: intFromEnv('FREE_TIER_ITEM_LIMIT', 5),
  },

  // RevenueCat: 'PRODUCTION' webhook events are always processed. Sandbox
  // events are only accepted when this flag is true (default: dev/test only).
  revenuecatAllowSandboxWebhooks:
    process.env.NODE_ENV !== 'production'
    && process.env.REVENUECAT_ALLOW_SANDBOX !== 'false',

  // OAuth refresh tokens for the email scanner are encrypted at rest with
  // AES-256-GCM. Key derived from this secret via SHA-256 → 32-byte key.
  // [Legacy] is a comma-separated list of previously-active secrets;
  // decrypt tries them in order if the primary key fails its GCM auth
  // tag check. This makes secret rotation a two-step process: rotate the
  // primary, push the old value into the legacy list, then re-encrypt
  // existing rows in the background before dropping the legacy entry.
  oauthEncryptionSecret: readSecret('OAUTH_TOKEN_ENCRYPTION_SECRET') || '',
  oauthEncryptionSecretsLegacy: (process.env.OAUTH_TOKEN_ENCRYPTION_SECRET_LEGACY || '')
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0),

  cors: {
    origins: (process.env.CORS_ORIGINS || 'http://localhost:3000,http://localhost:3001')
      .split(',')
      .map((o) => o.trim())
      .filter((o) => o.length > 0),
  },

  rateLimit: {
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // limit each IP to 100 requests per windowMs
  },
};
