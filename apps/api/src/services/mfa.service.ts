import crypto from 'crypto';
import { OTP } from 'otplib';
import { NobleCryptoPlugin } from '@otplib/plugin-crypto-noble';
import { ScureBase32Plugin } from '@otplib/plugin-base32-scure';
import qrcode from 'qrcode';
import { pool } from '../db';
import { config } from '../config';
import { logger } from '../utils/logger';
import { AppError } from '../utils/errors';
import { encryptToken, decryptToken, isOAuthEncryptionConfigured, currentKeyVersion } from '../utils/oauth-encryption';

/**
 * H22: AAD for MFA factor ciphertexts. Binding the TOTP secret to
 * (user_id, factor_type) means a row swap fails GCM verification —
 * an attacker with DB write can't move a known-working factor onto
 * another user's row.
 */
function mfaFactorAad(userId: string, factorType: string): string {
  return `${userId}|${factorType}`;
}
import { hashToken } from '../utils/token-hash';

/**
 * S-C2 (audit): TOTP enrollment + login challenge.
 *
 * Storage:
 *  - user_mfa_factors holds AES-256-GCM-encrypted base32 secrets. The
 *    encryption helper is shared with user_oauth_integrations
 *    (utils/oauth-encryption.ts) — same OAUTH_TOKEN_ENCRYPTION_SECRET
 *    drives both. A factor is `verified` only after the user submits a
 *    correct code; un-verified factors are never honored at login (one-
 *    step enrollment-and-login would let an attacker who already has
 *    the password enroll their own factor and complete the loop).
 *  - user_mfa_backup_codes holds keyed-HMAC code hashes. Single-use.
 *
 * RFC 6238 + window=1 (current step ± 1) for clock skew tolerance.
 *
 * MFA challenge token:
 *  - Short-lived JWT (5 min) bearing { userId, mfaPending: true }.
 *  - Can ONLY exchange for an access token via /auth/mfa/challenge.
 *  - Mints in /auth/login when the user has any verified factor.
 */

// 5 min — long enough for a user to open their authenticator app, short
// enough to bound replay if the challenge token leaks.
const CHALLENGE_TTL_SECONDS = 5 * 60;

// 15 min — span of a typical "I clicked the wrong button, let me undo"
// recovery flow. The token's only consumer is POST /users/me/recover; it
// dies after one successful recover or after 15 min, whichever comes
// first. Short enough that a leaked token can't be sat on through the
// 30-day grace window.
const ACCOUNT_RECOVER_TTL_SECONDS = 15 * 60;

// 10 backup codes minted at enrollment. Single-use. Format:
// 4 groups of 4 hex chars (e.g. "ab12-cd34-ef56-7890") — easy to type
// out of a recovery doc.
const BACKUP_CODE_COUNT = 10;
const BACKUP_CODE_BYTES = 8;

// otplib v13 OTP class — TOTP strategy, RFC 6238 defaults (6 digits, 30s
// step, SHA-1). The plugins are factories — call them to materialize
// concrete CryptoPlugin / Base32Plugin instances. NobleCryptoPlugin gives
// us the HMAC primitives; ScureBase32Plugin gives us secret encode/
// decode without an extra dep.
const totp = new OTP({
  strategy: 'totp',
  crypto: new NobleCryptoPlugin(),
  base32: new ScureBase32Plugin(),
});

// ±30s clock-skew tolerance — equivalent to the legacy window=1 setting.
// One full step on each side; the canonical choice that trades minimal
// security for typical user-clock drift.
const TOTP_TOLERANCE_SECONDS = 30;

export interface EnrollResult {
  factorId: string;
  secret: string;
  otpauthUrl: string;
  qrCodeDataUrl: string;
  backupCodes: string[];
}

export interface MfaStatus {
  hasVerifiedFactor: boolean;
  factorTypes: string[];
}

function formatBackupCode(bytes: Buffer): string {
  // 8 bytes -> 16 hex chars -> 4 groups of 4. Hyphenated for readability.
  const hex = bytes.toString('hex');
  return `${hex.slice(0, 4)}-${hex.slice(4, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}`;
}

function normalizeBackupCode(input: string): string {
  // Accept variants the user might type: with hyphens, without, with
  // spaces, mixed case. Canonical form is lowercase hex with no separators
  // — that's what we hash.
  return input.replace(/[\s-]/g, '').toLowerCase();
}

/**
 * Build a challenge JWT that /auth/mfa/challenge consumes. Uses the same
 * jwt.sign / verify primitives as access tokens but with a short TTL
 * and a distinct `purpose` claim so an access token can't masquerade
 * as a challenge token (and vice versa).
 */
export function mintMfaChallengeToken(userId: string): string {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const jwt = require('jsonwebtoken') as typeof import('jsonwebtoken');
  return jwt.sign(
    { userId, purpose: 'mfa_challenge' },
    config.jwt.secret,
    {
      algorithm: 'HS256',
      expiresIn: CHALLENGE_TTL_SECONDS,
      issuer: config.jwt.issuer,
      audience: config.jwt.audience,
    },
  );
}

export function verifyMfaChallengeToken(token: string): { userId: string } {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const jwt = require('jsonwebtoken') as typeof import('jsonwebtoken');
  const decoded = jwt.verify(token, config.jwt.secret, {
    algorithms: ['HS256'],
    issuer: config.jwt.issuer,
    audience: config.jwt.audience,
  }) as { userId?: string; purpose?: string };
  if (decoded.purpose !== 'mfa_challenge' || typeof decoded.userId !== 'string') {
    throw new AppError('Invalid MFA challenge token', 401);
  }
  return { userId: decoded.userId };
}

/**
 * C0-15: account-recovery token. Same JWT primitives as the MFA challenge
 * token; distinct `purpose: 'account_recover'` so the authenticate
 * middleware can refuse it everywhere except POST /users/me/recover.
 *
 * Minted by /auth/login (+ OAuth handlers) when a soft-deleted user
 * within the 30-day grace window re-authenticates. The user's original
 * (pre-delete) access token has already been invalidated by the
 * soft-delete blacklist, so without this token the user has no
 * authenticated path to cancel the deletion.
 */
export function mintAccountRecoverToken(userId: string): string {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const jwt = require('jsonwebtoken') as typeof import('jsonwebtoken');
  return jwt.sign(
    { userId, purpose: 'account_recover' },
    config.jwt.secret,
    {
      algorithm: 'HS256',
      expiresIn: ACCOUNT_RECOVER_TTL_SECONDS,
      issuer: config.jwt.issuer,
      audience: config.jwt.audience,
    },
  );
}

export class MfaService {
  /** Returns whether the user has any verified MFA factor. */
  static async getStatus(userId: string): Promise<MfaStatus> {
    const result = await pool.query<{ factor_type: string }>(
      `SELECT factor_type FROM user_mfa_factors
        WHERE user_id = $1 AND verified_at IS NOT NULL`,
      [userId],
    );
    return {
      hasVerifiedFactor: result.rows.length > 0,
      factorTypes: result.rows.map((r) => r.factor_type),
    };
  }

  /**
   * Begin TOTP enrollment. Generates a fresh base32 secret + otpauth URL
   * + QR-code data URL + backup codes. Persists the factor in
   * un-verified state (verified_at NULL) and the backup codes hashed.
   *
   * The unverified factor is overwritten on every enrollment call so a
   * user can re-roll mid-flow (e.g. switched apps without scanning the
   * first QR). The verified-factor unique index allows one un-verified
   * row to coexist alongside zero verified rows.
   */
  static async enrollTotp(
    userId: string,
    accountLabel: string,
  ): Promise<EnrollResult> {
    if (!isOAuthEncryptionConfigured()) {
      throw new AppError('MFA storage is not configured (encryption secret missing)', 503);
    }

    const secret = totp.generateSecret(); // base32, 160 bits
    const issuer = 'HavenKeep';
    const otpauthUrl = totp.generateURI({ issuer, label: accountLabel, secret });
    const qrCodeDataUrl = await qrcode.toDataURL(otpauthUrl);

    const encrypted = encryptToken(secret, mfaFactorAad(userId, 'totp'));
    const keyVer = currentKeyVersion();

    // Mint backup codes BEFORE the transaction commits so a partial failure
    // doesn't leave a factor in place with no recovery path.
    const backupPlaintexts: string[] = [];
    const backupHashes: string[] = [];
    for (let i = 0; i < BACKUP_CODE_COUNT; i++) {
      const code = formatBackupCode(crypto.randomBytes(BACKUP_CODE_BYTES));
      backupPlaintexts.push(code);
      backupHashes.push(hashToken(normalizeBackupCode(code)));
    }

    const client = await pool.connect();
    let factorId: string;
    try {
      await client.query('BEGIN');

      // Drop any unverified factor + previously-issued backup codes so
      // a user re-enrolling doesn't accumulate.
      await client.query(
        `DELETE FROM user_mfa_factors
          WHERE user_id = $1 AND factor_type = 'totp' AND verified_at IS NULL`,
        [userId],
      );
      await client.query(
        `DELETE FROM user_mfa_backup_codes
          WHERE user_id = $1 AND used_at IS NULL`,
        [userId],
      );

      const inserted = await client.query<{ id: string }>(
        `INSERT INTO user_mfa_factors
           (user_id, factor_type, secret_ciphertext, secret_iv, secret_tag, label, key_version)
         VALUES ($1, 'totp', $2, $3, $4, $5, $6)
         RETURNING id`,
        [userId, encrypted.ciphertext, encrypted.iv, encrypted.tag, accountLabel, keyVer],
      );
      factorId = inserted.rows[0].id;

      for (const hash of backupHashes) {
        await client.query(
          `INSERT INTO user_mfa_backup_codes (user_id, code_hash) VALUES ($1, $2)`,
          [userId, hash],
        );
      }

      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      throw err;
    } finally {
      client.release();
    }

    return {
      factorId,
      secret,
      otpauthUrl,
      qrCodeDataUrl,
      backupCodes: backupPlaintexts,
    };
  }

  /**
   * Verify a TOTP code against the user's un-verified factor and flip
   * it to verified. Required before the factor counts at login.
   * Returns true on success, throws on failure.
   */
  static async verifyEnrollmentCode(userId: string, code: string): Promise<void> {
    const factor = await pool.query<{
      id: string;
      secret_ciphertext: string;
      secret_iv: string;
      secret_tag: string;
      key_version: number | null;
    }>(
      `SELECT id, secret_ciphertext, secret_iv, secret_tag, key_version
         FROM user_mfa_factors
        WHERE user_id = $1 AND factor_type = 'totp' AND verified_at IS NULL`,
      [userId],
    );
    if (factor.rows.length === 0) {
      throw new AppError('No pending MFA enrollment found', 404);
    }
    const row = factor.rows[0];
    const secret = decryptToken(
      {
        ciphertext: row.secret_ciphertext,
        iv: row.secret_iv,
        tag: row.secret_tag,
        keyVersion: row.key_version ?? undefined,
      },
      mfaFactorAad(userId, 'totp'),
    );
    const result = totp.verifySync({
      token: code,
      secret,
      epochTolerance: TOTP_TOLERANCE_SECONDS,
    });
    if (!result.valid) {
      throw new AppError('Invalid verification code', 400);
    }

    await pool.query(
      `UPDATE user_mfa_factors SET verified_at = NOW() WHERE id = $1`,
      [row.id],
    );
  }

  /**
   * Verify a TOTP code OR backup code at login challenge. Returns true
   * on success and CONSUMES the backup code if that was the path used.
   * Throws AppError on failure.
   */
  static async verifyChallengeCode(userId: string, code: string): Promise<void> {
    const trimmed = code.trim();
    // Detect backup code by shape (hex with optional separators). TOTP is
    // always 6 digits per RFC 6238 + our authenticator config.
    const isBackup = !/^\d{6}$/.test(trimmed);

    if (isBackup) {
      const normalized = normalizeBackupCode(trimmed);
      const hash = hashToken(normalized);
      const consumed = await pool.query(
        `UPDATE user_mfa_backup_codes
            SET used_at = NOW()
          WHERE user_id = $1 AND code_hash = $2 AND used_at IS NULL
          RETURNING id`,
        [userId, hash],
      );
      if (consumed.rows.length === 0) {
        throw new AppError('Invalid or already-used backup code', 400);
      }
      return;
    }

    // TOTP path
    const factor = await pool.query<{
      secret_ciphertext: string;
      secret_iv: string;
      secret_tag: string;
      key_version: number | null;
    }>(
      `SELECT secret_ciphertext, secret_iv, secret_tag, key_version
         FROM user_mfa_factors
        WHERE user_id = $1 AND factor_type = 'totp' AND verified_at IS NOT NULL
        LIMIT 1`,
      [userId],
    );
    if (factor.rows.length === 0) {
      // Defense-in-depth: caller should already have routed past MFA
      // for users with no verified factor. Surface a clean 400.
      throw new AppError('No verified MFA factor on file', 400);
    }
    const row = factor.rows[0];
    const secret = decryptToken(
      {
        ciphertext: row.secret_ciphertext,
        iv: row.secret_iv,
        tag: row.secret_tag,
        keyVersion: row.key_version ?? undefined,
      },
      mfaFactorAad(userId, 'totp'),
    );
    const result = totp.verifySync({
      token: trimmed,
      secret,
      epochTolerance: TOTP_TOLERANCE_SECONDS,
    });
    if (!result.valid) {
      throw new AppError('Invalid verification code', 400);
    }
  }

  /**
   * Disable an MFA factor. Requires either a current TOTP code or an
   * unused backup code so an attacker who has the password alone can't
   * remove the second factor.
   */
  static async disableTotp(userId: string, code: string): Promise<void> {
    await this.verifyChallengeCode(userId, code);
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        `DELETE FROM user_mfa_factors WHERE user_id = $1 AND factor_type = 'totp'`,
        [userId],
      );
      await client.query(
        `DELETE FROM user_mfa_backup_codes WHERE user_id = $1`,
        [userId],
      );
      await client.query('COMMIT');
      logger.info({ userId }, 'TOTP factor disabled');
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      throw err;
    } finally {
      client.release();
    }
  }
}
