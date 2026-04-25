/**
 * Single source of truth for email validation, mirroring the backend's
 * `validateEmail` rule (audit Ch10-W012). The dashboard's own permissive
 * regex previously accepted addresses the API rejected, which surfaced as
 * a confusing "Registration failed" with no field-level explanation.
 */

const EMAIL_RE =
  /^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$/;

export function isValidEmail(value: unknown): value is string {
  if (typeof value !== 'string') return false;
  if (value.length < 3 || value.length > 254) return false;
  return EMAIL_RE.test(value);
}

export function normalizeEmail(value: string): string {
  return value.trim().toLowerCase();
}
