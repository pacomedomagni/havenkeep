import { Request, Response, NextFunction } from 'express';
import crypto from 'crypto';

// Double-submit cookie pattern CSRF implementation
// The token cookie is NOT httpOnly so the client JS can read it and
// send it back via the x-csrf-token header. The server then compares
// the header value against the cookie value.

const CSRF_HEADER = 'x-csrf-token';
const CSRF_COOKIE = 'csrf_token';

export function generateCsrfToken(): string {
  return crypto.randomBytes(32).toString('hex');
}

export function csrfProtection(req: Request, res: Response, next: NextFunction) {
  // Skip CSRF for GET, HEAD, OPTIONS (safe methods)
  if (['GET', 'HEAD', 'OPTIONS'].includes(req.method)) {
    return next();
  }

  const tokenFromHeader = req.get(CSRF_HEADER);
  const tokenFromCookie = req.cookies?.[CSRF_COOKIE];

  if (!tokenFromHeader || !tokenFromCookie || tokenFromHeader !== tokenFromCookie) {
    return res.status(403).json({ error: 'Invalid CSRF token' });
  }

  // Rotate token after successful validation
  const newToken = generateCsrfToken();
  res.cookie(CSRF_COOKIE, newToken, {
    httpOnly: false, // Client JS must read this to include in header
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
    maxAge: 86400000, // 24 hours
  });

  next();
}

export function setCsrfToken(req: Request, res: Response, next: NextFunction) {
  if (!req.cookies?.[CSRF_COOKIE]) {
    const token = generateCsrfToken();
    res.cookie(CSRF_COOKIE, token, {
      httpOnly: false, // Client JS must read this to include in header
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'strict',
      maxAge: 86400000, // 24 hours
    });
  }
  next();
}
