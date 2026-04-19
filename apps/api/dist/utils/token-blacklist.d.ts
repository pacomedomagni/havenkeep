/**
 * Eagerly initialize the Redis connection at startup.
 * Call this from the server bootstrap so connection issues surface immediately.
 */
export declare function initializeTokenBlacklist(): Promise<void>;
/**
 * Blacklist a token using its embedded exp claim to calculate TTL.
 * The token will be rejected by authenticate() until its natural expiration.
 *
 * Throws on failure so callers can decide how to handle it.
 */
export declare function blacklistTokenAuto(token: string): Promise<void>;
/**
 * Check if a token has been blacklisted.
 *
 * Includes a circuit breaker: after {@link CIRCUIT_BREAKER_THRESHOLD}
 * consecutive Redis failures the circuit opens for
 * {@link CIRCUIT_BREAKER_RESET_MS} ms.  While open, requests are allowed
 * through (fail-open) and a critical warning is logged.  After the cooldown
 * period a single Redis call is attempted; on success the circuit closes.
 */
export declare function isTokenBlacklisted(token: string): Promise<boolean>;
/**
 * Gracefully close the Redis connection (for shutdown).
 */
export declare function closeTokenBlacklist(): Promise<void>;
//# sourceMappingURL=token-blacklist.d.ts.map