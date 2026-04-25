/**
 * Disposable / temporary email domain blocklist (audit Ch12-T045).
 *
 * The list is intentionally small — we only block the most common abuse
 * vectors that show up in signup spam. It is NOT a substitute for proper
 * email verification, which the registration flow already does separately.
 *
 * Adding a domain: lowercase, no leading `@`, exact-match.
 */

const DISPOSABLE_DOMAINS = new Set<string>([
  'mailinator.com',
  'guerrillamail.com',
  'guerrillamail.net',
  'guerrillamail.org',
  '10minutemail.com',
  'tempmail.com',
  'temp-mail.org',
  'temp-mail.io',
  'throwawaymail.com',
  'yopmail.com',
  'yopmail.net',
  'getnada.com',
  'maildrop.cc',
  'sharklasers.com',
  'trashmail.com',
  'fakeinbox.com',
  'tempinbox.com',
  'discard.email',
  'dispostable.com',
]);

/**
 * Returns true if the email's domain is on the disposable blocklist.
 * Comparison is case-insensitive and tolerant of whitespace.
 */
export function isDisposableEmail(email: string): boolean {
  if (!email || typeof email !== 'string') return false;
  const trimmed = email.trim().toLowerCase();
  const at = trimmed.lastIndexOf('@');
  if (at < 0 || at === trimmed.length - 1) return false;
  const domain = trimmed.slice(at + 1);
  return DISPOSABLE_DOMAINS.has(domain);
}

export const _DISPOSABLE_DOMAINS_FOR_TEST = DISPOSABLE_DOMAINS;
