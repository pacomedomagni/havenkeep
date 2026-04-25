import crypto from 'crypto';
import { config } from '../config';

/**
 * AES-256-GCM helper for encrypting OAuth refresh and access tokens at rest in
 * `user_oauth_integrations`. The 32-byte key is derived from
 * `config.oauthEncryptionSecret` via SHA-256 — the secret itself is opaque
 * length, so we hash it to a fixed 32-byte AES-256 key.
 *
 * Storage format (matches migration 038):
 *   - ciphertext: base64 string
 *   - iv:         base64 of 12 random bytes (24-char base64 fits CHAR(24))
 *   - tag:        base64 of the 16-byte GCM auth tag (24-char base64)
 */

export interface EncryptedToken {
  ciphertext: string;
  iv: string;
  tag: string;
}

const ALGO = 'aes-256-gcm';
const IV_BYTES = 12;

let cachedKey: Buffer | null = null;
let cachedKeyFor: string | null = null;

function getKey(): Buffer {
  const secret = config.oauthEncryptionSecret;
  if (!secret) {
    throw new Error('OAuth encryption secret is not configured');
  }
  if (cachedKey && cachedKeyFor === secret) return cachedKey;
  cachedKey = crypto.createHash('sha256').update(secret, 'utf8').digest();
  cachedKeyFor = secret;
  return cachedKey;
}

export function isOAuthEncryptionConfigured(): boolean {
  return !!config.oauthEncryptionSecret;
}

export function encryptToken(plaintext: string): EncryptedToken {
  if (!plaintext) {
    throw new Error('Cannot encrypt empty token');
  }
  const key = getKey();
  const iv = crypto.randomBytes(IV_BYTES);
  const cipher = crypto.createCipheriv(ALGO, key, iv);
  const enc = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();

  return {
    ciphertext: enc.toString('base64'),
    iv: iv.toString('base64'),
    tag: tag.toString('base64'),
  };
}

export function decryptToken(payload: EncryptedToken): string {
  const key = getKey();
  // The schema uses CHAR(24) for the IV/tag columns, which Postgres
  // right-pads with spaces. Trim before base64 decoding so the round-trip
  // matches what the cipher expects.
  const iv = Buffer.from(payload.iv.trim(), 'base64');
  const tag = Buffer.from(payload.tag.trim(), 'base64');
  const ciphertext = Buffer.from(payload.ciphertext, 'base64');

  const decipher = crypto.createDecipheriv(ALGO, key, iv);
  decipher.setAuthTag(tag);
  const dec = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  return dec.toString('utf8');
}
