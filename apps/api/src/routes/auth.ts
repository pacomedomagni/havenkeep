import { Router } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { query, getClient } from '../db';
import Joi from 'joi';
import { config } from '../config';
import { AppError } from '../middleware/errorHandler';
import { authRateLimiter, refreshRateLimiter, passwordResetRateLimiter } from '../middleware/rateLimiter';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { registerSchema, loginSchema, refreshTokenSchema } from '../validators';
import { forgotPasswordSchema, resetPasswordSchema, verifyEmailSchema } from '../validators/auth.validator';
import { logger } from '../utils/logger';
import { AuditService } from '../services/audit.service';
import { EmailService } from '../services/email.service';
import { blacklistTokenAuto } from '../utils/token-blacklist';
import { generateUniqueReferralCode } from '../utils/referral-code';

const router = Router();

// Cached OAuth client singletons (lazy-initialized)
let googleOAuth2Client: any = null;
let appleJwksClientInstance: any = null;

// Parse JWT expiry string (e.g. '7d', '24h') to milliseconds
function parseExpiryToMs(expiry: string | number): number {
  if (typeof expiry === 'number') return expiry * 1000;
  const match = String(expiry).match(/^(\d+)(s|m|h|d)$/);
  if (!match) return 7 * 24 * 60 * 60 * 1000; // fallback 7 days
  const value = parseInt(match[1], 10);
  const unit = match[2];
  const multipliers: Record<string, number> = { s: 1000, m: 60000, h: 3600000, d: 86400000 };
  return value * multipliers[unit];
}

const REFRESH_TOKEN_EXPIRY_MS = parseExpiryToMs(config.jwt.refreshExpiresIn as string | number);

// Hash refresh tokens with SHA-256 before storing in the database.
// This prevents token theft from a DB dump — the raw token is only sent to the client.
function hashRefreshToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
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

async function resolveReferredBy(referralCode?: string): Promise<string | null> {
  if (!referralCode) return null;
  const result = await query(
    `SELECT id FROM users WHERE referral_code = $1`,
    [referralCode]
  );
  return result.rows.length > 0 ? result.rows[0].id : null;
}

// Register
router.post('/register', authRateLimiter, validate(registerSchema), async (req, res, next) => {
  const client = await getClient();
  try {
    const { email, password, fullName, referralCode } = req.body;

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

    // Hash password with bcrypt rounds=12 (only after confirming email is available)
    const passwordHash = await bcrypt.hash(password, 12);

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

    // Generate tokens
    const accessToken = jwt.sign(
      { userId: user.id, email: user.email },
      config.jwt.secret,
      { expiresIn: config.jwt.expiresIn }
    );

    const refreshToken = jwt.sign(
      { userId: user.id },
      config.jwt.refreshSecret,
      { expiresIn: config.jwt.refreshExpiresIn }
    );

    // Store hashed refresh token
    const expiresAt = new Date(Date.now() + REFRESH_TOKEN_EXPIRY_MS);

    await client.query(
      `INSERT INTO refresh_tokens (user_id, token, expires_at)
       VALUES ($1, $2, $3)`,
      [user.id, hashRefreshToken(refreshToken), expiresAt]
    );

    await client.query('COMMIT');

    // Audit log: successful registration
    await AuditService.logAuth({
      action: 'auth.register',
      userId: user.id,
      email: user.email,
      ipAddress: getIpAddress(req),
      userAgent: req.get('user-agent'),
      success: true,
    });

    // Send email verification (fire-and-forget)
    const verificationToken = crypto.randomBytes(32).toString('hex');
    const verificationExpiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24 hours
    query(
      `INSERT INTO email_verification_tokens (user_id, token, expires_at) VALUES ($1, $2, $3)`,
      [user.id, verificationToken, verificationExpiresAt]
    ).then(() => {
      const verifyUrl = `${config.app.frontendUrl}/verify-email?token=${verificationToken}`;
      return EmailService.sendEmailVerificationEmail({
        to: user.email,
        user_name: user.full_name || 'there',
        verify_url: verifyUrl,
      });
    }).catch((err) => {
      logger.error({ error: err, userId: user.id }, 'Failed to send verification email');
    });

    res.status(201).json({
      user: {
        id: user.id,
        email: user.email,
        full_name: user.full_name,
        avatar_url: user.avatar_url || null,
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
    });
  } catch (error) {
    await client.query('ROLLBACK');
    // Audit log: failed registration (skip for duplicate-email conflicts)
    if ((error as any)?.code !== '23505' && !(error instanceof AppError && error.statusCode === 409)) {
      await AuditService.logAuth({
        action: 'auth.register',
        email: req.body.email,
        ipAddress: getIpAddress(req),
        userAgent: req.get('user-agent'),
        success: false,
        errorMessage: error instanceof Error ? error.message : 'Registration failed',
      });
    }
    next(error);
  } finally {
    client.release();
  }
});

// Login
router.post('/login', authRateLimiter, validate(loginSchema), async (req, res, next) => {
  try {
    const { email, password } = req.body;

    // Get user
    const result = await query(
      `SELECT u.id, u.email, u.password_hash, u.full_name, u.avatar_url, u.auth_provider, u.plan,
              u.plan_expires_at, u.referred_by, u.referral_code, u.is_admin, u.created_at, u.updated_at,
              (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = u.id AND p.is_active = TRUE)) as is_partner
       FROM users u WHERE u.email = $1`,
      [email.toLowerCase()]
    );

    if (result.rows.length === 0) {
      // Constant-time: run bcrypt even when user doesn't exist to prevent timing attacks
      await bcrypt.compare(password, '$2a$12$000000000000000000000uGAV.eTk/fI05JBbVvI3B.ggHOFglqi');
      throw new AppError('Invalid credentials', 401);
    }

    const user = result.rows[0];

    // Verify password
    if (!user.password_hash) {
      await bcrypt.compare(password, '$2a$12$000000000000000000000uGAV.eTk/fI05JBbVvI3B.ggHOFglqi');
      throw new AppError('Invalid credentials', 401);
    }
    const valid = await bcrypt.compare(password, user.password_hash);

    if (!valid) {
      // Audit log: failed login (wrong password)
      await AuditService.logAuth({
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

    // Generate tokens
    const accessToken = jwt.sign(
      { userId: user.id, email: user.email },
      config.jwt.secret,
      { expiresIn: config.jwt.expiresIn }
    );

    const refreshToken = jwt.sign(
      { userId: user.id },
      config.jwt.refreshSecret,
      { expiresIn: config.jwt.refreshExpiresIn }
    );

    // Store hashed refresh token
    const expiresAt = new Date(Date.now() + REFRESH_TOKEN_EXPIRY_MS);

    await query(
      `INSERT INTO refresh_tokens (user_id, token, expires_at)
       VALUES ($1, $2, $3)`,
      [user.id, hashRefreshToken(refreshToken), expiresAt]
    );

    // Cap active refresh tokens per user (keep most recent 10, remove oldest)
    await query(
      `DELETE FROM refresh_tokens
       WHERE user_id = $1 AND id NOT IN (
         SELECT id FROM refresh_tokens WHERE user_id = $1
         ORDER BY created_at DESC LIMIT 10
       )`,
      [user.id]
    );

    // Audit log: successful login
    await AuditService.logAuth({
      action: 'auth.login',
      userId: user.id,
      email: user.email,
      ipAddress: getIpAddress(req),
      userAgent: req.get('user-agent'),
      success: true,
    });

    res.json({
      user: {
        id: user.id,
        email: user.email,
        full_name: user.full_name,
        avatar_url: user.avatar_url || null,
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
    });
  } catch (error) {
    // Audit log: failed login (user not found or other error) — skip if already logged
    if (error instanceof AppError && error.statusCode === 401 && !(error as any)._auditLogged) {
      await AuditService.logAuth({
        action: 'auth.login',
        email: req.body.email,
        ipAddress: getIpAddress(req),
        userAgent: req.get('user-agent'),
        success: false,
        errorMessage: 'Invalid credentials',
      });
    }
    next(error);
  }
});

// Refresh token
router.post('/refresh', refreshRateLimiter, validate(refreshTokenSchema), async (req, res, next) => {
  try {
    const { refreshToken } = req.body;

    // Verify refresh token
    const decoded = jwt.verify(refreshToken, config.jwt.refreshSecret) as {
      userId: string;
    };

    // Atomically consume the refresh token (prevents race conditions).
    // DELETE...RETURNING guarantees only one concurrent request succeeds.
    const tokenHash = hashRefreshToken(refreshToken);
    const tokenResult = await query(
      `DELETE FROM refresh_tokens
       WHERE token = $1 AND expires_at > NOW()
       RETURNING user_id`,
      [tokenHash]
    );

    if (tokenResult.rows.length === 0) {
      // Token not found — could be replay/reuse. Check if user exists
      // and invalidate all their tokens as a security precaution.
      const suspectUser = await query(
        `SELECT id FROM users WHERE id = $1`,
        [decoded.userId]
      );
      if (suspectUser.rows.length > 0) {
        await query(
          `DELETE FROM refresh_tokens WHERE user_id = $1`,
          [decoded.userId]
        );
        logger.warn(
          { userId: decoded.userId },
          'Refresh token reuse detected — all sessions invalidated'
        );
      }
      throw new AppError('Invalid refresh token', 401);
    }

    // Get user
    const userResult = await query(
      `SELECT id, email FROM users WHERE id = $1`,
      [decoded.userId]
    );

    if (userResult.rows.length === 0) {
      throw new AppError('User not found', 401);
    }

    const user = userResult.rows[0];

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

    // Generate new access token
    const accessToken = jwt.sign(
      { userId: user.id, email: user.email },
      config.jwt.secret,
      { expiresIn: config.jwt.expiresIn }
    );

    // Generate new refresh token (rotation)
    const newRefreshToken = jwt.sign(
      { userId: user.id },
      config.jwt.refreshSecret,
      { expiresIn: config.jwt.refreshExpiresIn }
    );

    // Store the new hashed refresh token
    const expiresAt = new Date(Date.now() + REFRESH_TOKEN_EXPIRY_MS);

    await query(
      `INSERT INTO refresh_tokens (user_id, token, expires_at)
       VALUES ($1, $2, $3)`,
      [user.id, hashRefreshToken(newRefreshToken), expiresAt]
    );

    res.json({ accessToken, refreshToken: newRefreshToken });
  } catch (error) {
    next(error);
  }
});

// Logout — refreshToken is optional (allows logout with just an access token)
const logoutSchema = Joi.object({
  refreshToken: Joi.string().optional(),
}).rename('refresh_token', 'refreshToken', { ignoreUndefined: true, override: false });

router.post('/logout', refreshRateLimiter, validate(logoutSchema), async (req, res, next) => {
  try {
    const { refreshToken } = req.body;

    let userId: string | undefined;

    // Blacklist the current access token using its actual remaining TTL
    const authHeader = req.headers.authorization;
    if (authHeader?.startsWith('Bearer ')) {
      const accessToken = authHeader.substring(7);
      try {
        await blacklistTokenAuto(accessToken);
      } catch (blacklistError) {
        // Best-effort: don't block logout if Redis/blacklist fails
        logger.warn({ error: blacklistError }, 'Failed to blacklist access token during logout');
      }
    }

    if (refreshToken) {
      // Get user ID from refresh token before deleting (lookup by hash)
      const tokenHash = hashRefreshToken(refreshToken);
      const tokenResult = await query(
        `SELECT user_id FROM refresh_tokens WHERE token = $1`,
        [tokenHash]
      );

      if (tokenResult.rows.length > 0) {
        userId = tokenResult.rows[0].user_id;
      }

      await query(
        `DELETE FROM refresh_tokens WHERE token = $1`,
        [tokenHash]
      );

      // Invalidate any unused password reset tokens for this user
      if (userId) {
        await query(
          `UPDATE password_reset_tokens SET used = TRUE WHERE user_id = $1 AND used = FALSE`,
          [userId]
        );
      }
    }

    // Audit log: logout
    if (userId) {
      await AuditService.logAuth({
        action: 'auth.logout',
        userId,
        ipAddress: getIpAddress(req),
        userAgent: req.get('user-agent'),
        success: true,
      });
    }

    res.json({ message: 'Logged out successfully' });
  } catch (error) {
    next(error);
  }
});

// Logout all devices — requires authentication
router.post('/logout-all', authenticate, async (req, res, next) => {
  try {
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

    // Audit log
    await AuditService.logAuth({
      action: 'auth.logout_all',
      userId: req.user!.id,
      ipAddress: getIpAddress(req),
      userAgent: req.get('user-agent'),
      success: true,
    });

    res.json({ message: 'All sessions logged out successfully' });
  } catch (error) {
    next(error);
  }
});

// Forgot password - request reset
router.post('/forgot-password', passwordResetRateLimiter, validate(forgotPasswordSchema), async (req, res, next) => {
  try {
    const { email } = req.body;

    const result = await query(
      `SELECT id, email, full_name FROM users WHERE email = $1`,
      [email.toLowerCase()]
    );

    // Always return success to prevent email enumeration
    if (result.rows.length === 0) {
      res.json({ message: 'If an account exists with that email, a reset link has been sent.' });
      return;
    }

    const user = result.rows[0];

    // Invalidate any existing reset tokens
    await query(
      `UPDATE password_reset_tokens SET used = TRUE WHERE user_id = $1 AND used = FALSE`,
      [user.id]
    );

    // Generate reset token
    const resetToken = crypto.randomBytes(32).toString('hex');
    const expiresAt = new Date();
    expiresAt.setHours(expiresAt.getHours() + 1); // 1 hour expiry

    await query(
      `INSERT INTO password_reset_tokens (user_id, token, expires_at)
       VALUES ($1, $2, $3)`,
      [user.id, hashRefreshToken(resetToken), expiresAt]
    );

    // Send password reset email
    const resetUrl = `${config.app.frontendUrl}/reset-password?token=${resetToken}`;

    logger.info({ userId: user.id }, 'Password reset requested');

    // Fire-and-forget: don't block the HTTP response on email delivery
    EmailService.sendPasswordResetEmail({
      to: user.email,
      user_name: user.full_name || 'there',
      reset_url: resetUrl,
    }).catch((emailError) => {
      logger.error({ error: emailError, userId: user.id }, 'Failed to send password reset email');
    });

    // Audit log: password reset requested
    await AuditService.logAuth({
      action: 'auth.password_reset_request',
      userId: user.id,
      email: user.email,
      ipAddress: getIpAddress(req),
      userAgent: req.get('user-agent'),
      success: true,
    });

    res.json({ message: 'If an account exists with that email, a reset link has been sent.' });
  } catch (error) {
    next(error);
  }
});

// Reset password with token
router.post('/reset-password', authRateLimiter, validate(resetPasswordSchema), async (req, res, next) => {
  try {
    const { token, newPassword } = req.body;

    // Hash the token for lookup (reset tokens are stored as SHA-256 hashes)
    const tokenHash = hashRefreshToken(token);

    // Atomically find and mark the reset token as used in a single query
    // to prevent race conditions with concurrent reset requests
    const tokenResult = await query(
      `UPDATE password_reset_tokens
       SET used = TRUE
       WHERE token = $1 AND expires_at > NOW() AND used = FALSE
       RETURNING user_id`,
      [tokenHash]
    );

    if (tokenResult.rows.length === 0) {
      throw new AppError('Invalid or expired reset token', 400);
    }

    const userId = tokenResult.rows[0].user_id;

    // Hash new password
    const passwordHash = await bcrypt.hash(newPassword, 12);

    // Update password
    await query(
      `UPDATE users SET password_hash = $1 WHERE id = $2`,
      [passwordHash, userId]
    );

    // Invalidate all refresh tokens
    await query(
      `DELETE FROM refresh_tokens WHERE user_id = $1`,
      [userId]
    );

    // Blacklist the caller's access token if present
    const authHeader = req.headers.authorization;
    if (authHeader?.startsWith('Bearer ')) {
      try {
        await blacklistTokenAuto(authHeader.substring(7));
      } catch {
        // Best-effort
      }
    }

    // Audit log: password reset completed
    await AuditService.logAuth({
      action: 'auth.password_reset_complete',
      userId,
      ipAddress: getIpAddress(req),
      userAgent: req.get('user-agent'),
      success: true,
    });

    res.json({ message: 'Password has been reset successfully' });
  } catch (error) {
    next(error);
  }
});

// Verify email
router.post('/verify-email', authRateLimiter, validate(verifyEmailSchema), async (req, res, next) => {
  try {
    const { token } = req.body;

    // Atomically consume the verification token and get user_id
    const tokenResult = await query(
      `DELETE FROM email_verification_tokens
       WHERE token = $1 AND expires_at > NOW()
       RETURNING user_id`,
      [token]
    );

    if (tokenResult.rows.length === 0) {
      throw new AppError('Invalid or expired verification token', 400);
    }

    const userId = tokenResult.rows[0].user_id;

    // Mark email as verified and clean up any remaining tokens for this user
    await Promise.all([
      query(`UPDATE users SET email_verified = TRUE WHERE id = $1`, [userId]),
      query(`DELETE FROM email_verification_tokens WHERE user_id = $1`, [userId]),
    ]);

    // Audit log: email verified
    await AuditService.logAuth({
      action: 'auth.email_verify',
      userId,
      ipAddress: getIpAddress(req),
      userAgent: req.get('user-agent'),
      success: true,
    });

    res.json({ message: 'Email verified successfully' });
  } catch (error) {
    next(error);
  }
});

// Google OAuth — accept ID token from mobile, verify, create/find user, return JWT
const googleOAuthSchema = Joi.object({
  idToken: Joi.string().required(),
  referralCode: Joi.string().optional(),
});

router.post('/google', authRateLimiter, validate(googleOAuthSchema), async (req, res, next) => {
  try {
    if (!config.google?.clientId) {
      throw new AppError('Google OAuth is not configured', 501);
    }

    const { idToken, referralCode } = req.body;

    // Verify the Google ID token (lazy-init singleton)
    if (!googleOAuth2Client) {
      const { OAuth2Client } = await import('google-auth-library');
      googleOAuth2Client = new OAuth2Client(config.google.clientId);
    }
    const oauthClient = googleOAuth2Client;

    const ticket = await oauthClient.verifyIdToken({
      idToken,
      audience: config.google?.clientId,
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
    const avatarUrl = payload.picture || null;

    // Find or create user
    let userResult = await query(
      `SELECT id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
              referred_by, referral_code, is_admin, created_at, updated_at,
              (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = users.id AND p.is_active = TRUE)) as is_partner
       FROM users WHERE email = $1`,
      [email]
    );

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
          `INSERT INTO users (email, full_name, avatar_url, auth_provider, email_verified, referral_code, referred_by)
           VALUES ($1, $2, $3, 'google', TRUE, $4, $5)
           RETURNING id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
                     referred_by, referral_code, is_admin, created_at, updated_at`,
          [email, fullName, avatarUrl, userReferralCode, referredBy]
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
        await txClient.query('ROLLBACK');
        throw txError;
      } finally {
        txClient.release();
      }
    } else {
      user = userResult.rows[0];
    }

    // Generate tokens
    const accessToken = jwt.sign(
      { userId: user.id, email: user.email },
      config.jwt.secret,
      { expiresIn: config.jwt.expiresIn }
    );

    const refreshToken = jwt.sign(
      { userId: user.id },
      config.jwt.refreshSecret,
      { expiresIn: config.jwt.refreshExpiresIn }
    );

    const expiresAt = new Date(Date.now() + REFRESH_TOKEN_EXPIRY_MS);

    await query(
      `INSERT INTO refresh_tokens (user_id, token, expires_at)
       VALUES ($1, $2, $3)`,
      [user.id, hashRefreshToken(refreshToken), expiresAt]
    );

    // Audit log: OAuth login
    await AuditService.logAuth({
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

    res.json({
      user: {
        id: user.id,
        email: user.email,
        full_name: user.full_name,
        avatar_url: user.avatar_url || null,
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
    });
  } catch (error) {
    next(error);
  }
});

// Apple OAuth — accept ID token from mobile, verify, create/find user, return JWT
const appleOAuthSchema = Joi.object({
  idToken: Joi.string().required(),
  fullName: Joi.string().optional(),
  referralCode: Joi.string().optional(),
});

router.post('/apple', authRateLimiter, validate(appleOAuthSchema), async (req, res, next) => {
  try {
    if (!config.apple?.bundleId) {
      throw new AppError('Apple Sign-In is not configured', 501);
    }

    const { idToken, fullName: appleFullName, referralCode } = req.body;

    // Verify Apple ID token against Apple's public keys (JWKS, lazy-init singleton)
    if (!appleJwksClientInstance) {
      const jwksClient = await import('jwks-rsa');
      appleJwksClientInstance = jwksClient.default({
        jwksUri: 'https://appleid.apple.com/auth/keys',
        cache: true,
        cacheMaxAge: 86400000, // 24 hours
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

    // Verify the token signature and claims
    const decoded = jwt.verify(idToken, publicKey, {
      algorithms: ['RS256'],
      issuer: 'https://appleid.apple.com',
      audience: config.apple.bundleId,
    }) as {
      sub: string;
      email?: string;
      email_verified?: boolean;
      aud?: string;
    };

    if (!decoded || !decoded.sub) {
      throw new AppError('Invalid Apple token', 401);
    }

    const appleUserId = decoded.sub;
    let email = decoded.email?.toLowerCase();

    // Find or create user — first try by email, then by apple_user_id
    let userResult;

    if (email) {
      userResult = await query(
        `SELECT id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
                referred_by, referral_code, is_admin, created_at, updated_at,
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
                referred_by, referral_code, is_admin, created_at, updated_at,
                (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = users.id AND p.is_active = TRUE)) as is_partner
         FROM users WHERE apple_user_id = $1`,
        [appleUserId]
      );
      if (appleIdResult.rows.length > 0) {
        userResult = appleIdResult;
        email = appleIdResult.rows[0].email;
      }
    }

    if (!email) {
      throw new AppError('Email not provided by Apple. Please grant email permission.', 401);
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
        await txClient.query('ROLLBACK');
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

    // Generate tokens
    const accessToken = jwt.sign(
      { userId: user.id, email: user.email },
      config.jwt.secret,
      { expiresIn: config.jwt.expiresIn }
    );

    const refreshToken = jwt.sign(
      { userId: user.id },
      config.jwt.refreshSecret,
      { expiresIn: config.jwt.refreshExpiresIn }
    );

    const expiresAt = new Date(Date.now() + REFRESH_TOKEN_EXPIRY_MS);

    await query(
      `INSERT INTO refresh_tokens (user_id, token, expires_at)
       VALUES ($1, $2, $3)`,
      [user.id, hashRefreshToken(refreshToken), expiresAt]
    );

    // Audit log: OAuth login
    await AuditService.logAuth({
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

    res.json({
      user: {
        id: user.id,
        email: user.email,
        full_name: user.full_name,
        avatar_url: user.avatar_url || null,
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
    });
  } catch (error) {
    next(error);
  }
});

export default router;
