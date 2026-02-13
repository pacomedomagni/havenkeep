declare const initializeRateLimiter: () => Promise<import("express-rate-limit").RateLimitRequestHandler>;
export { initializeRateLimiter };
export declare const authRateLimiter: import("express-rate-limit").RateLimitRequestHandler;
export declare const refreshRateLimiter: import("express-rate-limit").RateLimitRequestHandler;
export declare const uploadRateLimiter: import("express-rate-limit").RateLimitRequestHandler;
export declare const passwordResetRateLimiter: import("express-rate-limit").RateLimitRequestHandler;
export declare const activationCodeRateLimiter: import("express-rate-limit").RateLimitRequestHandler;
//# sourceMappingURL=rateLimiter.d.ts.map