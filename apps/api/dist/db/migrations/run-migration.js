"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.runMigration = runMigration;
const pg_1 = require("pg");
const fs_1 = require("fs");
const path_1 = require("path");
const logger_1 = require("../../utils/logger");
const config_1 = require("../../config");
const pool = new pg_1.Pool({
    connectionString: config_1.config.database.url,
    ssl: config_1.config.database.ssl ? { rejectUnauthorized: false } : undefined,
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
async function ensureBaseSchema() {
    const result = await pool.query(`SELECT to_regclass('public.users') AS users_table`);
    if (result.rows[0]?.users_table) {
        return;
    }
    const schemaSql = (0, fs_1.readFileSync)((0, path_1.join)(__dirname, '..', 'schema.sql'), 'utf-8');
    logger_1.logger.info('Applying base schema.sql before running migrations');
    await pool.query(schemaSql);
}
async function getExecutedMigrations() {
    const result = await pool.query('SELECT filename FROM schema_migrations ORDER BY filename');
    return new Set(result.rows.map((r) => r.filename));
}
async function runMigration(migrationFile) {
    const client = await pool.connect();
    try {
        logger_1.logger.info(`Running migration: ${migrationFile}`);
        const sql = (0, fs_1.readFileSync)((0, path_1.join)(__dirname, migrationFile), 'utf-8');
        await client.query('BEGIN');
        await client.query(sql);
        await client.query('INSERT INTO schema_migrations (filename) VALUES ($1)', [migrationFile]);
        await client.query('COMMIT');
        logger_1.logger.info(`Migration ${migrationFile} completed successfully`);
    }
    catch (error) {
        await client.query('ROLLBACK');
        logger_1.logger.error({ error, migrationFile }, `Migration ${migrationFile} failed`);
        throw error;
    }
    finally {
        client.release();
    }
}
async function main() {
    try {
        await ensureBaseSchema();
        await ensureMigrationsTable();
        const executed = await getExecutedMigrations();
        // Discover all .sql migration files, sorted by name
        const files = (0, fs_1.readdirSync)(__dirname)
            .filter((f) => f.endsWith('.sql'))
            .sort();
        let ranCount = 0;
        for (const file of files) {
            if (executed.has(file)) {
                logger_1.logger.info(`Skipping already-executed migration: ${file}`);
                continue;
            }
            await runMigration(file);
            ranCount++;
        }
        if (ranCount === 0) {
            logger_1.logger.info('No pending migrations');
        }
        else {
            logger_1.logger.info(`${ranCount} migration(s) completed successfully`);
        }
        process.exit(0);
    }
    catch (error) {
        logger_1.logger.error({ error }, 'Migration failed');
        process.exit(1);
    }
    finally {
        await pool.end();
    }
}
if (require.main === module) {
    main();
}
//# sourceMappingURL=run-migration.js.map