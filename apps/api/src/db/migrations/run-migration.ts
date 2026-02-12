import { Pool } from 'pg';
import { readFileSync, readdirSync } from 'fs';
import { join } from 'path';
import { logger } from '../../utils/logger';
import { config } from '../../config';

const pool = new Pool({
  connectionString: config.database.url,
  ssl: config.database.ssl ? { rejectUnauthorized: false } : undefined,
});

async function ensureMigrationsTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      id SERIAL PRIMARY KEY,
      filename VARCHAR(255) NOT NULL UNIQUE,
      executed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
}

async function getExecutedMigrations(): Promise<Set<string>> {
  const result = await pool.query('SELECT filename FROM schema_migrations ORDER BY filename');
  return new Set(result.rows.map((r: { filename: string }) => r.filename));
}

async function runMigration(migrationFile: string) {
  const client = await pool.connect();

  try {
    logger.info(`Running migration: ${migrationFile}`);

    const sql = readFileSync(join(__dirname, migrationFile), 'utf-8');

    await client.query('BEGIN');
    await client.query(sql);
    await client.query(
      'INSERT INTO schema_migrations (filename) VALUES ($1)',
      [migrationFile]
    );
    await client.query('COMMIT');

    logger.info(`Migration ${migrationFile} completed successfully`);
  } catch (error) {
    await client.query('ROLLBACK');
    logger.error({ error, migrationFile }, `Migration ${migrationFile} failed`);
    throw error;
  } finally {
    client.release();
  }
}

async function main() {
  try {
    await ensureMigrationsTable();
    const executed = await getExecutedMigrations();

    // Discover all .sql migration files, sorted by name
    const files = readdirSync(__dirname)
      .filter((f) => f.endsWith('.sql'))
      .sort();

    let ranCount = 0;
    for (const file of files) {
      if (executed.has(file)) {
        logger.info(`Skipping already-executed migration: ${file}`);
        continue;
      }
      await runMigration(file);
      ranCount++;
    }

    if (ranCount === 0) {
      logger.info('No pending migrations');
    } else {
      logger.info(`${ranCount} migration(s) completed successfully`);
    }

    process.exit(0);
  } catch (error) {
    logger.error({ error }, 'Migration failed');
    process.exit(1);
  } finally {
    await pool.end();
  }
}

if (require.main === module) {
  main();
}

export { runMigration };
