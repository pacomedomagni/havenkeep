declare const initializeRateLimiter: () => Promise<import("express-rate-limit").RateLimitRequestHandler>;
export { initializeRateLimiter };
/**
 * Close the Redis client(s) used by the rate limiter.
 * Call during graceful shutdown to avoid leaked connections.
 */
export declare function closeRateLimiterRedis(): Promise<void>;
export declare const authRateLimiter: import("express-rate-limit").RateLimitRequestHandler;
export declare const refreshRateLimiter: import("express-rate-limit").RateLimitRequestHandler;
export declare const uploadRateLimiter: import("express-rate-limit").RateLimitRequestHandler;
export declare const passwordResetRateLimiter: import("express-rate-limit").RateLimitRequestHandler;
export declare const activationCodeRateLimiter: import("express-rate-limit").RateLimitRequestHandler;
export declare const verifyPremiumRateLimiter: import("express-rate-limit").RateLimitRequestHandler;
export declare const passwordChangeRateLimiter: import("express-rate-limit").RateLimitRequestHandler;
export declare const writeRateLimiter: import("express-rate-limit").RateLimitRequestHandler;
export declare const giftResendRateLimiter: import("express-rate-limit").RateLimitRequestHandler;
export declare const receiptScanRateLimiter: import("express-rate-limit").RateLimitRequestHandler;
export declare const newsletterRateLimiter: import("express-rate-limit").RateLimitRequestHandler;
export declare const contactRateLimiter: import("express-rate-limit").RateLimitRequestHandler;
//# sourceMappingURL=rateLimiter.d.ts.map