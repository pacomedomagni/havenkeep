import { config } from './index';
import { logger } from '../utils/logger';

const REQUIRED_ENV_VARS = [
  'NODE_ENV',
  'PORT',
  'DATABASE_URL',
  'DB_HOST',
  'DB_PORT',
  'DB_NAME',
  'DB_USER',
  'DB_PASSWORD',
  'JWT_SECRET',
  'REFRESH_TOKEN_SECRET',
];

const PRODUCTION_REQUIRED = [
  'STRIPE_SECRET_KEY',
  'MINIO_ACCESS_KEY',
  'MINIO_SECRET_KEY',
];

const OPTIONAL_FEATURES = [
  { env: 'OPENAI_API_KEY', feature: 'Receipt + email scanning' },
  { env: 'REVENUECAT_SECRET_API_KEY', feature: 'Premium verification' },
  { env: 'REVENUECAT_WEBHOOK_SECRET', feature: 'RevenueCat webhooks' },
  { env: 'STRIPE_WEBHOOK_SECRET', feature: 'Stripe webhooks' },
];

export function validateEnvironment() {
  const errors: string[] = [];

  // Check required vars
  for (const varName of REQUIRED_ENV_VARS) {
    if (!process.env[varName]) {
      errors.push(`Missing required environment variable: ${varName}`);
    }
  }

  // Check JWT secret strength
  if (config.jwt.secret.length < 32) {
    errors.push('JWT_SECRET must be at least 32 characters long');
  }

  if (config.jwt.secret.includes('change-this') || config.jwt.secret.includes('your-secret')) {
    errors.push('JWT_SECRET is using default value - must be changed for production');
  }

  // Production-specific validation
  if (config.env === 'production') {
    for (const varName of PRODUCTION_REQUIRED) {
      if (!process.env[varName]) {
        errors.push(`Missing production environment variable: ${varName}`);
      }
    }

    if (config.database.password.includes('dev') || config.database.password.length < 16) {
      errors.push('Database password is insecure for production');
    }
  }

  if (errors.length > 0) {
    logger.error({ errors }, 'Environment validation failed');
    errors.forEach(err => logger.error(err));
    process.exit(1);
  }

  for (const optional of OPTIONAL_FEATURES) {
    if (!process.env[optional.env]) {
      logger.warn(
        `${optional.env} not set — ${optional.feature} will be disabled or degraded`
      );
    }
  }

  logger.info('Environment configuration validated');
}
