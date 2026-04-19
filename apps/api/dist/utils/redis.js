"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getRedisClient = getRedisClient;
exports.closeRedisClient = closeRedisClient;
const redis_1 = require("redis");
const config_1 = require("../config");
const logger_1 = require("./logger");
let client = null;
let isReady = false;
/**
 * Returns the shared Redis client, creating and connecting it on first call.
 * All modules that need Redis should use this instead of creating their own client.
 */
async function getRedisClient() {
    if (client && isReady)
        return client;
    if (!client) {
        client = (0, redis_1.createClient)({
            url: config_1.config.redis.url,
            password: config_1.config.redis.password,
        });
        client.on('error', (err) => {
            logger_1.logger.error({ err }, 'Shared Redis client error');
            isReady = false;
        });
        client.on('ready', () => {
            isReady = true;
        });
        await client.connect();
        isReady = true;
        logger_1.logger.info('Shared Redis client connected');
    }
    return client;
}
/**
 * Gracefully close the shared Redis connection (for shutdown).
 */
async function closeRedisClient() {
    if (client) {
        await client.quit();
        client = null;
        isReady = false;
    }
}
//# sourceMappingURL=redis.js.map