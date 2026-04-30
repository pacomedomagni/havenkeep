import crypto from 'crypto';
import { config } from '../config';

/**
 * HMAC-SHA-256 of an opaque bearer token, keyed by the refresh-token JWT
 * secret.
 *
 * Audit Ch01-F019: storage uses a *keyed* hash so a DB-only leak (read-only
 * Postgres replica, backup tape, BAR/BAA breach) doesn't allow offline
 * lookup against a stolen plaintext token. The HMAC key is the
 * refresh-token secret, which is required-in-prod by the env validator.
 *
 * Used for: refresh-token storage, password-reset tokens, register-flow
 * email-verification tokens, and (S-M9) the change-email verification token.
 */
export function hashToken(token: string): string {
  return crypto.createHmac('sha256', config.jwt.refreshSecret).update(token).digest('hex');
}

// Alias retained for refresh-token call sites that read more naturally with
// the longer name. Same function — same key, same algorithm.
export const hashRefreshToken = hashToken;
