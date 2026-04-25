import { createClient } from 'redis';
import { config } from '../config';
import { logger } from './logger';

export type RedisClient = ReturnType<typeof createClient>;

let client: RedisClient | null = null;
let connectingPromise: Promise<RedisClient> | null = null;
let pingTimer: NodeJS.Timeout | null = null;

const PING_INTERVAL_MS = 30_000;

/**
 * Returns the shared Redis client, creating + connecting it on first call.
 * All modules that need Redis MUST use this — the audit caught a separate
 * client in token-blacklist.ts that diverged from the main client's state
 * (Ch11-I060/I061/I062).
 *
 * The `connectingPromise` cache serializes concurrent first-callers so two
 * requests hitting Redis at the exact same moment as boot don't each open a
 * fresh connection (Ch11-I061).
 */
export async function getRedisClient(): Promise<RedisClient> {
  if (client?.isReady) return client;
  if (connectingPromise) return connectingPromise;

  connectingPromise = (async () => {
    const c = createClient({
      url: config.redis.url,
      password: config.redis.password,
      socket: {
        // Bound reconnect attempts so a permanently-down Redis doesn't
        // chew CPU forever. After max retries the client emits an error
        // and stays disconnected; getRedisClient() callers see that as a
        // failed connect on the next attempt.
        reconnectStrategy: (retries) => {
          if (retries > 10) return new Error('Redis: max reconnect attempts');
          return Math.min(1000 * Math.pow(2, retries), 15_000);
        },
      },
    });

    c.on('error', (err) => {
      logger.error({ err }, 'Shared Redis client error');
    });

    c.on('reconnecting', () => {
      logger.warn('Shared Redis client reconnecting');
    });

    c.on('ready', async () => {
      // Ch11-I063: ping after each reconnect so we surface a half-open
      // connection (some proxies hold the TCP open while Redis itself
      // is unresponsive).
      try {
        await c.ping();
        logger.info('Shared Redis client ready (ping ok)');
      } catch (err) {
        logger.error({ err }, 'Shared Redis ready event but ping failed');
      }
    });

    await c.connect();
    client = c;
    startPingTimer();
    return c;
  })();

  try {
    return await connectingPromise;
  } finally {
    connectingPromise = null;
  }
}

function startPingTimer() {
  if (pingTimer) return;
  pingTimer = setInterval(async () => {
    if (!client?.isReady) return;
    try {
      await client.ping();
    } catch (err) {
      logger.warn({ err }, 'Shared Redis ping failed');
    }
  }, PING_INTERVAL_MS);
  // Don't keep the process alive just for the ping timer.
  pingTimer.unref();
}

/**
 * Gracefully close the shared Redis connection (for shutdown).
 * Removes all listeners so a delayed reconnect event doesn't fire after we've
 * closed the socket (Ch11-I065).
 */
export async function closeRedisClient(): Promise<void> {
  if (pingTimer) {
    clearInterval(pingTimer);
    pingTimer = null;
  }
  if (client) {
    client.removeAllListeners();
    try {
      if (client.isOpen) await client.quit();
    } catch (err) {
      logger.warn({ err }, 'Error during Redis quit');
    }
    client = null;
  }
}
