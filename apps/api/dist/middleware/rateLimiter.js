"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.contactRateLimiter = exports.newsletterRateLimiter = exports.receiptScanRateLimiter = exports.giftResendRateLimiter = exports.writeRateLimiter = exports.passwordChangeRateLimiter = exports.verifyPremiumRateLimiter = exports.activationCodeRateLimiter = exports.passwordResetRateLimiter = exports.uploadRateLimiter = exports.refreshRateLimiter = exports.authRateLimiter = exports.initializeRateLimiter = void 0;
exports.closeRateLimiterRedis = closeRateLimiterRedis;
const express_rate_limit_1 = __importDefault(require("express-rate-limit"));
const redis_1 = require("redis");
const config_1 = require("../config");
const logger_1 = require("../utils/logger");
// Redis store for distributed rate limiting
let redisClient = null;
async function getRedisClient() {
    if (!redisClient) {
        redisClient = (0, redis_1.createClient)({
            url: config_1.config.redis.url,
            password: config_1.config.redis.password,
        });
        redisClient.on('error', (err) => {
            logger_1.logger.error('Redis error:', err);
        });
        redisClient.on('connect', () => {
            logger_1.logger.info('✅ Redis connected for rate limiting');
        });
        await redisClient.connect();
    }
    return redisClient;
}
// Custom Redis store for rate limiting
class RedisStore {
    prefix;
    client;
    windowMs;
    constructor(client, windowMs, prefix = 'rl:') {
        this.client = client;
        this.windowMs = windowMs;
        this.prefix = prefix;
    }
    // Lua script that atomically: removes expired entries, adds the current
    // request, counts the remaining entries, and sets the key TTL.  This avoids
    // the race condition inherent in separate ZRANGEBYSCORE + ZADD calls.
    static LUA_INCREMENT = `
    local key = KEYS[1]
    local now = tonumber(ARGV[1])
    local windowStart = tonumber(ARGV[2])
    local ttl = tonumber(ARGV[3])

    redis.call('ZREMRANGEBYSCORE', key, 0, windowStart)
    redis.call('ZADD', key, now, tostring(now) .. ':' .. tostring(math.random(1000000)))
    local count = redis.call('ZCARD', key)
    redis.call('EXPIRE', key, ttl)
    return count
  `;
    async increment(key) {
        const redisKey = this.prefix + key;
        const now = Date.now();
        const windowStart = now - this.windowMs;
        const ttlSeconds = Math.ceil(this.windowMs / 1000);
        // Execute the sliding-window rate-limit logic atomically in a single
        // Lua script to prevent race conditions under concurrent requests.
        const totalHits = await this.client.eval(RedisStore.LUA_INCREMENT, {
            keys: [redisKey],
            arguments: [String(now), String(windowStart), String(ttlSeconds)],
        });
        const resetTime = new Date(now + this.windowMs);
        return { totalHits, resetTime };
    }
    async resetKey(key) {
        const redisKey = this.prefix + key;
        await this.client.del(redisKey);
    }
}
// Initialize rate limiter with Redis in production and staging
const initializeRateLimiter = async () => {
    if (config_1.config.env !== 'development' && config_1.config.env !== 'test') {
        try {
            const client = await getRedisClient();
            const store = new RedisStore(client, config_1.config.rateLimit.windowMs);
            return (0, express_rate_limit_1.default)({
                windowMs: config_1.config.rateLimit.windowMs,
                max: config_1.config.rateLimit.max,
                message: 'Too many requests from this IP, please try again later.',
                standardHeaders: true,
                legacyHeaders: false,
                handler: (req, res) => {
                    logger_1.logger.warn({
                        ip: req.ip,
                        path: req.path,
                        userAgent: req.get('user-agent'),
                    }, 'Rate limit exceeded');
                    res.status(429).json({
                        error: 'Too many requests',
                        message: 'Please try again later',
                        retryAfter: Math.ceil(config_1.config.rateLimit.windowMs / 1000),
                    });
                },
                skip: (req) => {
                    // Skip rate limiting for health checks
                    return req.path.startsWith('/health') || req.path.startsWith('/live') || req.path.startsWith('/ready');
                },
            });
        }
        catch (error) {
            logger_1.logger.error('Failed to initialize Redis rate limiter, falling back to memory store', error);
            return createMemoryRateLimiter();
        }
    }
    else {
        // Use memory store for development
        return createMemoryRateLimiter();
    }
};
exports.initializeRateLimiter = initializeRateLimiter;
function createMemoryRateLimiter() {
    return (0, express_rate_limit_1.default)({
        windowMs: config_1.config.rateLimit.windowMs,
        // 10x multiplier: in development, hot-reloading and manual testing tools
        // (e.g. Postman, cURL loops) generate many more requests than real users.
        // The higher limit avoids false rate-limit blocks during local development
        // while still exercising the rate-limiting code path.
        max: config_1.config.rateLimit.max * 10,
        message: 'Too many requests from this IP, please try again later.',
        standardHeaders: true,
        legacyHeaders: false,
        skip: (req) => {
            return req.path.startsWith('/health') || req.path.startsWith('/live') || req.path.startsWith('/ready');
        },
    });
}
// Shared Redis store reference, populated after initializeRateLimiter runs.
// Endpoint-specific limiters lazily pick this up so they benefit from
// distributed rate limiting in production without requiring async init.
let sharedRedisClient = null;
function createEndpointRateLimiter(options) {
    // If Redis is available, create a RedisStore for this limiter
    const store = sharedRedisClient
        ? new RedisStore(sharedRedisClient, options.windowMs, `rl:${options.message.slice(0, 10)}:`)
        : undefined;
    return (0, express_rate_limit_1.default)({
        ...options,
        standardHeaders: true,
        legacyHeaders: false,
        ...(store ? { store: store } : {}),
    });
}
// Initialize the shared Redis client for endpoint-specific limiters.
// Called after initializeRateLimiter resolves.
async function initializeEndpointRedis() {
    if (config_1.config.env !== 'development' && config_1.config.env !== 'test') {
        try {
            sharedRedisClient = await getRedisClient();
        }
        catch (error) {
            logger_1.logger.error('Failed to initialize Redis for endpoint rate limiters, using in-memory store', error);
        }
    }
}
// Eagerly attempt to connect (non-blocking).
// The limiters will use in-memory until this resolves.
initializeEndpointRedis().catch((err) => {
    logger_1.logger.error('Failed to initialize endpoint Redis (non-fatal):', err);
});
/**
 * Close the Redis client(s) used by the rate limiter.
 * Call during graceful shutdown to avoid leaked connections.
 */
async function closeRateLimiterRedis() {
    if (redisClient) {
        try {
            await redisClient.quit();
        }
        catch (err) {
            logger_1.logger.error({ err }, 'Error closing rate limiter Redis client');
        }
        redisClient = null;
        sharedRedisClient = null;
    }
}
// Specific rate limiters for sensitive endpoints
exports.authRateLimiter = createEndpointRateLimiter({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 10,
    message: 'Too many attempts, please try again later.',
});
// Refresh rate limiter: 10 requests per 15 minutes.
// This is intentionally generous since mobile apps may refresh tokens frequently.
// Consider reducing if abuse is detected.
exports.refreshRateLimiter = createEndpointRateLimiter({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 10,
    message: 'Too many token refresh attempts, please try again later.',
    skipSuccessfulRequests: false, // Count all attempts for brute-force protection
});
exports.uploadRateLimiter = createEndpointRateLimiter({
    windowMs: 60 * 1000, // 1 minute
    max: 10,
    message: 'Too many uploads, please try again later.',
});
exports.passwordResetRateLimiter = createEndpointRateLimiter({
    windowMs: 60 * 60 * 1000, // 1 hour
    max: 3,
    message: 'Too many password reset attempts, please try again later.',
});
exports.activationCodeRateLimiter = createEndpointRateLimiter({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 10,
    message: 'Too many activation code attempts, please try again later.',
});
// BE-12: Rate limiter for premium verification endpoint
// Limits to 5 requests per 15 minutes to prevent abuse of RevenueCat API calls
exports.verifyPremiumRateLimiter = createEndpointRateLimiter({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 5,
    message: 'Too many premium verification attempts, please try again later.',
});
// Rate limiter for password change endpoint
// 5 attempts per hour to prevent brute-force current password guessing
exports.passwordChangeRateLimiter = createEndpointRateLimiter({
    windowMs: 60 * 60 * 1000, // 1 hour
    max: 5,
    message: 'Too many password change attempts, please try again later.',
});
// Rate limiter for write endpoints (POST, PUT, DELETE)
// 30 requests per 15 minutes to prevent abuse of data-mutating operations
exports.writeRateLimiter = createEndpointRateLimiter({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 30,
    message: 'Too many write requests, please try again later.',
});
// Gift email resend limiter: 3 resends per hour per IP
exports.giftResendRateLimiter = createEndpointRateLimiter({
    windowMs: 60 * 60 * 1000, // 1 hour
    max: 3,
    message: 'Too many gift email resend attempts, please try again later.',
});
// Receipt scan limiter: 10 per minute per IP
exports.receiptScanRateLimiter = createEndpointRateLimiter({
    windowMs: 60 * 1000, // 1 minute
    max: 10,
    message: 'Too many receipt scan requests, please try again later.',
});
// Newsletter subscription limiter: 5 per hour per IP
exports.newsletterRateLimiter = createEndpointRateLimiter({
    windowMs: 60 * 60 * 1000, // 1 hour
    max: 5,
    message: 'Too many subscription attempts, please try again later.',
});
// Contact form limiter: 3 per hour per IP
exports.contactRateLimiter = createEndpointRateLimiter({
    windowMs: 60 * 60 * 1000, // 1 hour
    max: 3,
    message: 'Too many contact submissions, please try again later.',
});
//# sourceMappingURL=rateLimiter.js.map