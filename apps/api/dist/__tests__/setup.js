"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.cleanDatabase = cleanDatabase;
const path_1 = __importDefault(require("path"));
const dotenv_1 = __importDefault(require("dotenv"));
// Load .env from project root BEFORE any app code imports
dotenv_1.default.config({ path: path_1.default.join(__dirname, '../../../../.env') });
// Override env vars for test
process.env.NODE_ENV = 'test';
// Point to Docker postgres on localhost (not internal 'postgres' hostname)
process.env.DB_HOST = 'localhost';
process.env.DATABASE_URL = `postgresql://${process.env.DB_USER}:${process.env.DB_PASSWORD}@localhost:${process.env.DB_PORT}/${process.env.DB_NAME}`;
// Point to Docker redis on localhost
process.env.REDIS_URL = 'redis://localhost:6379';
// Point to Docker minio on localhost
process.env.MINIO_ENDPOINT = 'localhost';
const db_1 = require("../db");
const redis_1 = require("redis");
// Flush rate limiter keys in Redis between tests
let redisClient = null;
async function getTestRedis() {
    if (!redisClient) {
        redisClient = (0, redis_1.createClient)({ url: process.env.REDIS_URL });
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
    'audit_logs',
    'user_push_tokens',
    'email_verification_tokens',
    'password_reset_tokens',
    'refresh_tokens',
    'warranty_claims',
    'warranty_purchases',
    'maintenance_history',
    'notification_history',
    'documents',
    'items',
    'homes',
    'partner_commissions',
    'partner_gifts',
    'partners',
    'newsletter_subscribers',
    'contact_submissions',
    'user_analytics',
    'users',
];
async function cleanDatabase() {
    await db_1.pool.query(`TRUNCATE ${TABLES.join(', ')} CASCADE`);
    await flushRedis();
}
afterAll(async () => {
    if (redisClient) {
        await redisClient.quit();
    }
    await db_1.pool.end();
});
//# sourceMappingURL=setup.js.map