import { createClient } from 'redis';
export type RedisClient = ReturnType<typeof createClient>;
/**
 * Returns the shared Redis client, creating and connecting it on first call.
 * All modules that need Redis should use this instead of creating their own client.
 */
export declare function getRedisClient(): Promise<RedisClient>;
/**
 * Gracefully close the shared Redis connection (for shutdown).
 */
export declare function closeRedisClient(): Promise<void>;
//# sourceMappingURL=redis.d.ts.map