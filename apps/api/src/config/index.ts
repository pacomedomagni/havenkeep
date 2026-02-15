import dotenv from 'dotenv';
import type { SignOptions } from 'jsonwebtoken';
import path from 'path';

// Load environment variables
dotenv.config({ path: path.join(__dirname, '../../.env') });

export const config = {
  env: process.env.NODE_ENV || 'development',
  port: parseInt(process.env.PORT || '3000', 10),

  database: {
    url: process.env.DATABASE_URL || '',
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432', 10),
    name: process.env.DB_NAME || 'havenkeep',
    user: process.env.DB_USER || 'havenkeep',
    password: process.env.DB_PASSWORD || '',
    ssl: process.env.NODE_ENV === 'production',
  },

  jwt: {
    get secret(): string {
      const secret = process.env.JWT_SECRET;
      if (process.env.NODE_ENV === 'production' && (!secret || secret.trim() === '')) {
        throw new Error('JWT_SECRET must be set and non-empty in production');
      }
      if (process.env.NODE_ENV !== 'production') {
        return secret || 'dev-only-secret-do-not-use-in-production';
      }
      return secret!;
    },
    expiresIn: (process.env.JWT_EXPIRES_IN || '1h') as SignOptions['expiresIn'],
    get refreshSecret(): string {
      const secret = process.env.REFRESH_TOKEN_SECRET;
      if (process.env.NODE_ENV === 'production' && (!secret || secret.trim() === '')) {
        throw new Error('REFRESH_TOKEN_SECRET must be set and non-empty in production');
      }
      if (process.env.NODE_ENV !== 'production') {
        return secret || 'dev-only-refresh-secret';
      }
      return secret!;
    },
    refreshExpiresIn: (process.env.REFRESH_TOKEN_EXPIRES_IN || '7d') as SignOptions['expiresIn'],
  },
  
  redis: {
    url: process.env.REDIS_URL || 'redis://localhost:6379',
    password: process.env.REDIS_PASSWORD,
  },
  
  minio: {
    endpoint: process.env.MINIO_ENDPOINT || 'localhost',
    port: parseInt(process.env.MINIO_PORT || '9000', 10),
    useSSL: process.env.MINIO_USE_SSL === 'true',
    accessKey: process.env.MINIO_ACCESS_KEY || 'minioadmin',
    secretKey: process.env.MINIO_SECRET_KEY || 'minioadmin',
    bucket: process.env.MINIO_BUCKET || 'havenkeep',
  },
  
  stripe: {
    secretKey: process.env.STRIPE_SECRET_KEY || '',
    webhookSecret: process.env.STRIPE_WEBHOOK_SECRET || '',
    premiumPriceId: process.env.STRIPE_PRICE_ID_PREMIUM || '',
  },

  sendgrid: {
    apiKey: process.env.SENDGRID_API_KEY || '',
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
    apiKey: process.env.OPENAI_API_KEY || '',
  },

  revenuecat: {
    get apiKey(): string {
      const key = process.env.REVENUECAT_SECRET_API_KEY;
      if (!key && process.env.NODE_ENV === 'production') {
        throw new Error('REVENUECAT_SECRET_API_KEY must be set in production');
      }
      return key || '';
    },
    get webhookSecret(): string {
      const secret = process.env.REVENUECAT_WEBHOOK_SECRET;
      if (!secret && process.env.NODE_ENV === 'production') {
        throw new Error('REVENUECAT_WEBHOOK_SECRET must be set in production');
      }
      return secret || '';
    },
  },

  app: {
    baseUrl: process.env.APP_BASE_URL || 'http://localhost:3000',
    frontendUrl: process.env.FRONTEND_URL || 'http://localhost:3000',
    dashboardUrl: process.env.DASHBOARD_URL || 'http://localhost:3001',
    apiUrl: process.env.API_URL || 'http://localhost:3000',
  },

  cors: {
    origins: (process.env.CORS_ORIGINS || 'http://localhost:3000,http://localhost:3001').split(','),
  },

  rateLimit: {
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // limit each IP to 100 requests per windowMs
  },
};
