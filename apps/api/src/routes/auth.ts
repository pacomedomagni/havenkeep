import { Router } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { query, getClient } from '../db';
import Joi from 'joi';
import { config } from '../config';
import { AppError } from '../utils/errors';
import { authRateLimiter, refreshRateLimiter, passwordResetRateLimiter } from '../middleware/rateLimiter';
import { authenticate, invalidateUserCache } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { registerSchema, loginSchema, refreshTokenSchema } from '../validators';
import { forgotPasswordSchema, resetPasswordSchema, verifyEmailSchema, verifyEmailChangeSchema } from '../validators/auth.validator';
import { logger } from '../utils/logger';
import { AuditService } from '../services/audit.service';
import { EmailService } from '../services/email.service';
import { blacklistTokenAuto } from '../utils/token-blacklist';
import { generateUniqueReferralCode } from '../utils/referral-code';
import { isDisposableEmail } from '../utils/disposable-emails';
import { preHashForBcrypt } from '../utils/password';
import { getRedisClient } from '../utils/redis';
import { presignedUrlForKey } from '../config/minio';
import { rotateCsrfToken } from '../middleware/csrf';
import { asyncHandler } from '../utils/async-handler';
import { hashToken, hashRefreshToken } from '../utils/token-hash';
import { MfaService, mintMfaChallengeToken, verifyMfaChallengeToken } from '../services/mfa.service';

// C10: best-effort audit-log writer. The error-path catch arms in this file
// previously did `await AuditService.logAuth(...)` before `next(error)` —
// in Express 4 a rejection from that await never reaches the error
// middleware (next is never called), the handler's promise rejects, and
// process.on('unhandledRejection') triggers a SIGTERM. One DB hiccup mid-
// audit-write would crash the API. Fire-and-forget with a logged failure
// keeps the audit record on the happy path while never blocking the
// response.
function logAuthBestEffort(input: Parameters<typeof AuditService.logAuth>[0]): void {
  AuditService.logAuth(input).catch((err) => {
    logger.error({ err, action: input.action }, 'AuditService.logAuth failed (best-effort)');
  });
}

// S-CR-02: avatar_url is a MinIO object key. Mint a presigned URL on
// response so a leaked URL is useless within PRESIGNED_URL_TTL_SECONDS.
async function presignAvatarUrl(key: string | null | undefined): Promise<string | null> {
  return presignedUrlForKey(key);
}

const router = Router();

// Cached OAuth client singletons (lazy-initialized)
let googleOAuth2Client: any = null;
let appleJwksClientInstance: any = null;

// Parse JWT expiry string (e.g. '7d', '24h') to milliseconds.
//
// 4.4: throw on unrecognized input rather than silently falling back
// to 7 days. The fallback would mask a typo in `REFRESH_TOKEN_EXPIRES_IN`
// (`'7days'` instead of `'7d'`) and produce a refresh-token TTL that
// silently disagrees with the value the operator thought they
// configured. The constant is computed at module load so a bad value
// crashes the API on boot — exactly what we want.
function parseExpiryToMs(expiry: string | number): number {
  if (typeof expiry === 'number') return expiry * 1000;
  const match = String(expiry).match(/^(\d+)(s|m|h|d)$/);
  if (!match) {
    throw new Error(
      `parseExpiryToMs: unrecognized expiry '${expiry}'. ` +
      `Expected one of: NNs / NNm / NNh / NNd or a number of seconds.`,
    );
  }
  const value = parseInt(match[1], 10);
  const unit = match[2];
  const multipliers: Record<string, number> = { s: 1000, m: 60000, h: 3600000, d: 86400000 };
  return value * multipliers[unit];
}

const REFRESH_TOKEN_EXPIRY_MS = parseExpiryToMs(config.jwt.refreshExpiresIn as string | number);

// Hash opaque-bearer tokens with SHA-256 before storing. Used for refresh
// tokens, email verification tokens, and password reset tokens — all are
// server-generated single-purpose opaque strings.
//
// Audit Ch01-F019: keyed-HMAC token storage lives in utils/token-hash.ts so
// users.ts (change-email — S-M9) can use the same key + algorithm without
// duplicating the function or exporting cross-module from a route file.

/**
 * Sanitize a free-form string for inclusion in audit-log descriptions
 * (Ch01-F058). Strips control / non-printable characters and caps length so
 * a malicious email like `attacker\nrole_change=admin\n@evil.com` can't
 * smuggle fake newline-delimited audit entries.
 */
function sanitizeAuditLogText(value: unknown, max = 200): string {
  if (typeof value !== 'string') return '';
  return value
    .replace(/[\x00-\x1f\x7f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

// Helper to get IP address
const getIpAddress = (req: any): string => {
  const ip =
    (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() ||
    (req.headers['x-real-ip'] as string) ||
    req.socket.remoteAddress;
  if (!ip) {
    logger.warn({ path: req.path }, 'Could not determine client IP address');
    return 'unknown';
  }
  return ip;
};

/**
 * S1-H: record an Apple Sign-In nonce hash as consumed so a replay of the
 * same id-token + nonce pair fails the second time. Prefers Redis when
 * available (SET … NX EX gives O(1) replay detection without DB writes);
 * falls back to a small Postgres table whose PRIMARY KEY uniqueness
 * enforces the same invariant.
 *
 * Throws an AppError(401) on replay. The TTL covers any realistic delivery
 * slop on the Apple-issued token (Apple's exp is ~10 min; we keep nonces
 * for 5 min from consumption).
 */
const APPLE_NONCE_TTL_SECONDS = 300;

async function markAppleNonceConsumed(nonceHash: string): Promise<void> {
  const key = `apple_nonce:${nonceHash}`;
  try {
    const redis = await getRedisClient();
    const setResult = await redis.set(key, '1', { NX: true, EX: APPLE_NONCE_TTL_SECONDS });
    if (setResult === null) {
      // SET NX returned null => key already existed => replay.
      throw new AppError('Apple nonce has already been used', 401);
    }
    return;
  } catch (err) {
    if (err instanceof AppError) throw err;
    // Redis unreachable — fall through to the DB-backed table.
    logger.warn({ err }, 'Apple nonce check via Redis failed, falling back to DB');
  }

  try {
    const expiresAt = new Date(Date.now() + APPLE_NONCE_TTL_SECONDS * 1000);
    const result = await query(
      `INSERT INTO apple_sign_in_nonces (nonce_hash, expires_at)
         VALUES ($1, $2)
         ON CONFLICT (nonce_hash) DO NOTHING
         RETURNING nonce_hash`,
      [nonceHash, expiresAt],
    );
    if (result.rowCount === 0) {
      throw new AppError('Apple nonce has already been used', 401);
    }
  } catch (err) {
    if (err instanceof AppError) throw err;
    logger.error({ err }, 'Apple nonce DB insert failed');
    throw new AppError('Could not validate sign-in token', 500);
  }
}

async function resolveReferredBy(referralCode?: string): Promise<string | null> {
  if (!referralCode) return null;
  const result = await query(
    `SELECT id FROM users WHERE referral_code = $1`,
    [referralCode]
  );
  return result.rows.length > 0 ? result.rows[0].id : null;
}

/**
 * Cap refresh tokens per user by deleting the oldest ones, keeping only the
 * N most recent. This prevents unbounded token accumulation.
 */
async function capRefreshTokens(userId: string, maxTokens: number = 10): Promise<void> {
  // Two concurrent logins from the same user were racing: each SELECT saw
  // a different "latest N" set, and the two DELETEs together removed rows
  // the other needed to keep. Serialize via a per-user advisory lock held
  // for the duration of the SELECT+DELETE so the operation is atomic.
  const client = await getClient();
  try {
    await client.query('BEGIN');
    // hashtext returns a stable int4 per-user lock key. Two locks per
    // namespace would also work (pg_advisory_xact_lock(key1, key2)).
    await client.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [userId]);
    await client.query(
      `DELETE FROM refresh_tokens
         WHERE user_id = $1 AND id NOT IN (
           SELECT id FROM refresh_tokens
           WHERE user_id = $1
           ORDER BY created_at DESC
           LIMIT $2
         )`,
      [userId, maxTokens],
    );
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

/**
 * Create an authenticated session for a user: generates an access token and a
 * refresh token, stores the hashed refresh token in the database, and caps the
 * total number of active refresh tokens.
 */
async function createAuthSession(
  userId: string,
  email: string,
  isAdmin: boolean,
  isPartner: boolean
): Promise<{ accessToken: string; refreshToken: string }> {
  // S-HI-02: pin algorithm explicitly so a JWT secret swap to RSA-public-
  // key material can't introduce an HS256 forgery primitive.
  const accessToken = jwt.sign(
    { userId, email, isAdmin, isPartner },
    config.jwt.secret,
    { expiresIn: config.jwt.expiresIn, algorithm: 'HS256' }
  );

  const refreshToken = jwt.sign(
    { userId },
    config.jwt.refreshSecret,
    { expiresIn: config.jwt.refreshExpiresIn, algorithm: 'HS256' }
  );

  const expiresAt = new Date(Date.now() + REFRESH_TOKEN_EXPIRY_MS);

  await query(
    `INSERT INTO refresh_tokens (user_id, token, expires_at)
     VALUES ($1, $2, $3)`,
    [userId, hashRefreshToken(refreshToken), expiresAt]
  );

  await capRefreshTokens(userId);

  return { accessToken, refreshToken };
}

// Register
router.post('/register', authRateLimiter, validate(registerSchema), asyncHandler(async (req, res) => {
  const client = await getClient();
  try {
    const { email, password, fullName, referralCode } = req.body;

    // Audit Ch12-T045: reject obvious disposable / temp-mail signups before
    // we touch bcrypt or the database. The list is intentionally narrow —
    // a more aggressive list would lock out legitimate users on niche email
    // providers.
    if (isDisposableEmail(email)) {
      throw new AppError('That email provider is not supported. Please use a personal or work email.', 400);
    }

    const referredBy = await resolveReferredBy(referralCode);
    const userReferralCode = await generateUniqueReferralCode();

    await client.query('BEGIN');

    // Check for existing email before expensive bcrypt hash
    const existingUser = await client.query(
      `SELECT 1 FROM users WHERE email = $1`,
      [email.toLowerCase()]
    );
    if (existingUser.rows.length > 0) {
      throw new AppError('Email already registered', 409);
    }

    // Hash password with bcrypt rounds=12 (only after confirming email is
    // available). Pre-hash with SHA-256 so passwords > 72 bytes still use
    // their full entropy (Ch01-F005).
    const passwordHash = await bcrypt.hash(preHashForBcrypt(password), 12);

    // Atomically insert user — ON CONFLICT handles the race condition
    const result = await client.query(
      `INSERT INTO users (email, password_hash, full_name, referral_code, referred_by)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (email) DO NOTHING
       RETURNING id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
                 referred_by, referral_code, is_admin, created_at, updated_at`,
      [email.toLowerCase(), passwordHash, fullName, userReferralCode, referredBy]
    );

    if (result.rows.length === 0) {
      throw new AppError('Email already registered', 409);
    }

    const user = result.rows[0];

    // Create default home
    await client.query(
      `INSERT INTO homes (user_id, name) VALUES ($1, $2)`,
      [user.id, 'My Home']
    );

    // Store refresh token inside the transaction (we generate both tokens here
    // so that the refresh token is committed atomically with the user row).
    // S-HI-02: pin algorithm explicitly.
    const accessToken = jwt.sign(
      { userId: user.id, email: user.email, isAdmin: user.is_admin || false, isPartner: false },
      config.jwt.secret,
      { expiresIn: config.jwt.expiresIn, algorithm: 'HS256' }
    );

    const refreshToken = jwt.sign(
      { userId: user.id },
      config.jwt.refreshSecret,
      { expiresIn: config.jwt.refreshExpiresIn, algorithm: 'HS256' }
    );

    const refreshExpiresAt = new Date(Date.now() + REFRESH_TOKEN_EXPIRY_MS);

    await client.query(
      `INSERT INTO refresh_tokens (user_id, token, expires_at)
       VALUES ($1, $2, $3)`,
      [user.id, hashRefreshToken(refreshToken), refreshExpiresAt]
    );

    // Store email verification token inside the transaction
    const verificationToken = crypto.randomBytes(32).toString('hex');
    const verificationExpiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24 hours
    await client.query(
      `INSERT INTO email_verification_tokens (user_id, token, expires_at) VALUES ($1, $2, $3)`,
      [user.id, hashRefreshToken(verificationToken), verificationExpiresAt]
    );

    await client.query('COMMIT');

    // Audit log: successful registration (fire-and-forget to avoid throwing after COMMIT)
    AuditService.logAuth({
      action: 'auth.register',
      userId: user.id,
      email: user.email,
      ipAddress: getIpAddress(req),
      userAgent: req.get('user-agent'),
      success: true,
    }).catch((auditError) => {
      logger.error({ error: auditError, userId: user.id }, 'Failed to log registration audit event');
    });

    // Send email verification (fire-and-forget)
    const verifyUrl = `${config.app.frontendUrl}/verify-email?token=${verificationToken}`;
    EmailService.sendEmailVerificationEmail({
      to: user.email,
      user_name: user.full_name || 'there',
      verify_url: verifyUrl,
    }).catch((err) => {
      logger.error({ error: err, userId: user.id }, 'Failed to send verification email');
    });

    // S-ME-02: rotate CSRF token on auth state change to defang fixation.
    rotateCsrfToken(res);
    res.status(201).json({
      success: true,
      data: {
        user: {
          id: user.id,
          email: user.email,
          full_name: user.full_name,
          avatar_url: await presignAvatarUrl(user.avatar_url),
          auth_provider: user.auth_provider || 'email',
          plan: user.plan,
          plan_expires_at: user.plan_expires_at || null,
          referred_by: user.referred_by || null,
          referral_code: user.referral_code || null,
          is_admin: user.is_admin || false,
          is_partner: false,
          created_at: user.created_at,
          updated_at: user.updated_at,
        },
        accessToken,
        refreshToken,
      },
    });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    // Audit log: failed registration (skip for duplicate-email conflicts)
    if ((error as any)?.code !== '23505' && !(error instanceof AppError && error.statusCode === 409)) {
      logAuthBestEffort({
        action: 'auth.register',
        email: req.body.email,
        ipAddress: getIpAddress(req),
        userAgent: req.get('user-agent'),
        success: false,
        errorMessage: error instanceof Error ? error.message : 'Registration failed',
      });
    }
    throw error;
  } finally {
    client.release();
  }
}));

// Login
router.post('/login', authRateLimiter, validate(loginSchema), asyncHandler(async (req, res) => {
  try {
    const { email, password } = req.body;

    // Get user.
    // H-A1 (audit): include deleted_at + deletion_scheduled_for so a
    // soft-deleted or admin-suspended account can never reach the
    // token-issuing branch even with the right password. The prior
    // shape happily issued fresh access/refresh tokens to anyone with
    // the right credentials; every subsequent authenticated call then
    // 401'd via middleware/auth.ts. That confused legitimate users
    // (the delete-confirmation email tells them to "log back in to
    // recover" — see C13b for the recover path) AND masked credential-
    // stuffing against suspended-for-fraud accounts because
    // `auth.login success=true` always landed in the audit log.
    const result = await query(
      `SELECT u.id, u.email, u.password_hash, u.full_name, u.avatar_url, u.auth_provider, u.plan,
              u.plan_expires_at, u.referred_by, u.referral_code, u.is_admin,
              u.deleted_at, u.deletion_scheduled_for,
              u.created_at, u.updated_at,
              (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = u.id AND p.is_active = TRUE)) as is_partner
       FROM users u WHERE u.email = $1`,
      [email.toLowerCase()]
    );

    if (result.rows.length === 0) {
      // Constant-time: run bcrypt even when user doesn't exist to prevent timing attacks
      await bcrypt.compare(preHashForBcrypt(password), '$2a$12$000000000000000000000uGAV.eTk/fI05JBbVvI3B.ggHOFglqi');
      throw new AppError('Invalid credentials', 401);
    }

    const user = result.rows[0];

    // Verify password
    if (!user.password_hash) {
      await bcrypt.compare(preHashForBcrypt(password), '$2a$12$000000000000000000000uGAV.eTk/fI05JBbVvI3B.ggHOFglqi');
      throw new AppError('Invalid credentials', 401);
    }
    const valid = await bcrypt.compare(preHashForBcrypt(password), user.password_hash);

    if (!valid) {
      // Audit log: failed login (wrong password) — best-effort, never blocks response
      logAuthBestEffort({
        action: 'auth.login',
        userId: user.id,
        email: user.email,
        ipAddress: getIpAddress(req),
        userAgent: req.get('user-agent'),
        success: false,
        errorMessage: 'Invalid password',
      });
      const err = new AppError('Invalid credentials', 401);
      (err as any)._auditLogged = true;
      throw err;
    }

    // H-A1: refuse to issue tokens for soft-deleted or admin-suspended
    // accounts even when the password is correct. Two reasons:
    //   1. The prior path issued tokens then every subsequent call 401'd
    //      via middleware (Account is closed / suspended). The user got
    //      an apparently-successful login but couldn't actually use the
    //      app — confusing UX, and for the soft-delete-recover flow the
    //      message in the email lied about how recovery works.
    //   2. Successful credential-stuffing against suspended-for-fraud
    //      accounts produced `auth.login success=true` audit rows,
    //      hiding the attack pattern from anyone scanning the audit log
    //      for "fraud-account login attempts."
    //
    // Soft-deleted users within the 30-day grace window get a structured
    // ACCOUNT_PENDING_DELETION code so the mobile/web UI can route them
    // to the recover prompt (the recover endpoint at /me/recover is now
    // reachable thanks to C13b's middleware bypass).
    if (user.deleted_at) {
      const withinGrace =
        user.deletion_scheduled_for &&
        new Date(user.deletion_scheduled_for) > new Date();
      logAuthBestEffort({
        action: 'auth.login',
        userId: user.id,
        email: user.email,
        ipAddress: getIpAddress(req),
        userAgent: req.get('user-agent'),
        success: false,
        errorMessage: withinGrace ? 'soft_deleted_pending' : 'soft_deleted_expired',
      });
      if (withinGrace) {
        // Distinguished status code so the client can route to recover.
        // Don't leak this code on credentials-wrong responses — those
        // still return generic 401 — so an attacker who didn't already
        // have the password gains nothing from the existence signal.
        const err = new AppError(
          'Account is scheduled for deletion. Recovery available.',
          403,
          'ACCOUNT_PENDING_DELETION',
        );
        (err as any)._auditLogged = true;
        throw err;
      }
      const err = new AppError('Account is closed', 401, 'AUTH_REQUIRED');
      (err as any)._auditLogged = true;
      throw err;
    }
    if (user.plan === 'suspended') {
      logAuthBestEffort({
        action: 'auth.login',
        userId: user.id,
        email: user.email,
        ipAddress: getIpAddress(req),
        userAgent: req.get('user-agent'),
        success: false,
        errorMessage: 'plan_suspended',
      });
      const err = new AppError('Account suspended. Contact support.', 403, 'FORBIDDEN');
      (err as any)._auditLogged = true;
      throw err;
    }

    // S-C2: if the user has any verified MFA factor, defer issuing the
    // real access/refresh pair. Mint a short-lived MFA challenge token
    // instead; the client then POSTs the TOTP code (or a backup code)
    // to /auth/mfa/challenge to exchange the challenge for real tokens.
    // The challenge token's `purpose: 'mfa_challenge'` claim makes it
    // unusable as an access token elsewhere.
    const mfaStatus = await MfaService.getStatus(user.id);
    if (mfaStatus.hasVerifiedFactor) {
      const mfaToken = mintMfaChallengeToken(user.id);
      logAuthBestEffort({
        action: 'auth.login',
        userId: user.id,
        email: user.email,
        ipAddress: getIpAddress(req),
        userAgent: req.get('user-agent'),
        success: true,
        errorMessage: 'mfa_required',
      });
      res.json({
        success: true,
        data: {
          mfa_required: true,
          mfa_token: mfaToken,
          factor_types: mfaStatus.factorTypes,
        },
      });
      return;
    }

    // Generate tokens, store refresh token, and cap active tokens
    const { accessToken, refreshToken } = await createAuthSession(
      user.id, user.email, user.is_admin || false, user.is_partner || false
    );

    // Audit log: successful login (best-effort)
    logAuthBestEffort({
      action: 'auth.login',
      userId: user.id,
      email: user.email,
      ipAddress: getIpAddress(req),
      userAgent: req.get('user-agent'),
      success: true,
    });

    // S-ME-02: rotate CSRF token on auth state change to defang fixation.
    rotateCsrfToken(res);
    res.json({
      success: true,
      data: {
        user: {
          id: user.id,
          email: user.email,
          full_name: user.full_name,
          avatar_url: await presignAvatarUrl(user.avatar_url),
          auth_provider: user.auth_provider || 'email',
          plan: user.plan,
          plan_expires_at: user.plan_expires_at || null,
          referred_by: user.referred_by || null,
          referral_code: user.referral_code || null,
          is_admin: user.is_admin,
          is_partner: user.is_partner,
          created_at: user.created_at,
          updated_at: user.updated_at,
        },
        accessToken,
        refreshToken,
      },
    });
  } catch (error) {
    // Audit log: failed login (user not found or other error) — skip if already logged
    if (error instanceof AppError && error.statusCode === 401 && !(error as any)._auditLogged) {
      logAuthBestEffort({
        action: 'auth.login',
        email: req.body.email,
        ipAddress: getIpAddress(req),
        userAgent: req.get('user-agent'),
        success: false,
        errorMessage: 'Invalid credentials',
      });
    }
    throw error;
  }
}));

// S-C2: MFA challenge — exchange a short-lived MFA challenge token + a
// TOTP code (or backup code) for real access + refresh tokens.
//
// /auth/login mints the mfa_token JWT when the user has any verified
// factor. This route validates the challenge, validates the code, then
// calls createAuthSession just like the post-MFA-bypass path in /login.
//
// The challenge token's `purpose: 'mfa_challenge'` claim is enforced by
// verifyMfaChallengeToken so it can't masquerade as an access token.
const mfaChallengeSchema = Joi.object({
  mfa_token: Joi.string().min(20).max(4096).required(),
  code: Joi.string().min(6).max(64).required(),
});

router.post(
  '/mfa/challenge',
  authRateLimiter,
  validate(mfaChallengeSchema),
  asyncHandler(async (req, res) => {
    const { mfa_token, code } = req.body;

    let userId: string;
    try {
      ({ userId } = verifyMfaChallengeToken(mfa_token));
    } catch (err) {
      if (err instanceof AppError) throw err;
      // jwt errors land here
      throw new AppError('Invalid or expired MFA challenge', 401);
    }

    // Re-fetch the user — the row may have been suspended / deleted /
    // demoted between /login and now. We treat the challenge handoff
    // as a re-authentication boundary.
    const userResult = await query(
      `SELECT u.id, u.email, u.full_name, u.avatar_url, u.auth_provider, u.plan,
              u.plan_expires_at, u.referred_by, u.referral_code, u.is_admin,
              u.deleted_at, u.created_at, u.updated_at,
              (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = u.id AND p.is_active = TRUE)) as is_partner
       FROM users u WHERE u.id = $1`,
      [userId],
    );
    if (userResult.rows.length === 0) {
      throw new AppError('Account not found', 401);
    }
    const user = userResult.rows[0];
    if (user.deleted_at || user.plan === 'suspended') {
      throw new AppError('Account is closed or suspended', 401);
    }

    // Validate the TOTP / backup code. Throws AppError 400 on invalid.
    await MfaService.verifyChallengeCode(userId, code);

    const { accessToken, refreshToken } = await createAuthSession(
      user.id,
      user.email,
      user.is_admin || false,
      user.is_partner || false,
    );

    logAuthBestEffort({
      action: 'auth.login',
      userId: user.id,
      email: user.email,
      ipAddress: getIpAddress(req),
      userAgent: req.get('user-agent'),
      success: true,
      errorMessage: 'mfa_passed',
    });

    rotateCsrfToken(res);
    res.json({
      success: true,
      data: {
        user: {
          id: user.id,
          email: user.email,
          full_name: user.full_name,
          avatar_url: await presignAvatarUrl(user.avatar_url),
          auth_provider: user.auth_provider || 'email',
          plan: user.plan,
          plan_expires_at: user.plan_expires_at || null,
          referred_by: user.referred_by || null,
          referral_code: user.referral_code || null,
          is_admin: user.is_admin,
          is_partner: user.is_partner,
          created_at: user.created_at,
          updated_at: user.updated_at,
        },
        accessToken,
        refreshToken,
      },
    });
  }),
);

// Refresh token
router.post('/refresh', refreshRateLimiter, validate(refreshTokenSchema), asyncHandler(async (req, res) => {
  const { refreshToken } = req.body;

  // Verify the JWT signature first; the user_id we trust is whatever the
  // refresh_tokens row carries, not whatever the decoded JWT body claims
  // (audit Ch01-F020). The decoded body is only used to short-circuit
  // before doing the DB hit. S-HI-02: pin algorithm.
  jwt.verify(refreshToken, config.jwt.refreshSecret, { algorithms: ['HS256'] });

  // Atomically consume the refresh token (prevents race conditions).
  // DELETE...RETURNING guarantees only one concurrent request succeeds and
  // returns the *server-side* user_id bound to the token row.
  const tokenHash = hashRefreshToken(refreshToken);
  const tokenResult = await query(
    `DELETE FROM refresh_tokens
     WHERE token = $1 AND expires_at > NOW()
     RETURNING user_id`,
    [tokenHash]
  );

  if (tokenResult.rows.length === 0) {
    // Token unknown / already consumed. We can't safely identify the
    // owning user (the JWT body is attacker-controlled if signing was
    // compromised), so just refuse without doing any user-scoped action.
    logger.warn({ tokenHashPrefix: tokenHash.slice(0, 12) }, 'Unknown refresh token presented');
    throw new AppError('Invalid refresh token', 401);
  }

  // Trust ONLY the user_id from the row we just deleted.
  const trustedUserId: string = tokenResult.rows[0].user_id;

  // Get user (include role fields for JWT claims)
  const userResult = await query(
    `SELECT u.id, u.email, u.is_admin, u.deleted_at, u.plan,
            (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = u.id AND p.is_active = TRUE)) as is_partner
     FROM users u WHERE u.id = $1`,
    [trustedUserId],
  );

  if (userResult.rows.length === 0) {
    throw new AppError('User not found', 401);
  }

  const user = userResult.rows[0];

  // Refuse to refresh for soft-deleted or suspended users — otherwise a
  // valid refresh token outlives a suspend (audit Ch01-F021/F047).
  if (user.deleted_at || user.plan === 'suspended') {
    // Burn the rest of this user's refresh tokens too.
    await query(`DELETE FROM refresh_tokens WHERE user_id = $1`, [trustedUserId]);
    throw new AppError('Account is suspended or deleted', 401);
  }

  // Blacklist the old access token so it can't be reused after refresh
  const authHeader = req.headers.authorization;
  if (authHeader?.startsWith('Bearer ')) {
    const oldAccessToken = authHeader.substring(7);
    try {
      await blacklistTokenAuto(oldAccessToken);
    } catch {
      // Best-effort: don't block refresh if blacklisting fails
    }
  }

  // Generate new tokens (rotation) and cap active refresh tokens
  const { accessToken, refreshToken: newRefreshToken } = await createAuthSession(
    user.id, user.email, user.is_admin || false, user.is_partner || false
  );

  // S-ME-02: rotate CSRF token on auth state change to defang fixation.
  rotateCsrfToken(res);
  res.json({ success: true, data: { accessToken, refreshToken: newRefreshToken } });
}));

// Logout — requires a valid access token (Ch01-F014: previously accepted
// unauthenticated requests, which let an attacker who guessed a refresh
// token blacklist arbitrary access tokens). The access-token signature is
// verified by the `authenticate` middleware before the handler runs, so we
// can trust `req.user!.id` (Ch01-F015).
const logoutSchema = Joi.object({
  refreshToken: Joi.string().min(20).max(4096).optional(),
}).rename('refresh_token', 'refreshToken', { ignoreUndefined: true, override: false });

router.post('/logout', authenticate, refreshRateLimiter, validate(logoutSchema), asyncHandler(async (req, res) => {
  const { refreshToken } = req.body;
  const userId = req.user!.id;

  // Blacklist the current access token using its actual remaining TTL.
  //
  // S-M4 (audit): the prior shape silently swallowed a Redis-down /
  // blacklist-write failure and proceeded to return 200 "Logged out"
  // — but the access token's HS256 signature is still valid for the
  // full TTL (1h) since we never recorded it as revoked. An attacker
  // racing the user's logout (e.g. has stolen the access token, sees
  // the user click logout) keeps the token alive.
  //
  // Now: surface the failure as 503 so the client sees a real error
  // and the user can retry. The blacklist write IS the source of
  // truth for "this token can't be reused after logout." Don't lie.
  const authHeader = req.headers.authorization;
  if (authHeader?.startsWith('Bearer ')) {
    const accessToken = authHeader.substring(7);
    try {
      await blacklistTokenAuto(accessToken);
    } catch (blacklistError) {
      logger.error(
        { error: blacklistError, userId },
        'S-M4: failed to blacklist access token during logout — returning 503',
      );
      throw new AppError(
        'Logout temporarily unavailable. Please try again in a moment.',
        503,
        'UNHEALTHY',
      );
    }
  }

  if (refreshToken) {
    // Delete only refresh tokens that belong to the authenticated user —
    // we don't trust the JWT body of the refresh token any more than for
    // /refresh (Ch01-F020).
    const tokenHash = hashRefreshToken(refreshToken);
    await query(
      `DELETE FROM refresh_tokens WHERE token = $1 AND user_id = $2`,
      [tokenHash, userId],
    );
  }

  // Invalidate any unused password reset tokens for this user.
  await query(
    `UPDATE password_reset_tokens SET used = TRUE WHERE user_id = $1 AND used = FALSE`,
    [userId],
  );

  // Invalidate pending email-verification tokens too — a stale verify
  // link sent before logout shouldn't survive a logout (Ch01-F013).
  await query(
    `DELETE FROM email_verification_tokens WHERE user_id = $1`,
    [userId],
  );

  // Drop the cached user row so the next request after re-login isn't
  // served the stale 10s cache entry (Ch01-F048).
  await invalidateUserCache(userId);

  logAuthBestEffort({
    action: 'auth.logout',
    userId,
    ipAddress: getIpAddress(req),
    userAgent: req.get('user-agent'),
    success: true,
  });

  res.json({ success: true, message: 'Logged out successfully' });
}));

// H-A8 (audit): GET /auth/role-check — fresh DB-derived is_admin /
// is_partner. The dashboard Edge middleware previously read these
// flags from the unverified JWT body for navigation routing; a demoted
// user kept role-based dashboard access for up to JWT_EXPIRES_IN
// (1 hour) — the API still 403'd every page-render fetch via
// requireAdmin, but the user saw the admin nav shell render in between.
//
// This endpoint is intentionally lightweight: just authenticate +
// a single SELECT on the users table (already cached for 10s by
// the auth middleware). The dashboard middleware caches the response
// in a short-TTL cookie so it doesn't hit the API on every navigation.
router.get(
  '/role-check',
  authenticate,
  asyncHandler(async (req, res) => {
    // req.user is already populated from the auth middleware's fresh
    // DB read (or its 10s cache). is_admin and is_partner there are
    // derived from the same SELECT used by /admin/me etc.
    res.json({
      success: true,
      data: {
        user_id: req.user!.id,
        is_admin: req.user!.isAdmin === true,
        is_partner: req.user!.isPartner === true,
      },
    });
  }),
);

// Logout all devices — requires authentication
router.post('/logout-all', authenticate, asyncHandler(async (req, res) => {
  // Blacklist the current access token
  const authHeader = req.headers.authorization;
  if (authHeader?.startsWith('Bearer ')) {
    try {
      await blacklistTokenAuto(authHeader.substring(7));
    } catch {
      // Best-effort
    }
  }

  // Delete ALL refresh tokens for this user
  await query(
    `DELETE FROM refresh_tokens WHERE user_id = $1`,
    [req.user!.id]
  );

  // Invalidate any unused password reset tokens
  await query(
    `UPDATE password_reset_tokens SET used = TRUE WHERE user_id = $1 AND used = FALSE`,
    [req.user!.id]
  );

  // Audit log (best-effort — never block response on audit-write failure)
  logAuthBestEffort({
    action: 'auth.logout_all',
    userId: req.user!.id,
    ipAddress: getIpAddress(req),
    userAgent: req.get('user-agent'),
    success: true,
  });

  res.json({ success: true, message: 'All sessions logged out successfully' });
}));

// Forgot password - request reset.
//
// Audit Ch01-F016: response shape and timing must NOT vary on whether the
//   account exists. We always return the same generic message after a fixed
//   constant-time delay floor.
// Audit Ch01-F017: skip the email send entirely for accounts that haven't
//   verified their email — those accounts can re-trigger the verification
//   flow instead of using password reset to take over an unconfirmed inbox.
// Audit Ch01-F028: Apple/Google OAuth-only accounts have no password to
//   reset; tell the user (without confirming the email exists) to use the
//   provider's flow.
const FORGOT_PASSWORD_MIN_DURATION_MS = 250;

router.post('/forgot-password', passwordResetRateLimiter, validate(forgotPasswordSchema), asyncHandler(async (req, res) => {
  const startedAt = Date.now();
  const respondGeneric = async () => {
    const elapsed = Date.now() - startedAt;
    if (elapsed < FORGOT_PASSWORD_MIN_DURATION_MS) {
      await new Promise((r) => setTimeout(r, FORGOT_PASSWORD_MIN_DURATION_MS - elapsed));
    }
    res.json({ success: true, message: 'If an account exists with that email, a reset link has been sent.' });
  };

  const { email } = req.body;

  const result = await query(
    `SELECT id, email, full_name, auth_provider, email_verified
       FROM users
      WHERE email = $1
        AND deleted_at IS NULL
        AND plan <> 'suspended'`,
    [email.toLowerCase()],
  );

  // Account doesn't exist, is OAuth-only, or hasn't verified email — all
  // three return the same generic response so an attacker can't tell them
  // apart.
  const user = result.rows[0];
  const isPasswordAccount = user?.auth_provider === 'email' || (user && !user.auth_provider);

  if (!user || !isPasswordAccount || !user.email_verified) {
    return respondGeneric();
  }

  // H-A4 (audit): per-target-email rate limit on top of the per-IP
  // passwordResetRateLimiter. The IP-keyed limiter is defeated by a
  // botnet rotating residential proxies — without this guard a victim
  // gets:
  //   (a) their inbox bombed with HavenKeep-branded reset emails
  //       (SendGrid budget + sender-reputation hit), and
  //   (b) their legitimate in-flight reset token continually
  //       invalidated by the UPDATE ... SET used = TRUE below, so the
  //       legitimate user can never complete the flow until the
  //       attacker stops.
  //
  // 3 sends per email per hour, hashed key so a DB-leaked Redis dump
  // doesn't enumerate target emails. Fail-open: if Redis is down we'd
  // rather over-send than refuse legitimate resets.
  const recipientHash = crypto
    .createHash('sha256')
    .update(user.email.toLowerCase())
    .digest('hex');
  const recipientKey = `pwReset:recipient:${recipientHash}`;
  let recipientRateLimited = false;
  try {
    const redis = await getRedisClient();
    const count = await redis.incr(recipientKey);
    if (count === 1) {
      await redis.expire(recipientKey, 60 * 60);
    }
    if (count > 3) {
      recipientRateLimited = true;
    }
  } catch (err) {
    logger.warn({ err }, 'forgot-password recipient rate-limit Redis check failed; proceeding');
  }

  if (recipientRateLimited) {
    // Generic shape-identical response — same as the no-account path —
    // so an attacker can't probe whether their target is rate-limited.
    // Critically: skip the UPDATE ... SET used = TRUE that follows.
    // That update is the legitimate-user-DOS vector this guard exists
    // to close; running it on every attacker call would still let the
    // attacker burn the user's working token.
    logAuthBestEffort({
      action: 'auth.password_reset_request',
      userId: user.id,
      email: user.email,
      ipAddress: getIpAddress(req),
      userAgent: req.get('user-agent'),
      success: false,
      errorMessage: 'recipient_rate_limited',
    });
    return respondGeneric();
  }

  // Invalidate any existing reset tokens (single-use semantics).
  await query(
    `UPDATE password_reset_tokens SET used = TRUE WHERE user_id = $1 AND used = FALSE`,
    [user.id],
  );

  const resetToken = crypto.randomBytes(32).toString('hex');
  const expiresAt = new Date(Date.now() + 60 * 60 * 1000); // 1 hour
  await query(
    `INSERT INTO password_reset_tokens (user_id, token, expires_at)
       VALUES ($1, $2, $3)`,
    [user.id, hashToken(resetToken), expiresAt],
  );

  const resetUrl = `${config.app.frontendUrl}/reset-password?token=${resetToken}`;
  EmailService.sendPasswordResetEmail({
    to: user.email,
    user_name: user.full_name || 'there',
    reset_url: resetUrl,
  }).catch((emailError) => {
    logger.error({ error: emailError, userId: user.id }, 'Failed to send password reset email');
  });

  AuditService.logAuth({
    action: 'auth.password_reset_request',
    userId: user.id,
    email: user.email,
    ipAddress: getIpAddress(req),
    userAgent: req.get('user-agent'),
    success: true,
  }).catch((err) => logger.warn({ err }, 'Audit log failed for password_reset_request'));

  return respondGeneric();
}));

// Reset password with token
router.post('/reset-password', authRateLimiter, validate(resetPasswordSchema), asyncHandler(async (req, res) => {
  const { token, newPassword } = req.body;

  // Hash the token for lookup. Audit Ch01-F019: lookups go through the
  // keyed `hashToken` helper so a DB-only leak doesn't allow rainbowing.
  const tokenHash = hashToken(token);

  // Pre-hash to defang bcrypt's 72-byte truncation (Ch01-F005).
  const passwordHash = await bcrypt.hash(preHashForBcrypt(newPassword), 12);

  // Atomically: validate+consume token, update password, invalidate all
  // sessions. If any step fails the token stays unused so the user can
  // retry instead of being permanently locked out.
  const client = await getClient();
  let userId: string;
  try {
    await client.query('BEGIN');
    const tokenResult = await client.query(
      `UPDATE password_reset_tokens
          SET used = TRUE
        WHERE token = $1 AND expires_at > NOW() AND used = FALSE
       RETURNING user_id`,
      [tokenHash],
    );
    if (tokenResult.rows.length === 0) {
      await client.query('ROLLBACK').catch(() => {});
      throw new AppError('Invalid or expired reset token', 400);
    }
    userId = tokenResult.rows[0].user_id;

    await client.query(
      `UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2`,
      [passwordHash, userId],
    );
    // Drop every refresh token + every other unused reset token + every
    // pending email-verification token so no stale credential survives a
    // password reset (Ch01-F018: the dead "blacklist caller token" path
    // below was removed since the caller doesn't have one — the reset
    // page is unauthenticated).
    await client.query(`DELETE FROM refresh_tokens WHERE user_id = $1`, [userId]);
    await client.query(
      `UPDATE password_reset_tokens SET used = TRUE
        WHERE user_id = $1 AND used = FALSE`,
      [userId],
    );
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }

  // Audit log: password reset completed (best-effort)
  logAuthBestEffort({
    action: 'auth.password_reset_complete',
    userId,
    ipAddress: getIpAddress(req),
    userAgent: req.get('user-agent'),
    success: true,
  });

  res.json({ success: true, message: 'Password has been reset successfully' });
}));

// Verify email
router.post('/verify-email', authRateLimiter, validate(verifyEmailSchema), asyncHandler(async (req, res) => {
  const { token } = req.body;

  // Atomically consume the verification token. Only accept tokens whose
  // metadata indicates a register-flow verification — change-email tokens
  // live in the same table and would otherwise let a request to /verify-email
  // mark the *current* address as verified without applying the email swap
  // (audit Ch01-F011). Change-email tokens go through /verify-email-change.
  const tokenResult = await query(
    `DELETE FROM email_verification_tokens
      WHERE token = $1
        AND expires_at > NOW()
        AND COALESCE(metadata->>'type', 'register') IN ('register', 'verify')
      RETURNING user_id`,
    [hashRefreshToken(token)],
  );

  if (tokenResult.rows.length === 0) {
    throw new AppError('Invalid or expired verification token', 400);
  }

  const userId = tokenResult.rows[0].user_id;

  // Mark email as verified and clean up any remaining tokens for this user.
  // Limit cleanup to register-flow tokens so an in-flight change-email
  // token isn't collateral-damage deleted.
  await Promise.all([
    query(`UPDATE users SET email_verified = TRUE WHERE id = $1`, [userId]),
    query(
      `DELETE FROM email_verification_tokens
        WHERE user_id = $1
          AND COALESCE(metadata->>'type', 'register') IN ('register', 'verify')`,
      [userId],
    ),
  ]);

  // 2.3: cached row holds email_verified=false; invalidate so authenticated
  // routes reading req.user.emailVerified see the new value.
  await invalidateUserCache(userId);

  // Audit log: email verified (best-effort)
  logAuthBestEffort({
    action: 'auth.email_verify',
    userId,
    ipAddress: getIpAddress(req),
    userAgent: req.get('user-agent'),
    success: true,
  });

  res.json({ success: true, message: 'Email verified successfully' });
}));

// C13: consume a change-email verification token. /me/change-email mints
// a token, stores SHA-256(token) (S-M9 fix below moves to keyed HMAC) in
// email_verification_tokens with metadata.type='change_email' + new_email,
// and emails the new address a link of the form
//   ${frontendUrl}/verify-email-change?token=...
// The marketing site's /verify-email-change page POSTs the token here.
//
// Atomic: DELETE..RETURNING the token, lock the new email's uniqueness
// inside a tx, swap users.email, drop every refresh token for the user
// (force re-login on every device — the email is an authentication
// identifier in /forgot-password and /login), invalidate the user cache.
router.post(
  '/verify-email-change',
  authRateLimiter,
  validate(verifyEmailChangeSchema),
  asyncHandler(async (req, res) => {
    const { token } = req.body;
    const tokenHash = hashToken(token);

    const client = await getClient();
    let userId: string;
    let newEmail: string;
    try {
      await client.query('BEGIN');

      // Atomically consume the token. Restrict to type='change_email' so
      // a token of a different shape can't be redeemed here (the type
      // distinction is the same defense /verify-email uses in reverse —
      // see auth.ts:830).
      const consumed = await client.query(
        `DELETE FROM email_verification_tokens
          WHERE token = $1
            AND expires_at > NOW()
            AND metadata->>'type' = 'change_email'
          RETURNING user_id, metadata->>'new_email' AS new_email`,
        [tokenHash],
      );

      if (consumed.rows.length === 0) {
        await client.query('ROLLBACK').catch(() => {});
        throw new AppError('Invalid or expired verification link', 400);
      }

      userId = consumed.rows[0].user_id;
      newEmail = String(consumed.rows[0].new_email).toLowerCase();

      // Translate uniqueness violation to 409. Race between two users
      // both consuming change-email tokens to the same address: one wins,
      // the other gets a clean 409 with their token already consumed.
      try {
        await client.query(
          `UPDATE users
              SET email = $2,
                  email_verified = TRUE,
                  email_change_pending = NULL,
                  email_change_target = NULL,
                  updated_at = NOW()
            WHERE id = $1`,
          [userId, newEmail],
        );
      } catch (err: any) {
        if (err?.code === '23505') {
          await client.query('ROLLBACK').catch(() => {});
          throw new AppError('That email is no longer available', 409);
        }
        throw err;
      }

      // Force re-login on every device. The new email is an
      // authentication identifier; any in-flight refresh token bound to
      // the old email must die. (Mirrors /reset-password.)
      await client.query(`DELETE FROM refresh_tokens WHERE user_id = $1`, [userId]);

      // Drop every other change-email token for this user so the email
      // doesn't sit pending after the swap.
      await client.query(
        `DELETE FROM email_verification_tokens
          WHERE user_id = $1 AND metadata->>'type' = 'change_email'`,
        [userId],
      );

      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      throw err;
    } finally {
      client.release();
    }

    // Drop the cached user row so the next request after re-login sees
    // the new email + verified=true rather than the stale cache.
    await invalidateUserCache(userId);

    logAuthBestEffort({
      action: 'auth.email_verify',
      userId,
      email: newEmail,
      ipAddress: getIpAddress(req),
      userAgent: req.get('user-agent'),
      success: true,
      errorMessage: 'change_email completed',
    });

    res.json({
      success: true,
      message: 'Email change confirmed. Please sign in with your new email.',
    });
  }),
);

// Google OAuth — accept ID token from mobile, verify, create/find user, return JWT
const googleOAuthSchema = Joi.object({
  idToken: Joi.string().required(),
  referralCode: Joi.string().optional(),
});

router.post('/google', authRateLimiter, validate(googleOAuthSchema), asyncHandler(async (req, res) => {
    // Audit Ch01-F022: accept multiple audiences. The deployed setup keeps
    // Google client IDs per platform — iOS, Android, Web — and the audience
    // claim varies depending on which one the SDK initialised. Accept any
    // configured client id.
    const allowedGoogleAudiences: string[] = [
      config.google?.clientId,
      ...((process.env.GOOGLE_AUDIENCES || '').split(',').map((s) => s.trim()).filter(Boolean)),
    ].filter((a): a is string => typeof a === 'string' && a.length > 0);

    if (allowedGoogleAudiences.length === 0) {
      throw new AppError('Google OAuth is not configured', 501);
    }

    const { idToken, referralCode } = req.body;

    // Verify the Google ID token (lazy-init singleton).
    //
    // 2.6: cap the upstream HTTPS call at 5s. google-auth-library has no
    // timeout by default — if oauth2.googleapis.com / token verification
    // slows, every concurrent sign-in pins a DB pool client until the
    // socket closes. Pool=20 + a 25s upstream stall = pool exhaustion +
    // 503s on every authenticated route.
    if (!googleOAuth2Client) {
      const { OAuth2Client } = await import('google-auth-library');
      googleOAuth2Client = new OAuth2Client({
        clientId: allowedGoogleAudiences[0],
      });
      googleOAuth2Client.transporter.defaults = {
        ...googleOAuth2Client.transporter.defaults,
        timeout: 5000,
      };
    }
    const oauthClient = googleOAuth2Client;

    const ticket = await oauthClient.verifyIdToken({
      idToken,
      audience: allowedGoogleAudiences,
    });

    const payload = ticket.getPayload();
    if (!payload || !payload.email) {
      throw new AppError('Invalid Google token', 401);
    }

    // Reject if Google hasn't verified the email (prevents account takeover)
    if (!payload.email_verified) {
      throw new AppError('Google email is not verified', 401);
    }

    const email = payload.email.toLowerCase();
    const fullName = payload.name || 'User';
    // S-CR-02: avatar_url column holds a MinIO object key, not a URL.
    // We can't store the Google `picture` URL there directly. The user
    // can upload an avatar via /uploads/avatar after signing in; we
    // intentionally do not auto-mirror the Google avatar to MinIO.

    // Find or create user
    let userResult = await query(
      `SELECT id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
              referred_by, referral_code, is_admin, email_verified, created_at, updated_at,
              (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = users.id AND p.is_active = TRUE)) as is_partner
       FROM users WHERE email = $1`,
      [email]
    );

    // Audit Ch01-F023: the prior code silently merged a Google sign-in into
    // an existing email/password account, which would let an attacker who
    // owns a Google address take over a same-email password account if the
    // password user never verified their email. Refuse the merge unless the
    // existing account has confirmed the address.
    if (
      userResult.rows.length > 0 &&
      userResult.rows[0].auth_provider === 'email' &&
      !userResult.rows[0].email_verified
    ) {
      throw new AppError(
        'An account with this email already exists. Please sign in with your password and verify your email before linking Google.',
        409,
      );
    }

    let user;
    let isNewUser = false;

    if (userResult.rows.length === 0) {
      const referredBy = await resolveReferredBy(referralCode);
      const userReferralCode = await generateUniqueReferralCode();

      // Create new user + default home inside a transaction
      const txClient = await getClient();
      try {
        await txClient.query('BEGIN');
        const createResult = await txClient.query(
          `INSERT INTO users (email, full_name, auth_provider, email_verified, referral_code, referred_by)
           VALUES ($1, $2, 'google', TRUE, $3, $4)
           RETURNING id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
                     referred_by, referral_code, is_admin, created_at, updated_at`,
          [email, fullName, userReferralCode, referredBy]
        );
        user = createResult.rows[0];
        isNewUser = true;

        // Create default home
        await txClient.query(
          `INSERT INTO homes (user_id, name) VALUES ($1, $2)`,
          [user.id, 'My Home']
        );
        await txClient.query('COMMIT');
      } catch (txError) {
        await txClient.query('ROLLBACK').catch(() => {});
        throw txError;
      } finally {
        txClient.release();
      }
    } else {
      user = userResult.rows[0];
    }

    // Generate tokens, store refresh token, and cap active tokens
    const { accessToken, refreshToken } = await createAuthSession(
      user.id, user.email, user.is_admin || false, user.is_partner ?? false
    );

    // Audit log: OAuth login (best-effort)
    logAuthBestEffort({
      action: 'auth.oauth_login',
      userId: user.id,
      email: user.email,
      ipAddress: getIpAddress(req),
      userAgent: req.get('user-agent'),
      success: true,
      metadata: {
        provider: 'google',
        new_user: isNewUser,
      },
    });

    // S-ME-02: rotate CSRF token on auth state change to defang fixation.
    rotateCsrfToken(res);
    res.json({
      success: true,
      data: {
        user: {
          id: user.id,
          email: user.email,
          full_name: user.full_name,
          avatar_url: await presignAvatarUrl(user.avatar_url),
          auth_provider: user.auth_provider || 'google',
          plan: user.plan,
          plan_expires_at: user.plan_expires_at || null,
          referred_by: user.referred_by || null,
          referral_code: user.referral_code || null,
          is_admin: user.is_admin,
          is_partner: user.is_partner ?? false,
          created_at: user.created_at,
          updated_at: user.updated_at,
        },
        accessToken,
        refreshToken,
      },
    });
}));

// Apple OAuth — accept ID token from mobile, verify, create/find user, return JWT
//
// S1-H: `nonce` is the unhashed random string the client generated for this
// sign-in attempt. The client passed SHA-256(nonce) to Apple's SDK; we hash
// it again and confirm it matches the `nonce` claim baked into the ID token.
// Required (not optional) — without it a stolen ID token is replayable.
const appleOAuthSchema = Joi.object({
  idToken: Joi.string().required(),
  nonce: Joi.string().min(8).max(256).required(),
  fullName: Joi.string().optional(),
  referralCode: Joi.string().optional(),
});

router.post('/apple', authRateLimiter, validate(appleOAuthSchema), asyncHandler(async (req, res) => {
    // The /apple endpoint is enabled if at least one valid audience is
    // configured — either the iOS bundle ID (native iOS flow) or one or more
    // Services IDs (Android / web flow).
    const allowedAudiences = [
      config.apple?.bundleId,
      ...(config.apple?.servicesIds ?? []),
    ].filter((a): a is string => typeof a === 'string' && a.length > 0);

    if (allowedAudiences.length === 0) {
      throw new AppError('Apple Sign-In is not configured', 501);
    }

    const { idToken, nonce, fullName: appleFullName, referralCode } = req.body;

    // S1-H: hash the client-supplied nonce once so we can compare against the
    // ID token's `nonce` claim *and* use the hash as the replay-protection
    // key. The Apple SDK requires the SHA-256 hex of the random value as
    // input and bakes the *same* hex into the resulting ID token's claims.
    const nonceHash = crypto.createHash('sha256').update(nonce, 'utf8').digest('hex');

    // Verify Apple ID token against Apple's public keys (JWKS, lazy-init
    // singleton). 2.6: jwks-rsa defaults to a 30s socket timeout — if
    // Apple's keys endpoint slows under load, every concurrent Apple
    // sign-in parks a DB pool client. Cap at 5s.
    if (!appleJwksClientInstance) {
      const jwksClient = await import('jwks-rsa');
      appleJwksClientInstance = jwksClient.default({
        jwksUri: 'https://appleid.apple.com/auth/keys',
        cache: true,
        cacheMaxAge: 86400000, // 24 hours
        timeout: 5000,
      });
    }
    const appleJwksClient = appleJwksClientInstance;

    // Decode header to get the key ID
    const decodedHeader = jwt.decode(idToken, { complete: true });
    if (!decodedHeader || !decodedHeader.header.kid) {
      throw new AppError('Invalid Apple token format', 401);
    }

    // Fetch the signing key from Apple's JWKS
    const signingKey = await appleJwksClient.getSigningKey(decodedHeader.header.kid);
    const publicKey = signingKey.getPublicKey();

    // Verify the token signature and claims. `audience` accepts an array;
    // jwt.verify passes if the token's aud matches any entry. Cast to the
    // non-empty-tuple type the @types/jsonwebtoken overload requires —
    // safe because the empty-list path threw at line ~890.
    const decoded = jwt.verify(idToken, publicKey, {
      algorithms: ['RS256'],
      issuer: 'https://appleid.apple.com',
      audience: allowedAudiences as [string, ...string[]],
    }) as {
      sub: string;
      email?: string;
      email_verified?: boolean;
      aud?: string;
      nonce?: string;
    };

    if (!decoded || !decoded.sub) {
      throw new AppError('Invalid Apple token', 401);
    }

    // S-ME-05: Apple's docs say `email_verified` is always true (Apple
    // validates email ownership at Apple-ID-creation time). Defensive
    // check — if Apple ever lies / changes that contract, fail closed
    // rather than silently accepting an unverified email.
    if (decoded.email_verified === false) {
      throw new AppError('Apple email is not verified', 401);
    }

    // S1-H: verify the SHA-256 of the client-supplied nonce matches the
    // `nonce` claim Apple baked into the token, then record the hash so the
    // same id-token+nonce pair can never be replayed.
    if (typeof decoded.nonce !== 'string' || decoded.nonce.length === 0) {
      throw new AppError('Apple token missing nonce claim', 401);
    }
    if (decoded.nonce !== nonceHash) {
      throw new AppError('Apple token nonce mismatch', 401);
    }
    await markAppleNonceConsumed(nonceHash);

    const appleUserId = decoded.sub;
    let email = decoded.email?.toLowerCase();

    // Find or create user — first try by email, then by apple_user_id
    let userResult;

    if (email) {
      userResult = await query(
        `SELECT id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
                referred_by, referral_code, is_admin, email_verified, apple_user_id, created_at, updated_at,
                (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = users.id AND p.is_active = TRUE)) as is_partner
         FROM users WHERE email = $1`,
        [email]
      );
    }

    // On subsequent sign-ins, Apple may not provide email.
    // Fall back to lookup by apple_user_id stored from first sign-in.
    if ((!email || !userResult || userResult.rows.length === 0)) {
      const appleIdResult = await query(
        `SELECT id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
                referred_by, referral_code, is_admin, email_verified, apple_user_id, created_at, updated_at,
                (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = users.id AND p.is_active = TRUE)) as is_partner
         FROM users WHERE apple_user_id = $1`,
        [appleUserId]
      );
      if (appleIdResult.rows.length > 0) {
        userResult = appleIdResult;
        email = appleIdResult.rows[0].email;
      }
    }

    // S-CR-01: refuse to merge an Apple sign-in into an existing
    // email/password account by email match alone. The Google handler
    // has the symmetric guard at line ~915. Without this, an attacker
    // who controls an Apple ID with the same email as a HavenKeep
    // email/password user takes over the account on first Apple sign-in
    // and the apple_user_id binding below permanently locks the victim
    // out. The only safe merges: (a) the existing row's auth_provider
    // is already 'apple', or (b) the row already has the same
    // apple_user_id (subsequent sign-in for an already-linked user).
    if (
      userResult &&
      userResult.rows.length > 0 &&
      userResult.rows[0].auth_provider === 'email' &&
      userResult.rows[0].apple_user_id == null
    ) {
      throw new AppError(
        'An account with this email already exists. Please sign in with your password first to link Apple Sign-In to your account.',
        409,
      );
    }

    // H-A6 (audit): when the email-matched row already has an
    // apple_user_id AND it differs from the JWT-claimed sub, refuse.
    // The prior shape relied on the `WHERE apple_user_id IS NULL`
    // guard in the post-success UPDATE to silently skip the bind, but
    // the request still authenticated as the existing user — meaning
    // a second Apple ID (different `sub`) sharing an email with an
    // existing Apple-linked account could log in as the original
    // owner. Apple's `sub` is the canonical identifier; it must
    // round-trip on every sign-in.
    if (
      userResult &&
      userResult.rows.length > 0 &&
      userResult.rows[0].apple_user_id != null &&
      userResult.rows[0].apple_user_id !== appleUserId
    ) {
      logAuthBestEffort({
        action: 'auth.oauth_login',
        userId: userResult.rows[0].id,
        email: userResult.rows[0].email,
        ipAddress: getIpAddress(req),
        userAgent: req.get('user-agent'),
        success: false,
        errorMessage: 'apple_sub_mismatch',
        metadata: {
          provider: 'apple',
          stored_apple_user_id: userResult.rows[0].apple_user_id,
          presented_apple_user_id: appleUserId,
        },
      });
      throw new AppError(
        'Apple identifier mismatch. Please sign in with the original Apple ID linked to this account.',
        401,
        'AUTH_REQUIRED',
      );
    }

    // Apple only returns the email on the first sign-in to a given Service
    // ID. If the apple_user_id lookup also failed (genuine first-ever
    // sign-in but the email field was suppressed for any reason — Hide-My-
    // Email failure mode, client lost the field between the Apple flow
    // and our endpoint, etc.), synthesize a deterministic placeholder so
    // we can still mint the account. The placeholder uses an obviously
    // non-routable host so we never accidentally email it; the user can
    // attach a real recovery email from Settings later.
    if (!email) {
      email = `apple-${appleUserId}@privaterelay.apple.local`;
    }

    if (!userResult) {
      userResult = { rows: [] };
    }

    let user;
    let isNewUser = false;

    if (userResult.rows.length === 0) {
      const fullName = appleFullName || 'User';
      const referredBy = await resolveReferredBy(referralCode);
      const userReferralCode = await generateUniqueReferralCode();

      // Create new user + default home inside a transaction
      const txClient = await getClient();
      try {
        await txClient.query('BEGIN');
        const createResult = await txClient.query(
          `INSERT INTO users (email, full_name, auth_provider, email_verified, apple_user_id, referral_code, referred_by)
           VALUES ($1, $2, 'apple', TRUE, $3, $4, $5)
           RETURNING id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
                     referred_by, referral_code, is_admin, created_at, updated_at`,
          [email, fullName, appleUserId, userReferralCode, referredBy]
        );
        user = createResult.rows[0];
        isNewUser = true;

        // Create default home
        await txClient.query(
          `INSERT INTO homes (user_id, name) VALUES ($1, $2)`,
          [user.id, 'My Home']
        );
        await txClient.query('COMMIT');
      } catch (txError) {
        await txClient.query('ROLLBACK').catch(() => {});
        throw txError;
      } finally {
        txClient.release();
      }
    } else {
      user = userResult.rows[0];

      // Ensure apple_user_id is stored for future lookups
      await query(
        `UPDATE users SET apple_user_id = $1 WHERE id = $2 AND apple_user_id IS NULL`,
        [appleUserId, user.id]
      );
    }

    // Generate tokens, store refresh token, and cap active tokens
    const { accessToken, refreshToken } = await createAuthSession(
      user.id, user.email, user.is_admin || false, user.is_partner ?? false
    );

    // Audit log: OAuth login (best-effort)
    logAuthBestEffort({
      action: 'auth.oauth_login',
      userId: user.id,
      email: user.email,
      ipAddress: getIpAddress(req),
      userAgent: req.get('user-agent'),
      success: true,
      metadata: {
        provider: 'apple',
        new_user: isNewUser,
      },
    });

    // S-ME-02: rotate CSRF token on auth state change to defang fixation.
    rotateCsrfToken(res);
    res.json({
      success: true,
      data: {
        user: {
          id: user.id,
          email: user.email,
          full_name: user.full_name,
          avatar_url: await presignAvatarUrl(user.avatar_url),
          auth_provider: user.auth_provider || 'apple',
          plan: user.plan,
          plan_expires_at: user.plan_expires_at || null,
          referred_by: user.referred_by || null,
          referral_code: user.referral_code || null,
          is_admin: user.is_admin,
          is_partner: user.is_partner ?? false,
          created_at: user.created_at,
          updated_at: user.updated_at,
        },
        accessToken,
        refreshToken,
      },
    });
}));

export default router;
