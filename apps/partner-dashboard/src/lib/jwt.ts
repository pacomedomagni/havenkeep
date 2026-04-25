/**
 * Browser/edge-safe JWT helpers. The Express API is the only signature
 * verifier; the dashboard validates structure + expiry to short-circuit
 * obvious tampering and to drive UI redirects (audit Ch10-W008, W009, W016).
 */

export interface DecodedJwt {
  userId?: string;
  email?: string;
  exp?: number;
  iat?: number;
  isAdmin?: boolean;
  isPartner?: boolean;
  [k: string]: unknown;
}

/**
 * Cheap structural check — three base64url segments separated by dots, with
 * non-empty header and payload. Rejects everything that obviously isn't a JWT
 * before we attempt to decode.
 */
export function looksLikeJwt(token: unknown): token is string {
  if (typeof token !== 'string' || token.length === 0) return false;
  if (token.length > 4096) return false;
  const parts = token.split('.');
  if (parts.length !== 3) return false;
  const re = /^[A-Za-z0-9_-]+$/;
  return parts.every((p) => p.length > 0 && re.test(p));
}

export function decodeJwtPayload(token: string): DecodedJwt | null {
  if (!looksLikeJwt(token)) return null;
  try {
    const payload = token.split('.')[1];
    return JSON.parse(Buffer.from(payload, 'base64url').toString());
  } catch {
    return null;
  }
}

/**
 * Treat the token as expired 30 seconds early so we don't issue API calls
 * that race the actual expiry on the wire (Ch10-W016).
 */
export function isTokenExpired(token: string, skewMs = 30_000): boolean {
  const payload = decodeJwtPayload(token);
  if (!payload || typeof payload.exp !== 'number') return true;
  return payload.exp * 1000 < Date.now() + skewMs;
}
