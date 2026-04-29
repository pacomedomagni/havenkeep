import type { Request } from 'express';

/// Resolve the trusted client IP from the request.
///
/// 4.11: hoisted out of `audit.service.ts` so the request logger can
/// share the same XFF-trimming policy. Express's own `req.ip` reflects
/// the *first* trusted hop (per `app.set('trust proxy', N)`), but our
/// audit-logging policy is more conservative — strip exactly
/// `TRUST_PROXY_HOPS` proxies from the right and trust the leftover. If
/// XFF is absent or fully consumed, fall back to the socket address.
const TRUST_PROXY_HOPS = Math.max(
  0,
  Number(process.env.TRUST_PROXY_HOPS ?? '1'),
);

export function getIpAddress(req: Request): string {
  const raw = req.headers['x-forwarded-for'];
  if (typeof raw === 'string' && raw.length > 0) {
    // XFF order is "client, proxy1, proxy2, ..., closestProxy". Strip
    // the configured proxy count from the right; whatever sits at that
    // index is the closest hop we'll trust as the client.
    const parts = raw.split(',').map((s) => s.trim()).filter(Boolean);
    const idx = parts.length - 1 - TRUST_PROXY_HOPS;
    if (idx >= 0 && parts[idx]) {
      return parts[idx];
    }
  }
  return req.socket.remoteAddress || 'unknown';
}
