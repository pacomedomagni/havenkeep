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

  async increment(key: string): Promise<{ totalHits: number; resetTime: Date }> {
    const redisKey = this.prefix + key;
    const now = Date.now();
    const windowStart = now - this.windowMs;

    // Remove old entries
    await this.client.zRemRangeByScore(redisKey, 0, windowStart);

    // Add current request
    await this.client.zAdd(redisKey, { score: now, value: String(now) });

    // Count requests in window
    const totalHits = await this.client.zCard(redisKey);

    // Set expiry
    await this.client.expire(redisKey, Math.ceil(this.windowMs / 1000));

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
      logger.error('Failed to initialize Redis rate limiter, falling back to memory store', error);
      return createMemoryRateLimiter();
    }
  } else {
    // Use memory store for development
    return createMemoryRateLimiter();
  }
};

function createMemoryRateLimiter() {
  return rateLimit({
    windowMs: config.rateLimit.windowMs,
    max: config.rateLimit.max * 10, // More lenient in development
    message: 'Too many requests from this IP, please try again later.',
    standardHeaders: true,
    legacyHeaders: false,
    skip: (req) => {
      return req.path.startsWith('/health') || req.path.startsWith('/live') || req.path.startsWith('/ready');
    },
  });
}

// Export as a promise that resolves to the middleware
export const rateLimiter = await initializeRateLimiter();

// Specific rate limiters for sensitive endpoints
export const authRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5,
  message: 'Too many login attempts, please try again later.',
  skipSuccessfulRequests: true, // Don't count successful logins
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
