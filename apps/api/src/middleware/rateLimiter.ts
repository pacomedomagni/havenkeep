import rateLimit from 'express-rate-limit';
import { createClient } from 'redis';
import { config } from '../config';
import { logger } from '../utils/logger';

// Create Redis client for rate limiting
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
    
    await redisClient.connect();
  }
  return redisClient;
}

export const rateLimiter = rateLimit({
  windowMs: config.rateLimit.windowMs,
  max: config.rateLimit.max,
  message: 'Too many requests from this IP, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
  // Use Redis for distributed rate limiting in production
  skip: () => config.env === 'development',
});

// Specific rate limiters for sensitive endpoints
export const authRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5,
  message: 'Too many login attempts, please try again later.',
});

export const uploadRateLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 10,
  message: 'Too many uploads, please try again later.',
});
