import { Router } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { query } from '../db';
import { config } from '../config';
import { AppError } from '../middleware/errorHandler';
import { authRateLimiter } from '../middleware/rateLimiter';
import { validate } from '../middleware/validate';
import { registerSchema, loginSchema, refreshTokenSchema } from '../validators';

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

export default router;
