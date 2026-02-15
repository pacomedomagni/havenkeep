import rateLimit from 'express-rate-limit';
import { createClient } from 'redis';
import { config } from '../config';
import { logger } from '../utils/logger';

// Redis store for distributed rate limiting
let redisClient: ReturnType<typeof createClient> | null = null;

async function getRedisClient() {
  if (!redisClient) {
    redisClient = createClient({
      url: config.redis.url,
      password: config.redis.password,
    });

    redisClient.on('error', (err) => {
      logger.error('Redis error:', err);
    });

    redisClient.on('connect', () => {
      logger.info('✅ Redis connected for rate limiting');
    });

    await redisClient.connect();
  }
  return redisClient;
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

  async decrement(key: string): Promise<void> {
    // Optional: implement if needed
  }

  async resetKey(key: string): Promise<void> {
    const redisKey = this.prefix + key;
    await this.client.del(redisKey);
  }
}

// Initialize rate limiter with Redis in production
const initializeRateLimiter = async () => {
  if (config.env === 'production') {
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
          // Skip rate limiting for health checks
          return req.path.startsWith('/health') || req.path.startsWith('/live') || req.path.startsWith('/ready');
        },
      });
    } catch (error) {
      logger.error('Failed to initialize Redis rate limiter in production', error);
      throw new Error('Redis is required for rate limiting in production');
    }
  } else {
    // Use memory store for development
    return createMemoryRateLimiter();
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

// Specific rate limiters for sensitive endpoints
export const authRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10,
  message: 'Too many attempts, please try again later.',
});

// Refresh rate limiter: 10 requests per 15 minutes.
// This is intentionally generous since mobile apps may refresh tokens frequently.
// Consider reducing if abuse is detected.
export const refreshRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10,
  message: 'Too many token refresh attempts, please try again later.',
  skipSuccessfulRequests: false, // Count all attempts for brute-force protection
});

export const uploadRateLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 10,
  message: 'Too many uploads, please try again later.',
});

export const passwordResetRateLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 3,
  message: 'Too many password reset attempts, please try again later.',
});

export const activationCodeRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10,
  message: 'Too many activation code attempts, please try again later.',
});

// BE-12: Rate limiter for premium verification endpoint
// Limits to 5 requests per 15 minutes to prevent abuse of RevenueCat API calls
export const verifyPremiumRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5,
  message: 'Too many premium verification attempts, please try again later.',
});
