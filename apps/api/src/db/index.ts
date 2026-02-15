import { Pool, QueryResult, QueryResultRow } from 'pg';
import { config } from '../config';
import { logger } from '../utils/logger';

export const pool = new Pool({
  host: config.database.host,
  port: config.database.port,
  database: config.database.name,
  user: config.database.user,
  password: config.database.password,
  ssl: config.database.ssl ? { rejectUnauthorized: true } : false,
  max: parseInt(process.env.DB_POOL_MAX || '20', 10),
  idleTimeoutMillis: parseInt(process.env.DB_POOL_IDLE_TIMEOUT || '30000', 10),
  connectionTimeoutMillis: parseInt(process.env.DB_POOL_CONNECTION_TIMEOUT || '5000', 10),
});

pool.on('connect', () => {
  logger.info('✅ Database connected');
});

pool.on('error', (err) => {
  // Log but do NOT exit — idle client errors are recoverable and the pool
  // will automatically replace the dead connection on the next checkout.
  logger.error({ err }, 'Unexpected idle client error on database pool');
});

export async function query<T extends QueryResultRow = any>(
  text: string,
  params?: any[]
): Promise<QueryResult<T>> {
  const start = Date.now();
  try {
    const res = await pool.query<T>(text, params);
    const duration = Date.now() - start;
    // Log query text but never parameters (may contain sensitive data like emails, tokens)
    logger.debug({ query: text.slice(0, 200), duration, rows: res.rowCount }, 'Query executed');
    return res;
  } catch (error) {
    logger.error({ text, error }, 'Query error');
    throw error;
  }
}

export async function getClient() {
  return pool.connect();
}
