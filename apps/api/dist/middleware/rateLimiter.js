"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.activationCodeRateLimiter = exports.passwordResetRateLimiter = exports.uploadRateLimiter = exports.refreshRateLimiter = exports.authRateLimiter = exports.initializeRateLimiter = void 0;
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
    async increment(key) {
        const redisKey = this.prefix + key;
        const now = Date.now();
        const windowStart = now - this.windowMs;
        // Remove old entries
        await this.client.zRemRangeByScore(redisKey, 0, windowStart);
        // Add current request
        await this.client.zAdd(redisKey, { score: now, value: String(now) });
        // Count requests in window
        const totalHits = await this.client.zCard(redisKey);
        // Set expiry
        await this.client.expire(redisKey, Math.ceil(this.windowMs / 1000));
        const resetTime = new Date(now + this.windowMs);
        return { totalHits, resetTime };
    }
    async decrement(key) {
        // Optional: implement if needed
    }
    async resetKey(key) {
        const redisKey = this.prefix + key;
        await this.client.del(redisKey);
    }
}
// Initialize rate limiter with Redis in production
const initializeRateLimiter = async () => {
    if (config_1.config.env === 'production') {
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
            logger_1.logger.error('Failed to initialize Redis rate limiter in production', error);
            throw new Error('Redis is required for rate limiting in production');
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
        max: config_1.config.rateLimit.max * 10, // More lenient in development
        message: 'Too many requests from this IP, please try again later.',
        standardHeaders: true,
        legacyHeaders: false,
        skip: (req) => {
            return req.path.startsWith('/health') || req.path.startsWith('/live') || req.path.startsWith('/ready');
        },
    });
}
// Specific rate limiters for sensitive endpoints
exports.authRateLimiter = (0, express_rate_limit_1.default)({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 5,
    message: 'Too many login attempts, please try again later.',
    skipSuccessfulRequests: true, // Don't count successful logins
});
exports.refreshRateLimiter = (0, express_rate_limit_1.default)({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 10,
    message: 'Too many token refresh attempts, please try again later.',
    skipSuccessfulRequests: false, // Count all attempts for brute-force protection
});
exports.uploadRateLimiter = (0, express_rate_limit_1.default)({
    windowMs: 60 * 1000, // 1 minute
    max: 10,
    message: 'Too many uploads, please try again later.',
});
exports.passwordResetRateLimiter = (0, express_rate_limit_1.default)({
    windowMs: 60 * 60 * 1000, // 1 hour
    max: 3,
    message: 'Too many password reset attempts, please try again later.',
});
exports.activationCodeRateLimiter = (0, express_rate_limit_1.default)({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 10,
    message: 'Too many activation code attempts, please try again later.',
});
//# sourceMappingURL=rateLimiter.js.map