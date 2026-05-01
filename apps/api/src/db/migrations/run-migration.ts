import { Pool } from 'pg';
import { createHash } from 'crypto';
import { readFileSync, readdirSync } from 'fs';
import { join } from 'path';
import { logger } from '../../utils/logger';
import { config } from '../../config';

// Statements that must NOT be wrapped in BEGIN/COMMIT. Detection is line-prefix
// based — if any line of the file (ignoring leading whitespace and `--`
// comments) starts with one of these, the runner runs the file outside a
// transaction. The tradeoff: those files lose atomicity, so they must be
// idempotent (use IF EXISTS / IF NOT EXISTS / ON CONFLICT) to be safe to
// retry after a partial failure.
const NON_TXN_PATTERNS: RegExp[] = [
  /^\s*ALTER\s+TYPE\s+\w+\s+ADD\s+VALUE\b/i,                 // Ch00-DB002
  /^\s*CREATE\s+(UNIQUE\s+)?INDEX\s+CONCURRENTLY\b/i,        // Ch00-DB025
  /^\s*DROP\s+INDEX\s+CONCURRENTLY\b/i,
  /^\s*REINDEX\s+(TABLE|DATABASE|SCHEMA)\s+CONCURRENTLY\b/i,
];

const pool = new Pool({
  connectionString: config.database.url,
  ssl: config.database.ssl ? { rejectUnauthorized: false } : undefined,
});

function fileNeedsAutoCommit(sql: string): boolean {
  // Strip block comments first so a SQL keyword inside /* ... */ doesn't trip
  // detection.
  const stripped = sql.replace(/\/\*[\s\S]*?\*\//g, '');
  return NON_TXN_PATTERNS.some((re) => re.test(stripped));
}

async function ensureMigrationsTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      id SERIAL PRIMARY KEY,
      filename VARCHAR(255) NOT NULL UNIQUE,
      sha256 CHAR(64),
      executed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  // Backfill the sha256 column on existing installations.
  await pool.query(`
    ALTER TABLE schema_migrations
      ADD COLUMN IF NOT EXISTS sha256 CHAR(64)
  `);
}

/**
 * The base schema.sql runs on a brand-new DB. Migration 045 introduced
 * `schema_version` as the canonical "is the base done?" marker — that's
 * the *only* signal we trust now. The previous `users + items + partners`
 * table-presence fallback (S3-F) raced a partial bootstrap: a crash mid
 * schema.sql could leave those three tables present without the rest of
 * the dependency tree, and the runner would skip schema.sql forever.
 *
 * schema.sql is now fully idempotent (every CREATE has IF NOT EXISTS and
 * triggers/types are wrapped in DO blocks), so re-running it on an already-
 * bootstrapped DB is a safe no-op. That means: when schema_version is
 * missing OR doesn't carry the 'base' row, replay schema.sql.
 */
async function ensureBaseSchema() {
  const versionTable = await pool.query(
    `SELECT to_regclass('public.schema_version') AS v`,
  );
  if (versionTable.rows[0]?.v) {
    const baseRow = await pool.query(
      `SELECT 1 FROM schema_version WHERE phase = 'base' LIMIT 1`,
    );
    if (baseRow.rows.length > 0) return;
  }

  const schemaSql = readFileSync(join(__dirname, '..', 'schema.sql'), 'utf-8');
  logger.info('Applying base schema.sql (schema_version row absent or missing base phase)');
  await pool.query(schemaSql);
}

async function getExecutedMigrations(): Promise<Map<string, string | null>> {
  const result = await pool.query<{ filename: string; sha256: string | null }>(
    'SELECT filename, sha256 FROM schema_migrations ORDER BY filename',
  );
  const map = new Map<string, string | null>();
  for (const row of result.rows) map.set(row.filename, row.sha256);
  return map;
}

async function runMigration(migrationFile: string) {
  const sql = readFileSync(join(__dirname, migrationFile), 'utf-8');
  const sha = createHash('sha256').update(sql).digest('hex');
  const skipTxn = fileNeedsAutoCommit(sql);

  const client = await pool.connect();
  try {
    logger.info({ file: migrationFile, autoCommit: skipTxn }, 'Running migration');

    if (skipTxn) {
      // Each statement runs in its own implicit transaction. Files in this
      // mode MUST be idempotent (IF NOT EXISTS, ON CONFLICT, DROP IF EXISTS)
      // because a mid-file failure leaves partial state.
      await client.query(sql);
      await client.query(
        `INSERT INTO schema_migrations (filename, sha256) VALUES ($1, $2)
           ON CONFLICT (filename) DO UPDATE SET sha256 = EXCLUDED.sha256`,
        [migrationFile, sha],
      );
    } else {
      await client.query('BEGIN');
      await client.query(sql);
      await client.query(
        `INSERT INTO schema_migrations (filename, sha256) VALUES ($1, $2)`,
        [migrationFile, sha],
      );
      await client.query('COMMIT');
    }

    logger.info({ file: migrationFile }, 'Migration completed');
  } catch (error) {
    if (!skipTxn) {
      await client.query('ROLLBACK').catch(() => {});
    }
    logger.error({ err: error, file: migrationFile }, 'Migration failed');
    throw error;
  } finally {
    client.release();
  }
}

async function runAnalyzeAfterSeed(file: string): Promise<void> {
  // Ch00-DB054: seeds inflate stats; ANALYZE the touched tables so the
  // planner's row estimates aren't stuck at zero. We pick targets by name
  // convention — files containing 'seed' analyze every table they touch
  // (cheap; ANALYZE is non-blocking).
  if (!/seed/i.test(file)) return;
  try {
    await pool.query('ANALYZE');
    logger.info({ file }, 'ANALYZE completed after seed migration');
  } catch (err) {
    logger.warn({ err, file }, 'ANALYZE after seed failed (non-fatal)');
  }
}

// H-D1 (audit): session-scoped advisory lock so two replicas booting
// simultaneously can't both try to apply the same migrations. Most
// migrations aren't idempotent (ALTER TABLE ... ALTER COLUMN ... TYPE,
// INSERT ... UPDATE) — the second replica's INSERT INTO
// schema_migrations would 23505 only AFTER both had executed the DDL.
// On a CONCURRENTLY index that fails mid-run, the second replica
// crash-loops with `relation already exists`.
//
// Lock key: arbitrary 32-bit constant scoped to the migration runner.
// Distinct from the audit-chain advisory lock (mig 080: 687638440097),
// the account-purge lock (account-purge.service.ts: 0xa00d_4a13), and
// the cap-refresh-tokens lock. Document new keys in a registry comment
// when adding more.
const MIGRATION_LOCK_KEY = 0x4d_47_52_4e; // 'MGRN' as bytes

async function withMigrationLock<T>(fn: () => Promise<T>): Promise<T> {
  const lockClient = await pool.connect();
  try {
    // Blocking lock — the second replica waits until the first finishes.
    // We don't use try_advisory_lock here because we want the second
    // replica to PROCEED (and skip already-applied migrations as no-ops)
    // rather than exit and let k8s restart-loop it.
    await lockClient.query(`SELECT pg_advisory_lock($1)`, [MIGRATION_LOCK_KEY]);
    try {
      return await fn();
    } finally {
      // Best-effort release; the session-scoped lock is also dropped
      // automatically when the connection goes back to the pool.
      await lockClient
        .query(`SELECT pg_advisory_unlock($1)`, [MIGRATION_LOCK_KEY])
        .catch(() => {});
    }
  } finally {
    lockClient.release();
  }
}

async function main() {
  try {
    await withMigrationLock(async () => {
      await ensureBaseSchema();
      await ensureMigrationsTable();
      const executed = await getExecutedMigrations();

      const files = readdirSync(__dirname)
        .filter((f) => f.endsWith('.sql'))
        .sort();

      let ran = 0;
      for (const file of files) {
        if (executed.has(file)) {
          // Drift detection: if the file's content has changed since it was
          // recorded, surface a warning. We never re-run because that would
          // double-apply (most migrations aren't idempotent).
          const sha = createHash('sha256')
            .update(readFileSync(join(__dirname, file), 'utf-8'))
            .digest('hex');
          const recordedSha = executed.get(file);
          if (recordedSha && recordedSha !== sha) {
            logger.warn(
              { file, recorded: recordedSha.slice(0, 12), current: sha.slice(0, 12) },
              'Migration file SHA differs from schema_migrations record — manual reconciliation may be needed',
            );
          }
          logger.info({ file }, 'Skipping already-executed migration');
          continue;
        }
        await runMigration(file);
        await runAnalyzeAfterSeed(file);
        ran++;
      }

      logger.info({ ran }, ran === 0 ? 'No pending migrations' : 'Migrations completed');
    });
    process.exit(0);
  } catch (error) {
    logger.error({ err: error }, 'Migration failed');
    process.exit(1);
  } finally {
    await pool.end();
  }
}

if (require.main === module) {
  main();
}

export { runMigration, fileNeedsAutoCommit };
