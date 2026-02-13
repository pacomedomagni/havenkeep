/**
 * Blacklist a JWT access token. The token will be rejected by authenticate()
 * until its natural expiration (TTL is set to token's remaining lifetime).
 */
export declare function blacklistToken(token: string, expiresInSeconds: number): Promise<void>;
/**
 * Check if a token has been blacklisted.
 */
export declare function isTokenBlacklisted(token: string): Promise<boolean>;
/**
 * Blacklist all active tokens for a user by blacklisting the current token
 * and deleting all refresh tokens (forcing re-auth).
 */
export declare function blacklistUserTokens(token: string, tokenExp: number): Promise<void>;
//# sourceMappingURL=token-blacklist.d.ts.map