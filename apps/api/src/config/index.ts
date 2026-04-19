import dotenv from 'dotenv';
import fs from 'fs';
import type { SignOptions } from 'jsonwebtoken';
import path from 'path';

// Load environment variables
dotenv.config({ path: path.join(__dirname, '../../.env') });

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
  port: parseInt(process.env.PORT || '3000', 10),

  database: {
    url: readSecret('DATABASE_URL') || '',
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432', 10),
    name: process.env.DB_NAME || 'havenkeep',
    user: process.env.DB_USER || 'havenkeep',
    password: readSecret('DB_PASSWORD') || readSecret('POSTGRES_PASSWORD') || '',
    ssl: process.env.NODE_ENV === 'production' || process.env.NODE_ENV === 'staging',
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
    port: parseInt(process.env.MINIO_PORT || '9000', 10),
    useSSL: process.env.MINIO_USE_SSL === 'true',
    accessKey: readSecret('MINIO_ACCESS_KEY') || 'minioadmin',
    secretKey: readSecret('MINIO_SECRET_KEY') || 'minioadmin',
    bucket: process.env.MINIO_BUCKET || 'havenkeep',
  },

  stripe: {
    secretKey: readSecret('STRIPE_SECRET_KEY') || '',
    webhookSecret: readSecret('STRIPE_WEBHOOK_SECRET') || '',
    premiumPriceId: process.env.STRIPE_PRICE_ID_PREMIUM || '',
  },

  sendgrid: {
    apiKey: readSecret('SENDGRID_API_KEY') || '',
    fromEmail: process.env.SENDGRID_FROM_EMAIL || 'noreply@havenkeep.com',
    replyToEmail: process.env.SENDGRID_REPLY_TO_EMAIL || 'support@havenkeep.com',
  },

  google: {
    clientId: process.env.GOOGLE_CLIENT_ID || '',
  },

  apple: {
    bundleId: process.env.APPLE_BUNDLE_ID || '',
  },

  openai: {
    apiKey: readSecret('OPENAI_API_KEY') || '',
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
    itemLimit: parseInt(process.env.FREE_TIER_ITEM_LIMIT || '5', 10),
  },

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
