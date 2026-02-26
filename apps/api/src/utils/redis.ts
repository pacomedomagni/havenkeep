import { createClient } from 'redis';
import { config } from '../config';
import { logger } from './logger';

export type RedisClient = ReturnType<typeof createClient>;

let client: RedisClient | null = null;
let isReady = false;

/**
 * Returns the shared Redis client, creating and connecting it on first call.
 * All modules that need Redis should use this instead of creating their own client.
 */
export async function getRedisClient(): Promise<RedisClient> {
  if (client && isReady) return client;

  if (!client) {
    client = createClient({
      url: config.redis.url,
      password: config.redis.password,
    });

    client.on('error', (err) => {
      logger.error({ err }, 'Shared Redis client error');
      isReady = false;
    });

    client.on('ready', () => {
      isReady = true;
    });

    await client.connect();
    isReady = true;
    logger.info('Shared Redis client connected');
  }

  return client;
}

/**
 * Gracefully close the shared Redis connection (for shutdown).
 */
export async function closeRedisClient(): Promise<void> {
  if (client) {
    await client.quit();
    client = null;
    isReady = false;
  }
}
