import crypto from 'crypto';
import { config } from '../config';

/**
 * AES-256-GCM helper for encrypting OAuth refresh and access tokens at rest in
 * `user_oauth_integrations` and TOTP secrets in `user_mfa_factors`. The
 * 32-byte key is derived from the configured secret(s) via SHA-256.
 *
 * Storage format (matches migration 038 + 109):
 *   - ciphertext:  base64 string
 *   - iv:          base64 of 12 random bytes (24-char base64 fits CHAR(24))
 *   - tag:         base64 of the 16-byte GCM auth tag (24-char base64)
 *   - keyVersion:  small integer; persisted in the same row so a future
 *                  rotation sweep can `WHERE key_version < N`.
 *
 * H22: optional AAD (additional authenticated data) binds the ciphertext
 * to the row it lives in. Without AAD, an attacker with DB-write access
 * could swap an encrypted token from row A onto row B and decrypt as
 * user B. With AAD = `${userId}|${provider}|${providerEmail}` (or
 * whatever uniquely identifies the row), tampering produces a GCM
 * auth-tag mismatch and decrypt fails.
 *
 * Key rotation: encryptToken always returns `keyVersion = CURRENT_KEY_VERSION`.
 * decryptToken accepts a candidate `keyVersion`; the helper picks the
 * matching key from the (primary + legacy) chain. Without that, decrypt
 * blindly walks every key until one validates — works, but doesn't tell
 * us when the legacy list can be retired.
 */

export interface EncryptedToken {
  ciphertext: string;
  iv: string;
  tag: string;
  /**
   * Optional on read for forward-compat with rows persisted before
   * mig 109. New encrypts always populate it. When absent on decrypt,
   * the helper walks every candidate key as before.
   */
  keyVersion?: number;
}

const ALGO = 'aes-256-gcm';
const IV_BYTES = 12;

// Current encryption-key version. Bump in lockstep with adding the
// new primary secret + moving the previous primary into the legacy
// list. The DB column defaults to 1 so the initial state is
// self-consistent.
const CURRENT_KEY_VERSION = 1;

const keyCache = new Map<string, Buffer>();

function deriveKey(secret: string): Buffer {
  const cached = keyCache.get(secret);
  if (cached) return cached;
  const key = crypto.createHash('sha256').update(secret, 'utf8').digest();
  keyCache.set(secret, key);
  return key;
}

function getPrimaryKey(): Buffer {
  const secret = config.oauthEncryptionSecret;
  if (!secret) {
    throw new Error('OAuth encryption secret is not configured');
  }
  return deriveKey(secret);
}

interface VersionedKey {
  key: Buffer;
  version: number;
}

/**
 * Returns the candidate keys in (version, key) form. Today the primary
 * key is always version=CURRENT_KEY_VERSION; legacy keys get a sentinel
 * version of 0 because we can't enumerate which past version each one
 * was — rotation flow re-encrypts everything to CURRENT before the
 * legacy entry would matter.
 */
function getCandidateKeys(): VersionedKey[] {
  const out: VersionedKey[] = [{ key: getPrimaryKey(), version: CURRENT_KEY_VERSION }];
  for (const legacy of config.oauthEncryptionSecretsLegacy ?? []) {
    if (legacy && legacy !== config.oauthEncryptionSecret) {
      out.push({ key: deriveKey(legacy), version: 0 });
    }
  }
  return out;
}

export function isOAuthEncryptionConfigured(): boolean {
  return !!config.oauthEncryptionSecret;
}

export function currentKeyVersion(): number {
  return CURRENT_KEY_VERSION;
}

/**
 * @param aad Optional additional-authenticated-data bound to the
 *   ciphertext via setAAD. Must be supplied unchanged on decrypt — if
 *   the AAD differs by even one byte, the GCM auth tag check fails.
 *   Pass a row-identifying string like `${userId}|${provider}`.
 */
export function encryptToken(plaintext: string, aad?: string): EncryptedToken {
  if (!plaintext) {
    throw new Error('Cannot encrypt empty token');
  }
  const key = getPrimaryKey();
  const iv = crypto.randomBytes(IV_BYTES);
  const cipher = crypto.createCipheriv(ALGO, key, iv);
  if (aad) cipher.setAAD(Buffer.from(aad, 'utf8'));
  const enc = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();

  return {
    ciphertext: enc.toString('base64'),
    iv: iv.toString('base64'),
    tag: tag.toString('base64'),
    keyVersion: CURRENT_KEY_VERSION,
  };
}

/**
 * @param aad Must match the AAD passed to encryptToken for this row.
 *   Absence on read after presence on write yields a GCM mismatch.
 */
export function decryptToken(payload: EncryptedToken, aad?: string): string {
  // The schema uses CHAR(24) for the IV/tag columns, which Postgres
  // right-pads with spaces. Trim before base64 decoding so the round-trip
  // matches what the cipher expects.
  const iv = Buffer.from(payload.iv.trim(), 'base64');
  const tag = Buffer.from(payload.tag.trim(), 'base64');
  const ciphertext = Buffer.from(payload.ciphertext, 'base64');

  // H23: when keyVersion is present try that key first; otherwise walk
  // every candidate as before. The walk preserves the older behavior
  // for any row written before mig 109 / without a stored version.
  const allCandidates = getCandidateKeys();
  const ordered = payload.keyVersion
    ? [
        ...allCandidates.filter((c) => c.version === payload.keyVersion),
        ...allCandidates.filter((c) => c.version !== payload.keyVersion),
      ]
    : allCandidates;

  let lastErr: unknown;
  for (const { key } of ordered) {
    try {
      const decipher = crypto.createDecipheriv(ALGO, key, iv);
      decipher.setAuthTag(tag);
      if (aad) decipher.setAAD(Buffer.from(aad, 'utf8'));
      const dec = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
      return dec.toString('utf8');
    } catch (err) {
      lastErr = err;
    }
  }
  throw lastErr ?? new Error('OAuth token decryption failed');
}
