import { Request, Response, NextFunction } from 'express';
import crypto from 'crypto';

const CSRF_COOKIE = 'csrf_token';
const CSRF_HEADER = 'x-csrf-token';

function generateCsrfToken(): string {
  return crypto.randomBytes(32).toString('hex');
}

function csrfCookieOptions() {
  return {
    httpOnly: false,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax' as const,
    maxAge: 86400000, // 24 hours
  };
}

/**
 * Roll the CSRF cookie forward when the request already carries one.
 * Pre-S-ME-02, this minted a cookie on every anonymous request, which
 * both (a) created useless tokens for traffic with no session, and
 * (b) opened a token-fixation vector: an attacker could drop a known
 * token into a victim's browser pre-login, and that token would
 * persist across login.
 *
 * L2 (audit): the prior comment claimed access/refresh cookies also
 * trigger refresh — they do NOT. Only the CSRF cookie itself drives
 * the roll-forward here. The dashboard's Edge middleware
 * (apps/partner-dashboard/middleware.ts:ensureCsrfCookie) is the
 * upstream half that mints the cookie when a logged-in user lands
 * without one; this middleware is the downstream half that just
 * refreshes the maxAge so an idle session doesn't lose CSRF
 * protection mid-flow. Browser clients that talk directly to
 * api.havenkeep.com bypassing the dashboard proxy mint via
 * GET /api/v1/csrf (S-M7 — see routes/csrf.ts).
 *
 * Auth handlers (login, refresh, OAuth, signup) call [rotateCsrfToken]
 * to issue a fresh token bound to the new session.
 *
 * SameSite=Lax (not Strict — Ch11-I029) so the cookie is sent on
 * top-level navigations the OAuth callback relies on.
 */
export function setCsrfToken(req: Request, res: Response, next: NextFunction) {
  // Only refresh the cookie if it already exists. Do NOT issue a fresh
  // token to anonymous traffic — auth handlers (rotateCsrfToken) and
  // the dashboard's ensureCsrfCookie are responsible for minting on
  // auth-state change / first-touch.
  if (req.cookies?.[CSRF_COOKIE]) {
    res.cookie(CSRF_COOKIE, req.cookies[CSRF_COOKIE], csrfCookieOptions());
  }
  next();
}

/**
 * Rotate the CSRF cookie. Called from auth handlers (login, refresh,
 * OAuth-google, OAuth-apple, signup) so a fresh token binds to each new
 * session. Mitigates token-fixation: a token planted pre-login can't
 * survive into the post-login session.
 */
export function rotateCsrfToken(res: Response): void {
  res.cookie(CSRF_COOKIE, generateCsrfToken(), csrfCookieOptions());
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
 * The protection model: cookies in flight = browser session; no cookies =
 * pure API client (mobile, server-to-server). XSRF needs a victim's
 * cookie to forge against — without one, an attacker can't exploit
 * anything. So we bypass CSRF when there are no cookies at all,
 * regardless of whether a Bearer token is also present.
 *
 * The previous gate also required a Bearer token to bypass, which made
 * `/auth/login` unreachable from mobile (no Bearer yet on first sign-in,
 * no cookies because mobile clients don't store them).
 *
 * 4.2: cross-app invariant — the partner-dashboard proxy at
 * `apps/partner-dashboard/src/app/api/v1/[...path]/route.ts` strips
 * cookies on every forward and runs its OWN double-submit CSRF check at
 * the proxy layer. Removing the no-cookie bypass below would 403 every
 * dashboard mutation. If you ever need cookie-bearing requests through
 * the proxy, add a shared-secret `x-internal-proxy` header bypass here
 * AND restore cookie pass-through there — see that file's header for
 * the matching note.
 */
export function validateCsrfToken(req: Request, res: Response, next: NextFunction) {
  const safeMethods = ['GET', 'HEAD', 'OPTIONS'];
  if (safeMethods.includes(req.method)) return next();

  const hasAnyCookie = Object.keys(req.cookies ?? {}).length > 0;

  // No cookies = no browser session at risk → CSRF doesn't apply.
  if (!hasAnyCookie) return next();

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
