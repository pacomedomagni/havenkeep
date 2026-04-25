import rateLimit from 'express-rate-limit';
import type { createClient } from 'redis';
import { config } from '../config';
import { logger } from '../utils/logger';
import { getRedisClient as getSharedRedisClient } from '../utils/redis';

// Reuse the shared Redis client (Ch11-I060). The rate limiter used to open
// its own connection that diverged from token-blacklist + the user cache;
// every Redis hiccup hit one client and not the others, producing
// hard-to-triage flakiness.
async function getRedisClient(): Promise<ReturnType<typeof createClient>> {
  return getSharedRedisClient();
}

// Custom Redis store for rate limiting
class RedisStore {
  private prefix: string;
  private client: ReturnType<typeof createClient>;
  private windowMs: number;

  constructor(client: ReturnType<typeof createClient>, windowMs: number, prefix = 'rl:') {
    this.client = client;
    this.windowMs = windowMs;
    this.prefix = prefix;
  }

  // Lua script that atomically: removes expired entries, adds the current
  // request, counts the remaining entries, and sets the key TTL.  This avoids
  // the race condition inherent in separate ZRANGEBYSCORE + ZADD calls.
  private static readonly LUA_INCREMENT = `
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

  async increment(key: string): Promise<{ totalHits: number; resetTime: Date }> {
    const redisKey = this.prefix + key;
    const now = Date.now();
    const windowStart = now - this.windowMs;
    const ttlSeconds = Math.ceil(this.windowMs / 1000);

    // Execute the sliding-window rate-limit logic atomically in a single
    // Lua script to prevent race conditions under concurrent requests.
    const totalHits = await this.client.eval(RedisStore.LUA_INCREMENT, {
      keys: [redisKey],
      arguments: [String(now), String(windowStart), String(ttlSeconds)],
    }) as number;

    const resetTime = new Date(now + this.windowMs);

    return { totalHits, resetTime };
  }

  async resetKey(key: string): Promise<void> {
    const redisKey = this.prefix + key;
    await this.client.del(redisKey);
  }
}

// Initialize rate limiter with Redis in production and staging.
// Audit Ch11-I089: the previous "fall back to memory if Redis unavailable"
// path silently shrunk the production rate limit to a per-instance count,
// which under multi-instance deploys means a 100/min limit becomes 100*N/min.
// Production now FAILS startup if Redis is required and unavailable.
const initializeRateLimiter = async () => {
  const isProduction = config.env === 'production' || config.env === 'staging';
  if (!isProduction) {
    return createMemoryRateLimiter();
  }
  try {
    const client = await getRedisClient();
    const store = new RedisStore(client, config.rateLimit.windowMs);

    return rateLimit({
      windowMs: config.rateLimit.windowMs,
      max: config.rateLimit.max,
      message: 'Too many requests from this IP, please try again later.',
      standardHeaders: true,
      legacyHeaders: false,
      handler: (req, res) => {
        logger.warn({
          ip: req.ip,
          path: req.path,
          userAgent: req.get('user-agent'),
        }, 'Rate limit exceeded');

        res.status(429).json({
          error: 'Too many requests',
          message: 'Please try again later',
          retryAfter: Math.ceil(config.rateLimit.windowMs / 1000),
        });
      },
      skip: (req) => {
        return req.path.startsWith('/health') || req.path.startsWith('/live') || req.path.startsWith('/ready');
      },
      store: store as any,
    });
  } catch (error) {
    // No silent memory fallback in production — surface the failure so the
    // pod fails health and the load balancer keeps its old healthy targets.
    logger.fatal({ error }, 'Redis required for rate limiting in production but unavailable');
    throw error;
  }
};

function createMemoryRateLimiter() {
  return rateLimit({
    windowMs: config.rateLimit.windowMs,
    // 10x multiplier: in development, hot-reloading and manual testing tools
    // (e.g. Postman, cURL loops) generate many more requests than real users.
    // The higher limit avoids false rate-limit blocks during local development
    // while still exercising the rate-limiting code path.
    max: config.rateLimit.max * 10,
    message: 'Too many requests from this IP, please try again later.',
    standardHeaders: true,
    legacyHeaders: false,
    skip: (req) => {
      return req.path.startsWith('/health') || req.path.startsWith('/live') || req.path.startsWith('/ready');
    },
  });
}

// Export the initializer — must be awaited in index.ts
export { initializeRateLimiter };

// Shared Redis store reference, populated after initializeRateLimiter runs.
// Endpoint-specific limiters lazily pick this up so they benefit from
// distributed rate limiting in production without requiring async init.
let sharedRedisClient: ReturnType<typeof createClient> | null = null;

function createEndpointRateLimiter(options: {
  windowMs: number;
  max: number;
  message: string;
  skipSuccessfulRequests?: boolean;
}) {
  // If Redis is available, create a RedisStore for this limiter
  const store = sharedRedisClient
    ? new RedisStore(sharedRedisClient, options.windowMs, `rl:${options.message.slice(0, 10)}:`)
    : undefined;

  return rateLimit({
    ...options,
    standardHeaders: true,
    legacyHeaders: false,
    ...(store ? { store: store as any } : {}),
  });
}

// Initialize the shared Redis client for endpoint-specific limiters.
// Called after initializeRateLimiter resolves.
async function initializeEndpointRedis() {
  if (config.env !== 'development' && config.env !== 'test') {
    try {
      sharedRedisClient = await getRedisClient();
    } catch (error) {
      logger.error('Failed to initialize Redis for endpoint rate limiters, using in-memory store', error);
    }
  }
}

// Eagerly attempt to connect (non-blocking).
// The limiters will use in-memory until this resolves.
initializeEndpointRedis().catch((err) => {
  logger.error('Failed to initialize endpoint Redis (non-fatal):', err);
});

/**
 * Close the rate-limiter's reference to Redis. The shared Redis client owns
 * the actual socket close (utils/redis.ts → closeRedisClient); this function
 * only clears the module-level reference to it.
 */
export async function closeRateLimiterRedis(): Promise<void> {
  sharedRedisClient = null;
}

// Specific rate limiters for sensitive endpoints
export const authRateLimiter = createEndpointRateLimiter({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10,
  message: 'Too many attempts, please try again later.',
});

// Refresh rate limiter: 10 requests per 15 minutes.
// This is intentionally generous since mobile apps may refresh tokens frequently.
// Consider reducing if abuse is detected.
export const refreshRateLimiter = createEndpointRateLimiter({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10,
  message: 'Too many token refresh attempts, please try again later.',
  skipSuccessfulRequests: false, // Count all attempts for brute-force protection
});

export const uploadRateLimiter = createEndpointRateLimiter({
  windowMs: 60 * 1000, // 1 minute
  max: 10,
  message: 'Too many uploads, please try again later.',
});

export const passwordResetRateLimiter = createEndpointRateLimiter({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 3,
  message: 'Too many password reset attempts, please try again later.',
});

export const activationCodeRateLimiter = createEndpointRateLimiter({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10,
  message: 'Too many activation code attempts, please try again later.',
});

// BE-12: Rate limiter for premium verification endpoint
// Limits to 5 requests per 15 minutes to prevent abuse of RevenueCat API calls
export const verifyPremiumRateLimiter = createEndpointRateLimiter({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5,
  message: 'Too many premium verification attempts, please try again later.',
});

// Rate limiter for password change endpoint
// 5 attempts per hour to prevent brute-force current password guessing
export const passwordChangeRateLimiter = createEndpointRateLimiter({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 5,
  message: 'Too many password change attempts, please try again later.',
});

// Rate limiter for write endpoints (POST, PUT, DELETE)
// 30 requests per 15 minutes to prevent abuse of data-mutating operations
export const writeRateLimiter = createEndpointRateLimiter({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 30,
  message: 'Too many write requests, please try again later.',
});

// Gift email resend limiter: 3 resends per hour per IP
export const giftResendRateLimiter = createEndpointRateLimiter({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 3,
  message: 'Too many gift email resend attempts, please try again later.',
});

// Receipt scan limiter: 10 per minute per IP
export const receiptScanRateLimiter = createEndpointRateLimiter({
  windowMs: 60 * 1000, // 1 minute
  max: 10,
  message: 'Too many receipt scan requests, please try again later.',
});

// Items list limiter (Ch02-F065): cheap to call but expensive to scale; cap
// at 60 reads/minute per IP. Burst-friendly for normal app use, blocks
// scrapers.
export const itemsListRateLimiter = createEndpointRateLimiter({
  windowMs: 60 * 1000, // 1 minute
  max: 60,
  message: 'Too many list requests, please try again later.',
});

// CSV export limiter (Ch02-F066): exports stream the entire item table; cap
// to 5 per hour per IP to prevent unbounded server work.
export const csvExportRateLimiter = createEndpointRateLimiter({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 5,
  message: 'Too many CSV exports, please try again later.',
});

// Newsletter subscription limiter: 5 per hour per IP
export const newsletterRateLimiter = createEndpointRateLimiter({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 5,
  message: 'Too many subscription attempts, please try again later.',
});

// Contact form limiter: 3 per hour per IP
export const contactRateLimiter = createEndpointRateLimiter({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 3,
  message: 'Too many contact submissions, please try again later.',
});

// Generic read limiter (Ch04-F009/F089): per-IP cap on cheap GET endpoints
// that fan out big joins (warranty-claims list, audit/logs, etc.). 120/min
// matches the busy mobile-app scrolling pattern; anything above is scraping.
export const readRateLimiter = createEndpointRateLimiter({
  windowMs: 60 * 1000, // 1 minute
  max: 120,
  message: 'Too many read requests, please slow down.',
});
