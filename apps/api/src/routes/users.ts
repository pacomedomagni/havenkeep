import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { query } from '../db';
import { authenticate } from '../middleware/auth';
import { AppError } from '../middleware/errorHandler';
import { validate } from '../middleware/validate';
import { updateUserSchema, pushTokenSchema } from '../validators';
import { changePasswordSchema, deleteAccountSchema } from '../validators/users.validator';
import { blacklistToken } from '../utils/token-blacklist';

const router = Router();
router.use(authenticate);

// Get current user profile
router.get('/me', async (req, res, next) => {
  try {
    const result = await query(
      `SELECT id, email, full_name, avatar_url, plan, plan_expires_at, created_at
       FROM users WHERE id = $1`,
      [req.user!.id]
    );

    if (result.rows.length === 0) {
      throw new AppError('User not found', 404);
    }

    res.json({ user: result.rows[0] });
  } catch (error) {
    next(error);
  }
});

// Update user profile
router.put('/me', validate(updateUserSchema), async (req, res, next) => {
  try {
    const { fullName, avatarUrl } = req.body;
    const result = await query(
      `UPDATE users SET
        full_name = COALESCE($1, full_name),
        avatar_url = $2
       WHERE id = $3
       RETURNING id, email, full_name, avatar_url, plan`,
      [fullName, avatarUrl !== undefined ? avatarUrl : null, req.user!.id]
    );

    if (result.rows.length === 0) {
      throw new AppError('User not found', 404);
    }

    res.json({ user: result.rows[0] });
  } catch (error) {
    next(error);
  }
});

// Register push notification token
router.post('/push-token', validate(pushTokenSchema), async (req, res, next) => {
  try {
    const { fcmToken, platform } = req.body;

    await query(
      `INSERT INTO user_push_tokens (user_id, fcm_token, platform, updated_at)
       VALUES ($1, $2, $3, NOW())
       ON CONFLICT (user_id, fcm_token)
       DO UPDATE SET platform = $3, updated_at = NOW()`,
      [req.user!.id, fcmToken, platform || 'unknown']
    );

    res.json({ message: 'Push token registered' });
  } catch (error) {
    next(error);
  }
});

// Change password
router.put('/me/password', validate(changePasswordSchema), async (req, res, next) => {
  try {
    const { currentPassword, newPassword } = req.body;

    // Get current password hash
    const userResult = await query(
      `SELECT password_hash FROM users WHERE id = $1`,
      [req.user!.id]
    );

    if (userResult.rows.length === 0) {
      throw new AppError('User not found', 404);
    }

    // Verify current password
    const valid = await bcrypt.compare(currentPassword, userResult.rows[0].password_hash);
    if (!valid) {
      throw new AppError('Current password is incorrect', 401);
    }

    // Hash and update new password
    const newHash = await bcrypt.hash(newPassword, 12);
    await query(
      `UPDATE users SET password_hash = $1 WHERE id = $2`,
      [newHash, req.user!.id]
    );

    // Blacklist the current access token so it can't be reused
    const authHeader = req.headers.authorization;
    if (authHeader?.startsWith('Bearer ')) {
      const accessToken = authHeader.substring(7);
      await blacklistToken(accessToken, 3600);
    }

    // Invalidate all refresh tokens (force re-login on other devices)
    await query(
      `DELETE FROM refresh_tokens WHERE user_id = $1`,
      [req.user!.id]
    );

    res.json({ message: 'Password changed successfully' });
  } catch (error) {
    next(error);
  }
});

// Delete account
router.delete('/me', validate(deleteAccountSchema), async (req, res, next) => {
  try {
    const { password } = req.body;

    // Verify password before deletion
    const userResult = await query(
      `SELECT password_hash FROM users WHERE id = $1`,
      [req.user!.id]
    );

    if (userResult.rows.length === 0) {
      throw new AppError('User not found', 404);
    }

    if (!userResult.rows[0].password_hash) {
      throw new AppError('Cannot verify password for SSO accounts', 400);
    }
    const valid = await bcrypt.compare(password, userResult.rows[0].password_hash);
    if (!valid) {
      throw new AppError('Invalid password', 401);
    }

    // Delete user (cascades to all related data)
    await query(`DELETE FROM users WHERE id = $1`, [req.user!.id]);

    res.json({ message: 'Account deleted successfully' });
  } catch (error) {
    next(error);
  }
});

export default router;
