import { Request, Response, NextFunction } from 'express';
import crypto from 'crypto';

const CSRF_COOKIE = 'csrf_token';
const CSRF_HEADER = 'x-csrf-token';

function generateCsrfToken(): string {
  return crypto.randomBytes(32).toString('hex');
}

/**
 * Issue the CSRF cookie on first contact. The cookie is non-httpOnly because
 * the browser-side JS reads it to set the X-CSRF-Token header (double-submit
 * cookie pattern). SameSite=Lax (not Strict — Ch11-I029) so the cookie is
 * sent on top-level navigations the OAuth callback relies on.
 */
export function setCsrfToken(req: Request, res: Response, next: NextFunction) {
  if (!req.cookies?.[CSRF_COOKIE]) {
    const token = generateCsrfToken();
    res.cookie(CSRF_COOKIE, token, {
      httpOnly: false,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'lax',
      maxAge: 86400000, // 24 hours
    });
  }
  next();
}

function constantTimeEquals(a: string, b: string): boolean {
  // Length-mismatch comparison short-circuits in O(1) by encoding to a
  // common buffer first; without this `Buffer.from(a).length !== Buffer.from(b).length`
  // already leaks the length differential.  (Ch11-I030)
  if (a.length !== b.length) return false;
  const bufA = Buffer.from(a, 'utf8');
  const bufB = Buffer.from(b, 'utf8');
  return crypto.timingSafeEqual(bufA, bufB);
}

/**
 * Validate the double-submit CSRF token on state-changing requests.
 *
 * Bearer auth bypass: ONLY skipped when the request carries no cookie at all
 * (audit Ch11-I009). A request that ships a Bearer header AND a session
 * cookie is a browser request whose CSRF protection still applies — the
 * "skip" used to wave through a forged form post that piggy-backed a stale
 * Bearer header.
 */
export function validateCsrfToken(req: Request, res: Response, next: NextFunction) {
  const safeMethods = ['GET', 'HEAD', 'OPTIONS'];
  if (safeMethods.includes(req.method)) return next();

  const hasCookieAuth = Boolean(req.cookies?.[CSRF_COOKIE]) || Object.keys(req.cookies ?? {}).length > 0;
  const hasBearer = (req.headers.authorization ?? '').startsWith('Bearer ');

  // Pure Bearer-auth API call (no cookies in flight) — CSRF doesn't apply.
  if (hasBearer && !hasCookieAuth) return next();

  // Cookie session must always present a matching token (Ch11-I031: the old
  // skip-if-no-cookie path let a request with no CSRF cookie bypass entirely;
  // any cookie-bearing mutation requires double-submit).
  const cookieToken = req.cookies?.[CSRF_COOKIE];
  const headerToken = req.headers[CSRF_HEADER] as string | undefined;
  if (!cookieToken || !headerToken || !constantTimeEquals(cookieToken, headerToken)) {
    return res.status(403).json({ success: false, error: 'CSRF token missing or invalid', code: 'CSRF_FAILED' });
  }
  next();
}
