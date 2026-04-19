import { createClient } from 'redis';
import jwt from 'jsonwebtoken';
import { config } from '../config';
import { logger } from './logger';

let redisClient: ReturnType<typeof createClient> | null = null;
let redisReady = false;

// Circuit breaker state: after CIRCUIT_BREAKER_THRESHOLD consecutive Redis
// failures we stop hammering Redis for CIRCUIT_BREAKER_RESET_MS. Behavior
// while the circuit is open:
//   - development: fail-open (accept token) to keep local dev workable.
//   - production:  fail-closed (reject token) — we cannot verify revocation,
//                  so a revoked token must not slip through.
// After cooldown, a single Redis call is attempted; success closes the circuit.
const CIRCUIT_BREAKER_THRESHOLD = 5;
const CIRCUIT_BREAKER_RESET_MS = 60_000; // 60 seconds
let consecutiveFailures = 0;
let circuitOpenUntil = 0; // timestamp (ms) when the circuit should close again

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
function getTokenRemainingTtl(token: string): number {
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
 * Blacklist a token using its embedded exp claim to calculate TTL.
 * The token will be rejected by authenticate() until its natural expiration.
 *
 * Throws on failure so callers can decide how to handle it.
 */
export async function blacklistTokenAuto(token: string): Promise<void> {
  const ttl = getTokenRemainingTtl(token);
  if (ttl <= 0) return; // Already expired, no need to blacklist
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
export async function isTokenBlacklisted(token: string): Promise<boolean> {
  // Circuit is already open — skip Redis until cooldown elapses.
  if (consecutiveFailures >= CIRCUIT_BREAKER_THRESHOLD && Date.now() < circuitOpenUntil) {
    if (config.env === 'production') {
      // Fail-closed: cannot verify revocation, reject.
      return true;
    }
    return false;
  }

  if (consecutiveFailures >= CIRCUIT_BREAKER_THRESHOLD) {
    logger.info('Token blacklist circuit breaker cooldown expired, retrying Redis');
  }

  try {
    const client = await getClient();
    const result = await client.get(`${BLACKLIST_PREFIX}${token}`);

    if (consecutiveFailures > 0) {
      logger.info('Token blacklist Redis recovered, resetting circuit breaker');
    }
    consecutiveFailures = 0;
    circuitOpenUntil = 0;

    return result !== null;
  } catch (error) {
    consecutiveFailures++;
    logger.error({ error, consecutiveFailures }, 'Failed to check token blacklist');

    if (consecutiveFailures >= CIRCUIT_BREAKER_THRESHOLD) {
      circuitOpenUntil = Date.now() + CIRCUIT_BREAKER_RESET_MS;
      logger.fatal(
        { consecutiveFailures, circuitOpenUntilISO: new Date(circuitOpenUntil).toISOString() },
        'CRITICAL: Token blacklist circuit breaker OPEN — fail-closed in production, fail-open in dev'
      );
    }

    // Dev: fail-open to keep local iteration fast.
    if (config.env !== 'production') {
      return false;
    }
    // Production: fail-closed. We cannot verify token revocation, so reject.
    return true;
  }
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
