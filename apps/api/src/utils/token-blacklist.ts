import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import { config } from '../config';
import { logger } from './logger';
import { getRedisClient, closeRedisClient } from './redis';

// Single shared Redis client (Ch11-I060). The blacklist used to maintain its
// own connection that diverged from the rest of the app's Redis state.
//
// Circuit breaker — after CIRCUIT_BREAKER_THRESHOLD consecutive failures we
// stop hitting Redis for CIRCUIT_BREAKER_RESET_MS. Behavior while open:
//   - production: fail-CLOSED on revocation checks (audit Ch11-I067 wanted no
//     "10s window where a revoked token still works")
//   - development/test: fail-OPEN to keep iteration fast
const CIRCUIT_BREAKER_THRESHOLD = 5;
const CIRCUIT_BREAKER_RESET_MS = 30_000;          // 30s — Ch11-I069 (was 70s)
let consecutiveFailures = 0;
let circuitOpenUntil = 0;

const BLACKLIST_PREFIX = 'token:blacklist:';

/**
 * Hash the JWT before using it as a Redis key (Ch11-I066). The raw token is
 * (a) very long, (b) sensitive — anyone with shell access to Redis would
 * otherwise see the full bearer token in `KEYS *`.
 */
function tokenKey(token: string): string {
  const sha = crypto.createHash('sha256').update(token).digest('hex');
  return `${BLACKLIST_PREFIX}${sha}`;
}

/**
 * Initialise the shared Redis client at startup. Kept as a named export so
 * `index.ts` can fail fast if Redis is unreachable.
 */
export async function initializeTokenBlacklist(): Promise<void> {
  await getRedisClient();
}

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

export async function blacklistTokenAuto(token: string): Promise<void> {
  const ttl = getTokenRemainingTtl(token);
  if (ttl <= 0) return;
  const client = await getRedisClient();
  await client.set(tokenKey(token), '1', { EX: ttl });
}

export async function isTokenBlacklisted(token: string): Promise<boolean> {
  // Circuit open and still inside cooldown — skip Redis entirely.
  if (consecutiveFailures >= CIRCUIT_BREAKER_THRESHOLD && Date.now() < circuitOpenUntil) {
    // Production fails closed: if we can't verify, treat as revoked.
    return config.env === 'production';
  }
  if (consecutiveFailures >= CIRCUIT_BREAKER_THRESHOLD) {
    logger.info('Token blacklist circuit breaker cooldown expired, retrying Redis');
  }

  try {
    const client = await getRedisClient();
    const result = await client.get(tokenKey(token));

    if (consecutiveFailures > 0) {
      logger.info({ consecutiveFailures }, 'Token blacklist Redis recovered, resetting circuit breaker');
    }
    consecutiveFailures = 0;
    circuitOpenUntil = 0;

    return result !== null;
  } catch (error) {
    consecutiveFailures += 1;

    // Ch11-I070: distinguish auth errors (which should NOT count toward the
    // breaker — they indicate a config bug, not a Redis outage) from network
    // errors (which should). We treat NOAUTH/WRONGPASS as fatal and re-throw
    // so the caller surfaces a 500 instead of silently fail-closing.
    const msg = (error as Error).message?.toUpperCase() ?? '';
    if (msg.includes('NOAUTH') || msg.includes('WRONGPASS')) {
      consecutiveFailures = 0;
      logger.fatal({ error }, 'Redis auth failure on token blacklist — fix Redis credentials');
      throw error;
    }

    logger.error({ error, consecutiveFailures }, 'Failed to check token blacklist');

    if (consecutiveFailures >= CIRCUIT_BREAKER_THRESHOLD) {
      circuitOpenUntil = Date.now() + CIRCUIT_BREAKER_RESET_MS;
      logger.fatal(
        { consecutiveFailures, circuitOpenUntilISO: new Date(circuitOpenUntil).toISOString() },
        'CRITICAL: Token blacklist circuit breaker OPEN',
      );
    }

    // Production fails closed; dev fails open.
    return config.env === 'production';
  }
}

/**
 * Resets shared Redis state for shutdown. The shared-client module owns the
 * actual close path (removeAllListeners + quit) — this re-export is here so
 * `index.ts` can call closeTokenBlacklist alongside the other shutdown hooks.
 */
export async function closeTokenBlacklist(): Promise<void> {
  await closeRedisClient();
}
