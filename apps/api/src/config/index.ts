import dotenv from 'dotenv';
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
    secret: process.env.JWT_SECRET || 'your-secret-key-change-this',
    expiresIn: process.env.JWT_EXPIRES_IN || '1h',
    refreshSecret: process.env.REFRESH_TOKEN_SECRET || 'your-refresh-secret',
    refreshExpiresIn: process.env.REFRESH_TOKEN_EXPIRES_IN || '7d',
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
  
  cors: {
    origins: (process.env.CORS_ORIGINS || 'http://localhost:3000,http://localhost:3001').split(','),
  },
  
  rateLimit: {
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // limit each IP to 100 requests per windowMs
  },
};
