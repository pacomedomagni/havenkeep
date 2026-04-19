"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.initializeTokenBlacklist = initializeTokenBlacklist;
exports.blacklistTokenAuto = blacklistTokenAuto;
exports.isTokenBlacklisted = isTokenBlacklisted;
exports.closeTokenBlacklist = closeTokenBlacklist;
const redis_1 = require("redis");
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const config_1 = require("../config");
const logger_1 = require("./logger");
let redisClient = null;
let redisReady = false;
// Circuit breaker state: after CIRCUIT_BREAKER_THRESHOLD consecutive Redis
// failures, we stop calling Redis for CIRCUIT_BREAKER_RESET_MS and allow
// requests through (fail-open) to avoid cascading latency.  After the
// cooldown we retry Redis; a single success resets the counter.
const CIRCUIT_BREAKER_THRESHOLD = 5;
const CIRCUIT_BREAKER_RESET_MS = 60_000; // 60 seconds
let consecutiveFailures = 0;
let circuitOpenUntil = 0; // timestamp (ms) when the circuit should close again
/**
 * Eagerly initialize the Redis connection at startup.
 * Call this from the server bootstrap so connection issues surface immediately.
 */
async function initializeTokenBlacklist() {
    if (redisClient)
        return;
    redisClient = (0, redis_1.createClient)({
        url: config_1.config.redis.url,
        password: config_1.config.redis.password,
    });
    redisClient.on('error', (err) => {
        logger_1.logger.error({ err }, 'Token blacklist Redis error');
        redisReady = false;
    });
    redisClient.on('ready', () => {
        redisReady = true;
    });
    await redisClient.connect();
    redisReady = true;
    logger_1.logger.info('Token blacklist Redis connected');
}
async function getClient() {
    if (!redisClient) {
        await initializeTokenBlacklist();
    }
    return redisClient;
}
const BLACKLIST_PREFIX = 'token:blacklist:';
/**
 * Calculate the remaining TTL (in seconds) for a JWT access token.
 * Returns 0 if the token is already expired or cannot be decoded.
 */
function getTokenRemainingTtl(token) {
    try {
        const decoded = jsonwebtoken_1.default.decode(token);
        if (!decoded?.exp)
            return 0;
        const remaining = decoded.exp - Math.floor(Date.now() / 1000);
        return Math.max(remaining, 0);
    }
    catch {
        return 0;
    }
}
/**
 * Blacklist a token using its embedded exp claim to calculate TTL.
 * The token will be rejected by authenticate() until its natural expiration.
 *
 * Throws on failure so callers can decide how to handle it.
 */
async function blacklistTokenAuto(token) {
    const ttl = getTokenRemainingTtl(token);
    if (ttl <= 0)
        return; // Already expired, no need to blacklist
    const client = await getClient();
    await client.set(`${BLACKLIST_PREFIX}${token}`, '1', { EX: ttl });
}
/**
 * Check if a token has been blacklisted.
 *
 * Includes a circuit breaker: after {@link CIRCUIT_BREAKER_THRESHOLD}
 * consecutive Redis failures the circuit opens for
 * {@link CIRCUIT_BREAKER_RESET_MS} ms.  While open, requests are allowed
 * through (fail-open) and a critical warning is logged.  After the cooldown
 * period a single Redis call is attempted; on success the circuit closes.
 */
async function isTokenBlacklisted(token) {
    // If the circuit is open, allow requests through until the cooldown expires
    if (consecutiveFailures >= CIRCUIT_BREAKER_THRESHOLD) {
        if (Date.now() < circuitOpenUntil) {
            // Circuit is still open — skip Redis entirely
            return false;
        }
        // Cooldown expired — attempt a single Redis call to see if it recovered
        logger_1.logger.info('Token blacklist circuit breaker cooldown expired, retrying Redis');
    }
    try {
        const client = await getClient();
        const result = await client.get(`${BLACKLIST_PREFIX}${token}`);
        // Success — reset the circuit breaker
        if (consecutiveFailures > 0) {
            logger_1.logger.info('Token blacklist Redis recovered, resetting circuit breaker');
        }
        consecutiveFailures = 0;
        circuitOpenUntil = 0;
        return result !== null;
    }
    catch (error) {
        consecutiveFailures++;
        logger_1.logger.error({ error, consecutiveFailures }, 'Failed to check token blacklist');
        if (consecutiveFailures >= CIRCUIT_BREAKER_THRESHOLD) {
            circuitOpenUntil = Date.now() + CIRCUIT_BREAKER_RESET_MS;
            logger_1.logger.fatal({ consecutiveFailures, circuitOpenUntilISO: new Date(circuitOpenUntil).toISOString() }, 'CRITICAL: Token blacklist circuit breaker OPEN — allowing all requests through for 60s');
        }
        // Fail-open in development, fail-closed in production (unless circuit is open)
        if (config_1.config.env !== 'production') {
            logger_1.logger.warn('Token blacklist check failed — fail-open in development (token accepted)');
            return false;
        }
        // In production, if the circuit just opened, fail-open
        if (consecutiveFailures >= CIRCUIT_BREAKER_THRESHOLD) {
            return false;
        }
        return true;
    }
}
/**
 * Gracefully close the Redis connection (for shutdown).
 */
async function closeTokenBlacklist() {
    if (redisClient) {
        await redisClient.quit();
        redisClient = null;
        redisReady = false;
    }
}
//# sourceMappingURL=token-blacklist.js.map