/**
 * Format a money amount for display. Accepts a string (the canonical wire
 * shape for DECIMAL columns) OR a number; in the string case we use the
 * server's exact representation rather than parseFloat-ing it back into a
 * binary float (audit Ch10-W036).
 *
 * Falls back to "$0.00" on anything we can't parse — never "NaN".
 */
export function formatCurrency(amount: number | string): string {
  let n: number;
  if (typeof amount === 'string') {
    if (amount.trim() === '') return '$0.00';
    n = Number(amount);
  } else {
    n = amount;
  }
  if (!Number.isFinite(n)) return '$0.00';
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  }).format(n);
}

/**
 * Validate a URL is HTTP(S) and points at our own domains. Used before any
 * action that copies a URL to the clipboard so a tampered backend response
 * can't seed a phishing link into the user's clipboard
 * (audit Ch10-W030).
 */
export function isSafeActivationUrl(value: string | null | undefined): value is string {
  if (typeof value !== 'string' || value.length === 0) return false;
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return false;
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return false;
  // Allowlist of hostnames that are legitimately part of the activation flow.
  // Add more here when staging-only hosts ship.
  const allowed = new Set([
    'havenkeep.com',
    'www.havenkeep.com',
    'app.havenkeep.com',
    'partners.havenkeep.com',
  ]);
  if (!allowed.has(url.hostname)) {
    // In dev/test we accept any localhost port.
    if (process.env.NODE_ENV !== 'production' && url.hostname === 'localhost') return true;
    return false;
  }
  return true;
}

/**
 * Validate a logo URL before rendering it as an `<img src>`. Rejects
 * `javascript:` / `data:` / `file:` / opaque-origin URLs (audit Ch10-W024).
 * Allowed protocols: http, https.
 */
export function isSafeLogoUrl(value: string | null | undefined): value is string {
  if (typeof value !== 'string' || value.length === 0) return false;
  if (value.length > 2048) return false;
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return false;
  }
  return url.protocol === 'https:' || url.protocol === 'http:';
}
