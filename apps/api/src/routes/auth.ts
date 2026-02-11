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

const router = Router();

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
      throw new AppError(409, 'Email already registered');
    }

    // Hash password with bcrypt rounds=12
    const passwordHash = await bcrypt.hash(password, 12);

    // Create user
    const result = await query(
      `INSERT INTO users (email, password_hash, full_name)
       VALUES ($1, $2, $3)
       RETURNING id, email, full_name, plan, created_at`,
      [email.toLowerCase(), passwordHash, fullName]
    );

    const user = result.rows[0];

    // Create default home
    await query(
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
        fullName: user.full_name,
        plan: user.plan,
      },
      accessToken,
      refreshToken,
    });
  } catch (error) {
    next(error);
  }
});

// Login
router.post('/login', authRateLimiter, validate(loginSchema), async (req, res, next) => {
  try {
    const { email, password } = req.body;

    // Get user
    const result = await query(
      `SELECT id, email, password_hash, full_name, plan, is_admin
       FROM users WHERE email = $1`,
      [email.toLowerCase()]
    );

    if (result.rows.length === 0) {
      throw new AppError(401, 'Invalid credentials');
    }

    const user = result.rows[0];

    // Verify password
    const valid = await bcrypt.compare(password, user.password_hash);

    if (!valid) {
      throw new AppError(401, 'Invalid credentials');
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

    res.json({
      user: {
        id: user.id,
        email: user.email,
        fullName: user.full_name,
        plan: user.plan,
        isAdmin: user.is_admin,
      },
      accessToken,
      refreshToken,
    });
  } catch (error) {
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
      throw new AppError(401, 'Invalid refresh token');
    }

    // Get user
    const userResult = await query(
      `SELECT id, email FROM users WHERE id = $1`,
      [decoded.userId]
    );

    if (userResult.rows.length === 0) {
      throw new AppError(401, 'User not found');
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

    if (refreshToken) {
      await query(
        `DELETE FROM refresh_tokens WHERE token = $1`,
        [refreshToken]
      );
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
      throw new AppError(400, 'Invalid or expired reset token');
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
      throw new AppError(400, 'Invalid or expired verification token');
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

    res.json({ message: 'Email verified successfully' });
  } catch (error) {
    next(error);
  }
});

// Google OAuth — accept ID token from mobile, verify, create/find user, return JWT
router.post('/google', authRateLimiter, async (req, res, next) => {
  try {
    const { idToken } = req.body;

    if (!idToken || typeof idToken !== 'string') {
      throw new AppError(400, 'Google ID token is required');
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
      throw new AppError(401, 'Invalid Google token');
    }

    const email = payload.email.toLowerCase();
    const fullName = payload.name || 'User';
    const avatarUrl = payload.picture || null;

    // Find or create user
    let userResult = await query(
      `SELECT id, email, full_name, plan, is_admin FROM users WHERE email = $1`,
      [email]
    );

    let user;

    if (userResult.rows.length === 0) {
      // Create new user (no password for OAuth users)
      const createResult = await query(
        `INSERT INTO users (email, full_name, avatar_url, auth_provider, email_verified)
         VALUES ($1, $2, $3, 'google', TRUE)
         RETURNING id, email, full_name, plan, is_admin`,
        [email, fullName, avatarUrl]
      );
      user = createResult.rows[0];

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

    res.json({
      user: {
        id: user.id,
        email: user.email,
        fullName: user.full_name,
        plan: user.plan,
        isAdmin: user.is_admin,
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
    const { idToken, fullName: appleFullName } = req.body;

    if (!idToken || typeof idToken !== 'string') {
      throw new AppError(400, 'Apple ID token is required');
    }

    // Decode Apple JWT (the idToken is a JWT itself)
    // In production, verify signature against Apple's public keys
    const decoded = jwt.decode(idToken) as {
      sub: string;
      email?: string;
      email_verified?: boolean;
    } | null;

    if (!decoded || !decoded.sub) {
      throw new AppError(401, 'Invalid Apple token');
    }

    const appleUserId = decoded.sub;
    const email = decoded.email?.toLowerCase();

    if (!email) {
      throw new AppError(401, 'Email not provided by Apple');
    }

    // Find or create user
    let userResult = await query(
      `SELECT id, email, full_name, plan, is_admin FROM users WHERE email = $1`,
      [email]
    );

    let user;

    if (userResult.rows.length === 0) {
      const fullName = appleFullName || 'User';

      const createResult = await query(
        `INSERT INTO users (email, full_name, auth_provider, email_verified)
         VALUES ($1, $2, 'apple', TRUE)
         RETURNING id, email, full_name, plan, is_admin`,
        [email, fullName]
      );
      user = createResult.rows[0];

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

    res.json({
      user: {
        id: user.id,
        email: user.email,
        fullName: user.full_name,
        plan: user.plan,
        isAdmin: user.is_admin,
      },
      accessToken,
      refreshToken,
    });
  } catch (error) {
    next(error);
  }
});

export default router;
