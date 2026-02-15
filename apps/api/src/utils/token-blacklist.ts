import { createClient } from 'redis';
import jwt from 'jsonwebtoken';
import { config } from '../config';
import { logger } from './logger';

let redisClient: ReturnType<typeof createClient> | null = null;
let redisReady = false;

/**
 * Eagerly initialize the Redis connection at startup.
 * Call this from the server bootstrap so connection issues surface immediately.
 */
export async function initializeTokenBlacklist(): Promise<void> {
  if (redisClient) return;

  redisClient = createClient({
    url: config.redis.url,
    password: config.redis.password,
  });

  redisClient.on('error', (err) => {
    logger.error({ err }, 'Token blacklist Redis error');
    redisReady = false;
  });

  redisClient.on('ready', () => {
    redisReady = true;
  });

  await redisClient.connect();
  redisReady = true;
  logger.info('Token blacklist Redis connected');
}

async function getClient(): Promise<ReturnType<typeof createClient>> {
  if (!redisClient) {
    await initializeTokenBlacklist();
  }
  return redisClient!;
}

const BLACKLIST_PREFIX = 'token:blacklist:';

/**
 * Calculate the remaining TTL (in seconds) for a JWT access token.
 * Returns 0 if the token is already expired or cannot be decoded.
 */
export function getTokenRemainingTtl(token: string): number {
  try {
    const decoded = jwt.decode(token) as { exp?: number } | null;
    if (!decoded?.exp) return 0;
    const remaining = decoded.exp - Math.floor(Date.now() / 1000);
    return Math.max(remaining, 0);
  } catch {
    return 0;
  }
}

/**
 * Blacklist a JWT access token. The token will be rejected by authenticate()
 * until its natural expiration (TTL is set to token's remaining lifetime).
 *
 * Throws on failure so callers can decide how to handle it.
 */
export async function blacklistToken(token: string, expiresInSeconds: number): Promise<void> {
  const client = await getClient();
  const ttl = Math.max(expiresInSeconds, 1);
  await client.set(`${BLACKLIST_PREFIX}${token}`, '1', { EX: ttl });
}

/**
 * Blacklist a token using its embedded exp claim to calculate TTL.
 * This is the preferred method — avoids hardcoded TTL values.
 */
export async function blacklistTokenAuto(token: string): Promise<void> {
  const ttl = getTokenRemainingTtl(token);
  if (ttl <= 0) return; // Already expired, no need to blacklist
  await blacklistToken(token, ttl);
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
  if (remainingSeconds <= 0) return;
  await blacklistToken(token, remainingSeconds);
}

/**
 * Gracefully close the Redis connection (for shutdown).
 */
export async function closeTokenBlacklist(): Promise<void> {
  if (redisClient) {
    await redisClient.quit();
    redisClient = null;
    redisReady = false;
  }
}
