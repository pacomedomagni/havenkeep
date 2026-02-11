import { Pool } from 'pg';
import { readFileSync } from 'fs';
import { join } from 'path';
import { logger } from '../../utils/logger';
import { config } from '../../config';

const pool = new Pool({
  connectionString: config.database.url,
  ssl: config.database.ssl ? { rejectUnauthorized: false } : undefined,
});

async function runMigration(migrationFile: string) {
  const client = await pool.connect();

  try {
    logger.info(`Running migration: ${migrationFile}`);

    // Read migration file
    const sql = readFileSync(join(__dirname, migrationFile), 'utf-8');

    // Begin transaction
    await client.query('BEGIN');

    // Execute migration
    await client.query(sql);

    // Commit transaction
    await client.query('COMMIT');

    logger.info(`✅ Migration ${migrationFile} completed successfully`);
  } catch (error) {
    // Rollback on error
    await client.query('ROLLBACK');
    logger.error({ error, migrationFile }, `❌ Migration ${migrationFile} failed`);
    throw error;
  } finally {
    client.release();
  }
}

async function main() {
  try {
    // Run migrations in order
    await runMigration('002_enhanced_features.sql');

    logger.info('🎉 All migrations completed successfully');
    process.exit(0);
  } catch (error) {
    logger.error({ error }, 'Migration failed');
    process.exit(1);
  } finally {
    await pool.end();
  }
}

// Run if called directly
if (require.main === module) {
  main();
}

export { runMigration };
