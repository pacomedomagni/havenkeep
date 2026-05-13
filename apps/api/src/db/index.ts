import { Pool, PoolClient, QueryResult, QueryResultRow, types } from 'pg';
import { readFileSync } from 'fs';
import { config } from '../config';
import { logger } from '../utils/logger';

// C9: parse NUMERIC/DECIMAL (OID 1700) as JS number. node-postgres returns
// these as strings by default to preserve precision; mobile models cast
// `as num?` and crash on hydration (partner gifts, warranty purchases /
// claims, maintenance history). Every money column
// in this codebase is DECIMAL(10,2) where float64 is exact for two-
// decimal-place values up to ~9 trillion. If a future column needs more
// precision than float64 (loss-of-precision around 2^53 ≈ 9e15), pin
// that column's parser separately to a Decimal lib.
types.setTypeParser(1700, (val) => (val === null ? null : parseFloat(val)));

// ── Knobs (tunable via env, NaN-guarded) ──────────────────────────────────
function intFromEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw.trim() === '') return fallback;
  const n = parseInt(raw, 10);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}

const POOL_MAX = intFromEnv('DB_POOL_MAX', 20);
const POOL_IDLE_MS = intFromEnv('DB_POOL_IDLE_TIMEOUT', 30_000);
const POOL_CONNECT_MS = intFromEnv('DB_POOL_CONNECTION_TIMEOUT', 5_000);
const STATEMENT_TIMEOUT_MS = intFromEnv('DB_STATEMENT_TIMEOUT', 30_000);
// Idle-in-transaction timeout — a forgotten BEGIN that holds locks for
// minutes is the most common production stall. (Ch11-I037)
const IDLE_IN_TX_MS = intFromEnv('DB_IDLE_IN_TRANSACTION_TIMEOUT', 60_000);
// Queries slower than this get a warn-level log so we can find pathologies
// in development without paying for tracing in prod. (Ch11-I039)
const SLOW_QUERY_MS = intFromEnv('DB_SLOW_QUERY_THRESHOLD', 250);
// Active client leak detector — if a checked-out client isn't released in
// this window, log a warning so we can find getClient-without-release
// callers. (Ch11-I040)
const CLIENT_LEAK_MS = intFromEnv('DB_CLIENT_LEAK_THRESHOLD', 10_000);

// ── SSL configuration ────────────────────────────────────────────────────
// (Ch11-I036) Production: rejectUnauthorized:true PLUS a CA file when
// DB_SSL_CA_FILE is set, so we actually verify the issuer.
function buildSslConfig() {
  if (config.database.ssl) {
    const caPath = process.env.DB_SSL_CA_FILE;
    if (caPath) {
      try {
        return { rejectUnauthorized: true, ca: readFileSync(caPath, 'utf8') };
      } catch (err) {
        logger.error({ err, caPath }, 'Failed to read DB_SSL_CA_FILE');
        throw err;
      }
    }
    return { rejectUnauthorized: true };
  }
  return false;
}

// (Ch11-I042) An empty DB password is never correct — bail loudly instead of
// silently connecting to a misconfigured DB.
if (!config.database.password && config.env !== 'test') {
  throw new Error('DB password is empty (set DB_PASSWORD or POSTGRES_PASSWORD)');
}

export const pool = new Pool({
  host: config.database.host,
  port: config.database.port,
  database: config.database.name,
  user: config.database.user,
  password: config.database.password,
  ssl: buildSslConfig(),
  max: POOL_MAX,
  idleTimeoutMillis: POOL_IDLE_MS,
  connectionTimeoutMillis: POOL_CONNECT_MS,
  statement_timeout: STATEMENT_TIMEOUT_MS,
});

let poolHealthy = false;

pool.on('connect', async (client) => {
  // Apply per-connection guards. SET LOCAL would only last the txn; SET
  // (session) survives subsequent queries on the connection.
  try {
    await client.query(`SET idle_in_transaction_session_timeout = ${IDLE_IN_TX_MS}`);
  } catch (err) {
    logger.warn({ err }, 'Failed to SET idle_in_transaction_session_timeout on new connection');
  }
  poolHealthy = true;
  logger.info('✅ Database connected');
});

pool.on('error', (err) => {
  // (Ch11-I041) Mark the pool unhealthy so /health endpoints reflect the
  // problem, even though pg-pool itself will replace the dead client on the
  // next checkout.
  poolHealthy = false;
  logger.error({ err }, 'Unexpected idle client error on database pool');
});

/**
 * Probe the pool with a trivial query and return whether it succeeded.
 * Used by `start()` to wait for DB readiness before binding the HTTP port
 * (Ch11-I088), and by /health to surface a degraded signal.
 */
export async function isDatabaseReady(): Promise<boolean> {
  try {
    await pool.query('SELECT 1');
    poolHealthy = true;
    return true;
  } catch (err) {
    poolHealthy = false;
    logger.error({ err }, 'Database readiness probe failed');
    return false;
  }
}

export function isPoolHealthy(): boolean {
  return poolHealthy;
}

export async function query<T extends QueryResultRow = any>(
  text: string,
  params?: any[],
): Promise<QueryResult<T>> {
  const start = Date.now();
  try {
    const res = await pool.query<T>(text, params);
    const duration = Date.now() - start;
    if (duration >= SLOW_QUERY_MS) {
      // Slow-query warn includes only the first 200 chars of the SQL — never
      // params (audit Ch11-I038: error path used to log full SQL with params).
      logger.warn(
        { sql: text.slice(0, 200), durationMs: duration, rows: res.rowCount },
        'Slow query',
      );
    } else {
      logger.debug({ durationMs: duration, rows: res.rowCount }, 'Query executed');
    }
    return res;
  } catch (error) {
    // (Ch11-I038) Truncate SQL and never log params; the SQL alone is enough
    // to triage and the params can carry tokens / emails / passwords.
    logger.error({ sql: text.slice(0, 200), error }, 'Query error');
    throw error;
  }
}

/**
 * Checkout helper with a leak watchdog. The returned client must be released
 * by the caller; if it isn't released within CLIENT_LEAK_MS we log a warning
 * so the offender can be found before it exhausts the pool.
 */
export async function getClient(): Promise<PoolClient> {
  const client = await pool.connect();
  const stack = new Error('client leak watchdog stack').stack;
  const leakTimer = setTimeout(() => {
    logger.warn(
      { thresholdMs: CLIENT_LEAK_MS, callsite: stack?.split('\n').slice(2, 8).join('\n') },
      'DB client checked out but not released — possible leak',
    );
  }, CLIENT_LEAK_MS);

  // Wrap release so the watchdog clears regardless of release path.
  const originalRelease = client.release.bind(client);
  (client as any).release = (err?: Error | boolean) => {
    clearTimeout(leakTimer);
    return originalRelease(err as any);
  };
  return client;
}
