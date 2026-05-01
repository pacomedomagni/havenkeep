import { Router, Request, Response } from 'express';
import crypto from 'crypto';

const CSRF_COOKIE = 'csrf_token';
const router = Router();

/**
 * S-M7: public CSRF mint endpoint for browser clients that talk directly to
 * api.havenkeep.com without going through the partner-dashboard proxy.
 *
 * The dashboard's Edge middleware (apps/partner-dashboard/middleware.ts:
 * ensureCsrfCookie) handles minting for traffic flowing through the proxy.
 * For any other browser surface — a future static SPA, a third-party app
 * embedding the API — there had to be a way to obtain the cookie before
 * the first state-changing request, since validateCsrfToken refuses any
 * cookie-bearing mutation that doesn't double-submit.
 *
 * Idempotent: if the cookie is already present and well-formed, return it
 * unchanged so this endpoint can be polled safely. Mint a fresh 32-byte
 * hex token only when the request arrives without one.
 *
 * GET (not POST) so it slots in front of the global validateCsrfToken
 * gate without an ordering hack — the gate skips safe methods. We set
 * Cache-Control: no-store so a CDN can't ever serve a token meant for
 * one client to a different one.
 *
 * SameSite=Lax + non-HttpOnly mirrors the rest of the auth surface (the
 * double-submit pattern needs JS read access). Secure in prod only.
 */
router.get('/', (req: Request, res: Response) => {
  const existing = req.cookies?.[CSRF_COOKIE];
  const wellFormed = typeof existing === 'string' && /^[a-f0-9]{64}$/.test(existing);
  const token = wellFormed ? existing : crypto.randomBytes(32).toString('hex');

  res.cookie(CSRF_COOKIE, token, {
    httpOnly: false,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
    maxAge: 86400000, // 24h — matches setCsrfToken
  });
  // Defence-in-depth: any cache between the API and the client (Caddy,
  // a future CDN, a misconfigured browser cache) must not memoise this
  // response. Each call must reach the API so the cookie roll-forward
  // happens.
  res.setHeader('Cache-Control', 'no-store');

  res.json({ success: true, csrfToken: token });
});

export default router;
