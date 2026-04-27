import crypto from 'crypto';

// Pre-hash a password to defang bcrypt's 72-byte truncation (Ch01-F005).
// bcrypt(SHA-256(password) base64-encoded) gives a fixed 44-char input that
// uses the full keyspace of the original password. The slice(0,72) is a
// belt-and-suspenders cap so bcrypt's internal limit is never reached even
// if the implementation changes.
export function preHashForBcrypt(password: string): string {
  return crypto.createHash('sha256').update(password, 'utf8').digest('base64').slice(0, 72);
}
