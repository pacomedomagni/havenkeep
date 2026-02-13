"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.blacklistToken = blacklistToken;
exports.isTokenBlacklisted = isTokenBlacklisted;
exports.blacklistUserTokens = blacklistUserTokens;
const redis_1 = require("redis");
const config_1 = require("../config");
const logger_1 = require("./logger");
let redisClient = null;
async function getClient() {
    if (!redisClient) {
        redisClient = (0, redis_1.createClient)({
            url: config_1.config.redis.url,
            password: config_1.config.redis.password,
        });
        redisClient.on('error', (err) => {
            logger_1.logger.error({ err }, 'Token blacklist Redis error');
        });
        await redisClient.connect();
    }
    return redisClient;
}
const BLACKLIST_PREFIX = 'token:blacklist:';
/**
 * Blacklist a JWT access token. The token will be rejected by authenticate()
 * until its natural expiration (TTL is set to token's remaining lifetime).
 */
async function blacklistToken(token, expiresInSeconds) {
    try {
        const client = await getClient();
        // Store with TTL matching the token's remaining lifetime so Redis auto-cleans
        const ttl = Math.max(expiresInSeconds, 1);
        await client.set(`${BLACKLIST_PREFIX}${token}`, '1', { EX: ttl });
    }
    catch (error) {
        logger_1.logger.error({ error }, 'Failed to blacklist token');
    }
}
/**
 * Check if a token has been blacklisted.
 */
async function isTokenBlacklisted(token) {
    try {
        const client = await getClient();
        const result = await client.get(`${BLACKLIST_PREFIX}${token}`);
        return result !== null;
    }
    catch (error) {
        // If Redis is down, fail-open in development, fail-closed in production
        logger_1.logger.error({ error }, 'Failed to check token blacklist');
        return config_1.config.env === 'production';
    }
}
/**
 * Blacklist all active tokens for a user by blacklisting the current token
 * and deleting all refresh tokens (forcing re-auth).
 */
async function blacklistUserTokens(token, tokenExp) {
    const now = Math.floor(Date.now() / 1000);
    const remainingSeconds = Math.max(tokenExp - now, 0);
    await blacklistToken(token, remainingSeconds);
}
//# sourceMappingURL=token-blacklist.js.map