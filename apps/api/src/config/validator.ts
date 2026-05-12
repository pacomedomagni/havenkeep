import { logger } from '../utils/logger';

// Validator deliberately does NOT import ./index (Ch11-I050) — it runs before
// the config object is constructed so we can fail-fast on bad env BEFORE any
// other module accidentally reads a half-initialized config. Everything below
// reads `process.env` directly.

interface ValidationContext {
  env: string;
  errors: string[];
  warnings: string[];
}

/**
 * Required vars across every environment. We accept EITHER `DATABASE_URL`
 * OR the discrete set (`DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USER`/`DB_PASSWORD`)
 * — the previous "both required" rule (Ch11-I051) made it impossible to use
 * a managed-DB connection string without also setting the discrete vars.
 */
const ALWAYS_REQUIRED = ['NODE_ENV', 'PORT', 'JWT_SECRET', 'REFRESH_TOKEN_SECRET'];

const PRODUCTION_REQUIRED = [
  'STRIPE_SECRET_KEY',
  'STRIPE_WEBHOOK_SECRET',          // promoted from "optional feature" — Ch11-I044
  'MINIO_ACCESS_KEY',
  'MINIO_SECRET_KEY',
];

const OPTIONAL_FEATURES: Array<{ env: string; feature: string }> = [
  { env: 'OPENAI_API_KEY', feature: 'Receipt + email scanning' },
  { env: 'REVENUECAT_SECRET_API_KEY', feature: 'Premium verification' },
  { env: 'REVENUECAT_WEBHOOK_SECRET', feature: 'RevenueCat webhooks' },
  { env: 'GOOGLE_CLIENT_ID', feature: 'Google Sign-In' },
  { env: 'APPLE_BUNDLE_ID', feature: 'Apple Sign-In' },
  { env: 'OAUTH_TOKEN_ENCRYPTION_SECRET', feature: 'Email scanner OAuth integrations' },
];

/** Best-effort check: is this an absolute http(s) URL or a postgres URI? */
function looksLikeUrl(value: string): boolean {
  try {
    const u = new URL(value);
    return ['http:', 'https:', 'postgres:', 'postgresql:', 'redis:', 'rediss:'].includes(u.protocol);
  } catch {
    return false;
  }
}

function checkRequired(ctx: ValidationContext) {
  for (const name of ALWAYS_REQUIRED) {
    if (!process.env[name] || process.env[name]!.trim() === '') {
      ctx.errors.push(`Missing required environment variable: ${name}`);
    }
  }

  // DATABASE_URL OR discrete config — either path is acceptable.
  const hasUrl = !!process.env.DATABASE_URL?.trim();
  const hasDiscrete = ['DB_HOST', 'DB_PORT', 'DB_NAME', 'DB_USER', 'DB_PASSWORD'].every(
    (n) => process.env[n] && process.env[n]!.trim() !== '',
  );
  if (!hasUrl && !hasDiscrete) {
    ctx.errors.push(
      'Database not configured: set DATABASE_URL (preferred) or DB_HOST/DB_PORT/DB_NAME/DB_USER/DB_PASSWORD',
    );
  }
}

function checkUrls(ctx: ValidationContext) {
  // Ch11-I052: validate URL-typed envs are real URLs, not random strings.
  const urlVars = ['DATABASE_URL', 'REDIS_URL', 'APP_BASE_URL', 'FRONTEND_URL', 'DASHBOARD_URL', 'API_URL'];
  for (const name of urlVars) {
    const v = process.env[name];
    if (v && !looksLikeUrl(v)) {
      ctx.errors.push(`${name} is not a valid URL: ${v.slice(0, 60)}`);
    }
  }
}

function checkSecretStrength(ctx: ValidationContext) {
  const jwtSecret = process.env.JWT_SECRET || '';
  if (jwtSecret.length < 32) ctx.errors.push('JWT_SECRET must be at least 32 characters');
  if (/change-this|your-secret|dev-only/i.test(jwtSecret) && ctx.env === 'production') {
    ctx.errors.push('JWT_SECRET is a placeholder — must be replaced for production');
  }

  const refreshSecret = process.env.REFRESH_TOKEN_SECRET || '';
  if (refreshSecret.length < 32) ctx.errors.push('REFRESH_TOKEN_SECRET must be at least 32 characters');
  if (/change-this|your-secret|dev-only/i.test(refreshSecret) && ctx.env === 'production') {
    ctx.errors.push('REFRESH_TOKEN_SECRET is a placeholder — must be replaced for production');
  }

  if (jwtSecret && refreshSecret && jwtSecret === refreshSecret) {
    ctx.errors.push('JWT_SECRET and REFRESH_TOKEN_SECRET must be different');
  }

  // Ch11-I054: provider keys carry well-known prefixes. We don't fail on
  // mismatch in dev (you might be using a fake), only in production.
  if (ctx.env === 'production') {
    const sendgridKey = process.env.SENDGRID_API_KEY || '';
    if (sendgridKey && !sendgridKey.startsWith('SG.')) {
      ctx.errors.push('SENDGRID_API_KEY does not look like a SendGrid key (SG.…)');
    }
  }
}

function checkProductionRequired(ctx: ValidationContext) {
  if (ctx.env !== 'production') return;
  for (const name of PRODUCTION_REQUIRED) {
    if (!process.env[name] || process.env[name]!.trim() === '') {
      ctx.errors.push(`Missing production environment variable: ${name}`);
    }
  }
  // Ch11-I053: substring-includes("dev") on the password was fragile; check
  // that the password is at least 16 chars AND not equal to the well-known
  // dev value docker-compose ships.
  const dbPass = process.env.DB_PASSWORD || process.env.POSTGRES_PASSWORD || '';
  if (dbPass && dbPass.length < 16) {
    ctx.errors.push('Database password is too short for production (>=16 chars required)');
  }
  if (dbPass === 'havenkeep_dev_2026') {
    ctx.errors.push('Database password is the development default — must be replaced');
  }
}

function checkOptionalFeatures(ctx: ValidationContext) {
  for (const optional of OPTIONAL_FEATURES) {
    const v = process.env[optional.env];
    if (!v || v.trim() === '') {
      ctx.warnings.push(`${optional.env} not set — ${optional.feature} will be disabled`);
    }
  }
}

export function validateEnvironment(): void {
  const ctx: ValidationContext = {
    env: process.env.NODE_ENV || 'development',
    errors: [],
    warnings: [],
  };

  checkRequired(ctx);
  checkUrls(ctx);
  checkSecretStrength(ctx);
  checkProductionRequired(ctx);
  checkOptionalFeatures(ctx);

  for (const w of ctx.warnings) logger.warn(w);

  if (ctx.errors.length > 0) {
    logger.error({ errors: ctx.errors }, 'Environment validation failed');
    for (const err of ctx.errors) logger.error(err);
    process.exit(1);
  }

  logger.info({ env: ctx.env, warnings: ctx.warnings.length }, 'Environment configuration validated');
}
