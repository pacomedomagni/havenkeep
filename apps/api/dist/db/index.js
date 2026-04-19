"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.pool = void 0;
exports.query = query;
exports.getClient = getClient;
const pg_1 = require("pg");
const config_1 = require("../config");
const logger_1 = require("../utils/logger");
exports.pool = new pg_1.Pool({
    host: config_1.config.database.host,
    port: config_1.config.database.port,
    database: config_1.config.database.name,
    user: config_1.config.database.user,
    password: config_1.config.database.password,
    ssl: config_1.config.env === 'production'
        ? { rejectUnauthorized: true }
        : config_1.config.database.ssl
            ? { rejectUnauthorized: true }
            : false,
    max: parseInt(process.env.DB_POOL_MAX || '20', 10),
    idleTimeoutMillis: parseInt(process.env.DB_POOL_IDLE_TIMEOUT || '30000', 10),
    connectionTimeoutMillis: parseInt(process.env.DB_POOL_CONNECTION_TIMEOUT || '5000', 10),
    statement_timeout: parseInt(process.env.DB_STATEMENT_TIMEOUT || '30000', 10), // 30 seconds
});
exports.pool.on('connect', () => {
    logger_1.logger.info('✅ Database connected');
});
exports.pool.on('error', (err) => {
    // Log but do NOT exit — idle client errors are recoverable and the pool
    // will automatically replace the dead connection on the next checkout.
    logger_1.logger.error({ err }, 'Unexpected idle client error on database pool');
});
async function query(text, params) {
    const start = Date.now();
    try {
        const res = await exports.pool.query(text, params);
        const duration = Date.now() - start;
        // Log query text but never parameters (may contain sensitive data like emails, tokens)
        logger_1.logger.debug({ query: text.slice(0, 200), duration, rows: res.rowCount }, 'Query executed');
        return res;
    }
    catch (error) {
        logger_1.logger.error({ text, error }, 'Query error');
        throw error;
    }
}
async function getClient() {
    return exports.pool.connect();
}
//# sourceMappingURL=index.js.map