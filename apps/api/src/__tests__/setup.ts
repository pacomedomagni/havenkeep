import path from 'path';
import dotenv from 'dotenv';

// Load .env from project root BEFORE any app code imports
dotenv.config({ path: path.join(__dirname, '../../../../.env') });

// Override env vars for test
process.env.NODE_ENV = 'test';
// Point to Docker postgres on localhost (not internal 'postgres' hostname)
process.env.DB_HOST = 'localhost';
// 4.3: honour TEST_DB_PORT so the harness can run against a sidecar
// Postgres on a free port when :5432 is held (e.g. another project's
// container is already bound to it). Falls back to DB_PORT, then 5432.
// CLAUDE.md 'A' bullet calls this out explicitly.
process.env.DB_PORT =
  process.env.TEST_DB_PORT || process.env.DB_PORT || '5432';
// Force the test DB to a *_test name regardless of what .env carries. The
// dev DB shipped in docker-compose.yml is `havenkeep`, but the test harness
// destroys the schema between suites so we never run against the dev DB.
// Tests opt-in by creating a sibling `havenkeep_test` database — see
// `npm run test:db:setup` (or the README) for the one-off creation.
process.env.DB_NAME = process.env.TEST_DB_NAME || 'havenkeep_test';
process.env.DATABASE_URL = `postgresql://${process.env.DB_USER}:${process.env.DB_PASSWORD}@localhost:${process.env.DB_PORT}/${process.env.DB_NAME}`;
// 4.3: honour TEST_REDIS_URL when the harness needs a sidecar Redis.
process.env.REDIS_URL = process.env.TEST_REDIS_URL || 'redis://localhost:6379';
// Point to Docker minio on localhost
process.env.MINIO_ENDPOINT = 'localhost';
// Default test secrets for the email-scanner OAuth + OpenAI flows. The
// outbound HTTP calls are stubbed by the test mocks, so the real values
// don't matter — only that the config-level guards see something non-empty.
process.env.OAUTH_TOKEN_ENCRYPTION_SECRET ||= 'test-oauth-encryption-secret-32bytes!';
process.env.OPENAI_API_KEY ||= 'sk-test-fake-not-real';
process.env.REVENUECAT_WEBHOOK_SECRET ||= 'rc_test_secret';
process.env.STRIPE_SECRET_KEY ||= 'sk_test_fake_for_unit_tests';
process.env.STRIPE_WEBHOOK_SECRET ||= 'whsec_test_fake_for_unit_tests';
// Tests using example.com as redirect_uri need to opt in via the env.
process.env.OAUTH_REDIRECT_URI_PREFIXES ||=
  'havenkeep://oauth-callback,https://havenkeep.com/oauth-callback,https://example.com/cb';

// Hard guard: tests TRUNCATE the entire schema between suites. If DATABASE_URL
// or DB_NAME are misconfigured (e.g. someone copy-pasted production env vars
// into a local shell) this would wipe production. Refuse to load the test
// harness unless the DB name explicitly contains "test".
{
  const dbName = (process.env.DB_NAME || '').toLowerCase();
  if (!dbName.includes('test')) {
    // Bail before any module that opens a connection is imported.
    throw new Error(
      `Refusing to start test harness: DB_NAME='${process.env.DB_NAME}' does not contain "test". ` +
      `If you intend to truncate this database, rename it to include 'test'.`
    );
  }
}

import { pool } from '../db';
import { createClient } from 'redis';

// Flush rate limiter keys in Redis between tests
let redisClient: ReturnType<typeof createClient> | null = null;

async function getTestRedis() {
  if (!redisClient) {
    redisClient = createClient({ url: process.env.REDIS_URL });
    await redisClient.connect();
  }
  return redisClient;
}

async function flushRedis() {
  const redis = await getTestRedis();
  await redis.flushDb();
}

// Tables to truncate between test suites (order matters for FK constraints)
const TABLES = [
  'webhook_events',
  'webhook_event_high_water',
  'audit_logs',
  'user_push_tokens',
  'email_verification_tokens',
  'password_reset_tokens',
  'refresh_tokens',
  'warranty_claim_state_history',
  'warranty_claims',
  'warranty_purchases',
  'maintenance_history',
  'maintenance_schedules',
  'notification_history',
  'notification_outbox',
  'notification_preferences',
  'documents',
  'email_scanner_review_queue',
  'email_scanner_seen_messages',
  'email_scans',
  'user_oauth_integrations',
  'user_mfa_backup_codes',
  'user_mfa_factors',
  // Phase 6 tables — keep before `users` so the FK CASCADE order holds.
  'openai_usage',
  'receipt_scan_idempotency',
  'items',
  'homes',
  'partner_gifts',
  'partners',
  'newsletter_subscribers',
  'contact_submissions',
  'user_analytics',
  'savings_feed',
  'request_idempotency',
  'gift_verify_attempts',
  'barcode_lookup_quota',
  // Standalone tables (no FK to users — TRUNCATE CASCADE on `users` doesn't
  // touch them, so they need to be listed explicitly to avoid cross-test
  // pollution from rows that survive the previous suite.
  'apple_sign_in_nonces',
  'users',
];

export async function cleanDatabase() {
  await pool.query(`TRUNCATE ${TABLES.join(', ')} CASCADE`);
  await flushRedis();
}

afterAll(async () => {
  if (redisClient) {
    await redisClient.quit();
  }
  await pool.end();
});
