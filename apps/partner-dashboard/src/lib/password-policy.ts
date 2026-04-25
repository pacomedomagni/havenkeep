/**
 * Single source of truth for password complexity, shared between signup and
 * reset-password. Mirrors the backend's `validatePassword` rule so the
 * dashboard's reset flow doesn't accept weaker passwords than signup
 * (audit Ch10-W018).
 */
export interface PasswordPolicyResult {
  ok: boolean;
  reason?: string;
}

const MIN_LENGTH = 8;
const MAX_LENGTH = 72; // bcrypt's effective limit
const SPECIAL_RE = /[!@#$%^&*()_\-+=\[\]{};:'",.<>/?\\|`~]/;

export function validatePassword(password: unknown): PasswordPolicyResult {
  if (typeof password !== 'string' || password.length === 0) {
    return { ok: false, reason: 'Password is required' };
  }
  if (password.length < MIN_LENGTH) {
    return { ok: false, reason: `Password must be at least ${MIN_LENGTH} characters` };
  }
  if (password.length > MAX_LENGTH) {
    return { ok: false, reason: `Password must be at most ${MAX_LENGTH} characters` };
  }
  if (!/[a-z]/.test(password)) {
    return { ok: false, reason: 'Password must contain a lowercase letter' };
  }
  if (!/[A-Z]/.test(password)) {
    return { ok: false, reason: 'Password must contain an uppercase letter' };
  }
  if (!/\d/.test(password)) {
    return { ok: false, reason: 'Password must contain a digit' };
  }
  if (!SPECIAL_RE.test(password)) {
    return { ok: false, reason: 'Password must contain a special character' };
  }
  return { ok: true };
}
