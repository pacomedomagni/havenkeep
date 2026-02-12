import { createClient } from 'redis';
import { config } from '../config';
import { logger } from './logger';

let redisClient: ReturnType<typeof createClient> | null = null;

async function getClient(): Promise<ReturnType<typeof createClient>> {
  if (!redisClient) {
    redisClient = createClient({
      url: config.redis.url,
      password: config.redis.password,
    });

    redisClient.on('error', (err) => {
      logger.error({ err }, 'Token blacklist Redis error');
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
export async function blacklistToken(token: string, expiresInSeconds: number): Promise<void> {
  try {
    const client = await getClient();
    // Store with TTL matching the token's remaining lifetime so Redis auto-cleans
    const ttl = Math.max(expiresInSeconds, 1);
    await client.set(`${BLACKLIST_PREFIX}${token}`, '1', { EX: ttl });
  } catch (error) {
    logger.error({ error }, 'Failed to blacklist token');
  }
}

/**
 * Check if a token has been blacklisted.
 */
export async function isTokenBlacklisted(token: string): Promise<boolean> {
  try {
    const client = await getClient();
    const result = await client.get(`${BLACKLIST_PREFIX}${token}`);
    return result !== null;
  } catch (error) {
    // If Redis is down, fail-open in development, fail-closed in production
    logger.error({ error }, 'Failed to check token blacklist');
    return config.env === 'production';
  }
}

/**
 * Blacklist all active tokens for a user by blacklisting the current token
 * and deleting all refresh tokens (forcing re-auth).
 */
export async function blacklistUserTokens(token: string, tokenExp: number): Promise<void> {
  const now = Math.floor(Date.now() / 1000);
  const remainingSeconds = Math.max(tokenExp - now, 0);
  await blacklistToken(token, remainingSeconds);
}
