import { Router } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { query } from '../db';
import { config } from '../config';
import { AppError } from '../middleware/errorHandler';
import { authRateLimiter } from '../middleware/rateLimiter';
import { validate } from '../middleware/validate';
import { registerSchema, loginSchema, refreshTokenSchema } from '../validators';
import { forgotPasswordSchema, resetPasswordSchema, verifyEmailSchema } from '../validators/auth.validator';
import { logger } from '../utils/logger';
import { AuditService } from '../services/audit.service';
import { blacklistToken } from '../utils/token-blacklist';

const router = Router();

// Helper to get IP address
const getIpAddress = (req: any): string => {
  return (
    (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() ||
    (req.headers['x-real-ip'] as string) ||
    req.socket.remoteAddress ||
    'unknown'
  );
};

// Register
router.post('/register', authRateLimiter, validate(registerSchema), async (req, res, next) => {
  try {
    const { email, password, fullName } = req.body;

    // Check if user exists
    const existing = await query(
      'SELECT id FROM users WHERE email = $1',
      [email.toLowerCase()]
    );

    if (existing.rows.length > 0) {
      throw new AppError('Email already registered', 409);
    }

    // Hash password with bcrypt rounds=12
    const passwordHash = await bcrypt.hash(password, 12);

    // Create user
    const result = await query(
      `INSERT INTO users (email, password_hash, full_name)
       VALUES ($1, $2, $3)
       RETURNING id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
                 referred_by, referral_code, is_admin, created_at, updated_at`,
      [email.toLowerCase(), passwordHash, fullName]
    );

    const user = result.rows[0];

    // Create default home
    await query(
      `INSERT INTO homes (user_id, name) VALUES ($1, $2)`,
      [user.id, 'My Home']
    );

    // Audit log: successful registration
    await AuditService.logAuth({
      action: 'auth.register',
      userId: user.id,
      email: user.email,
      ipAddress: getIpAddress(req),
      userAgent: req.get('user-agent'),
      success: true,
    });

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

    // Store refresh token
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 7);

    await query(
      `INSERT INTO refresh_tokens (user_id, token, expires_at)
       VALUES ($1, $2, $3)`,
      [user.id, refreshToken, expiresAt]
    );

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
        created_at: user.created_at,
        updated_at: user.updated_at,
      },
      accessToken,
      refreshToken,
    });
  } catch (error) {
    // Audit log: failed registration
    await AuditService.logAuth({
      action: 'auth.register',
      email: req.body.email,
      ipAddress: getIpAddress(req),
      userAgent: req.get('user-agent'),
      success: false,
      errorMessage: error instanceof Error ? error.message : 'Registration failed',
    });
    next(error);
  }
});

// Login
router.post('/login', authRateLimiter, validate(loginSchema), async (req, res, next) => {
  try {
    const { email, password } = req.body;

    // Get user
    const result = await query(
      `SELECT id, email, password_hash, full_name, avatar_url, auth_provider, plan,
              plan_expires_at, referred_by, referral_code, is_admin, created_at, updated_at
       FROM users WHERE email = $1`,
      [email.toLowerCase()]
    );

    if (result.rows.length === 0) {
      throw new AppError('Invalid credentials', 401);
    }

    const user = result.rows[0];

    // Verify password
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
      throw new AppError('Invalid credentials', 401);
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

    // Store refresh token
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 7);

    await query(
      `INSERT INTO refresh_tokens (user_id, token, expires_at)
       VALUES ($1, $2, $3)`,
      [user.id, refreshToken, expiresAt]
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
        created_at: user.created_at,
        updated_at: user.updated_at,
      },
      accessToken,
      refreshToken,
    });
  } catch (error) {
    // Audit log: failed login (user not found or other error)
    if (error instanceof AppError && error.statusCode === 401) {
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
router.post('/refresh', validate(refreshTokenSchema), async (req, res, next) => {
  try {
    const { refreshToken } = req.body;

    // Verify refresh token
    const decoded = jwt.verify(refreshToken, config.jwt.refreshSecret) as {
      userId: string;
    };

    // Check if token exists and not expired
    const tokenResult = await query(
      `SELECT user_id FROM refresh_tokens
       WHERE token = $1 AND expires_at > NOW()`,
      [refreshToken]
    );

    if (tokenResult.rows.length === 0) {
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

    // Generate new access token
    const accessToken = jwt.sign(
      { userId: user.id, email: user.email },
      config.jwt.secret,
      { expiresIn: config.jwt.expiresIn }
    );

    res.json({ accessToken });
  } catch (error) {
    next(error);
  }
});

// Logout
router.post('/logout', validate(refreshTokenSchema), async (req, res, next) => {
  try {
    const { refreshToken } = req.body;

    let userId: string | undefined;

    // Blacklist the current access token so it can't be reused
    const authHeader = req.headers.authorization;
    if (authHeader?.startsWith('Bearer ')) {
      const accessToken = authHeader.substring(7);
      // Blacklist for 1 hour (access token max lifetime)
      await blacklistToken(accessToken, 3600);
    }

    if (refreshToken) {
      // Get user ID from refresh token before deleting
      const tokenResult = await query(
        `SELECT user_id FROM refresh_tokens WHERE token = $1`,
        [refreshToken]
      );

      if (tokenResult.rows.length > 0) {
        userId = tokenResult.rows[0].user_id;
      }

      await query(
        `DELETE FROM refresh_tokens WHERE token = $1`,
        [refreshToken]
      );
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

// Forgot password - request reset
router.post('/forgot-password', authRateLimiter, validate(forgotPasswordSchema), async (req, res, next) => {
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
      [user.id, resetToken, expiresAt]
    );

    // In production, send email with reset link
    const resetUrl = `${config.app.frontendUrl}/reset-password?token=${resetToken}`;

    logger.info({ userId: user.id, resetUrl }, 'Password reset requested');

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

    // Find valid reset token
    const tokenResult = await query(
      `SELECT user_id FROM password_reset_tokens
       WHERE token = $1 AND expires_at > NOW() AND used = FALSE`,
      [token]
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

    // Mark token as used
    await query(
      `UPDATE password_reset_tokens SET used = TRUE WHERE token = $1`,
      [token]
    );

    // Invalidate all refresh tokens
    await query(
      `DELETE FROM refresh_tokens WHERE user_id = $1`,
      [userId]
    );

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
router.post('/verify-email', validate(verifyEmailSchema), async (req, res, next) => {
  try {
    const { token } = req.body;

    // Find valid verification token
    const tokenResult = await query(
      `SELECT user_id FROM email_verification_tokens
       WHERE token = $1 AND expires_at > NOW()`,
      [token]
    );

    if (tokenResult.rows.length === 0) {
      throw new AppError('Invalid or expired verification token', 400);
    }

    const userId = tokenResult.rows[0].user_id;

    // Mark email as verified
    await query(
      `UPDATE users SET email_verified = TRUE WHERE id = $1`,
      [userId]
    );

    // Clean up verification tokens
    await query(
      `DELETE FROM email_verification_tokens WHERE user_id = $1`,
      [userId]
    );

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
router.post('/google', authRateLimiter, async (req, res, next) => {
  try {
    if (!config.google?.clientId) {
      throw new AppError('Google OAuth is not configured', 501);
    }

    const { idToken } = req.body;

    if (!idToken || typeof idToken !== 'string') {
      throw new AppError('Google ID token is required', 400);
    }

    // Verify the Google ID token
    const { OAuth2Client } = await import('google-auth-library');
    const client = new OAuth2Client(config.google?.clientId);

    const ticket = await client.verifyIdToken({
      idToken,
      audience: config.google?.clientId,
    });

    const payload = ticket.getPayload();
    if (!payload || !payload.email) {
      throw new AppError('Invalid Google token', 401);
    }

    const email = payload.email.toLowerCase();
    const fullName = payload.name || 'User';
    const avatarUrl = payload.picture || null;

    // Find or create user
    let userResult = await query(
      `SELECT id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
              referred_by, referral_code, is_admin, created_at, updated_at
       FROM users WHERE email = $1`,
      [email]
    );

    let user;
    let isNewUser = false;

    if (userResult.rows.length === 0) {
      // Create new user (no password for OAuth users)
      const createResult = await query(
        `INSERT INTO users (email, full_name, avatar_url, auth_provider, email_verified)
         VALUES ($1, $2, $3, 'google', TRUE)
         RETURNING id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
                   referred_by, referral_code, is_admin, created_at, updated_at`,
        [email, fullName, avatarUrl]
      );
      user = createResult.rows[0];
      isNewUser = true;

      // Create default home
      await query(
        `INSERT INTO homes (user_id, name) VALUES ($1, $2)`,
        [user.id, 'My Home']
      );
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

    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 7);

    await query(
      `INSERT INTO refresh_tokens (user_id, token, expires_at)
       VALUES ($1, $2, $3)`,
      [user.id, refreshToken, expiresAt]
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
router.post('/apple', authRateLimiter, async (req, res, next) => {
  try {
    if (!config.apple?.bundleId) {
      throw new AppError('Apple Sign-In is not configured', 501);
    }

    const { idToken, fullName: appleFullName } = req.body;

    if (!idToken || typeof idToken !== 'string') {
      throw new AppError('Apple ID token is required', 400);
    }

    // Verify Apple ID token against Apple's public keys (JWKS)
    const jwksClient = await import('jwks-rsa');
    const appleJwksClient = jwksClient.default({
      jwksUri: 'https://appleid.apple.com/auth/keys',
      cache: true,
      cacheMaxAge: 86400000, // 24 hours
    });

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
    const email = decoded.email?.toLowerCase();

    if (!email) {
      throw new AppError('Email not provided by Apple', 401);
    }

    // Find or create user
    let userResult = await query(
      `SELECT id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
              referred_by, referral_code, is_admin, created_at, updated_at
       FROM users WHERE email = $1`,
      [email]
    );

    let user;
    let isNewUser = false;

    if (userResult.rows.length === 0) {
      const fullName = appleFullName || 'User';

      const createResult = await query(
        `INSERT INTO users (email, full_name, auth_provider, email_verified)
         VALUES ($1, $2, 'apple', TRUE)
         RETURNING id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
                   referred_by, referral_code, is_admin, created_at, updated_at`,
        [email, fullName]
      );
      user = createResult.rows[0];
      isNewUser = true;

      // Create default home
      await query(
        `INSERT INTO homes (user_id, name) VALUES ($1, $2)`,
        [user.id, 'My Home']
      );
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

    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 7);

    await query(
      `INSERT INTO refresh_tokens (user_id, token, expires_at)
       VALUES ($1, $2, $3)`,
      [user.id, refreshToken, expiresAt]
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
