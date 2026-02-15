import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { query } from '../db';
import { authenticate } from '../middleware/auth';
import { AppError } from '../middleware/errorHandler';
import { validate } from '../middleware/validate';
import { updateUserSchema, pushTokenSchema } from '../validators';
import { changePasswordSchema, deleteAccountSchema } from '../validators/users.validator';
import { blacklistTokenAuto } from '../utils/token-blacklist';
import { config } from '../config';
import { logger } from '../utils/logger';
import { AuditService } from '../services/audit.service';

const router = Router();
router.use(authenticate);

// Get current user profile
router.get('/me', async (req, res, next) => {
  try {
    const result = await query(
      `SELECT id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
              referred_by, referral_code, created_at, updated_at
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
    const updates: string[] = [];
    const values: any[] = [];
    let paramIndex = 1;

    if (fullName !== undefined) {
      updates.push(`full_name = $${paramIndex++}`);
      values.push(fullName);
    }

    if (avatarUrl !== undefined) {
      updates.push(`avatar_url = $${paramIndex++}`);
      values.push(avatarUrl);
    }

    if (updates.length === 0) {
      throw new AppError('No fields to update', 400);
    }

    values.push(req.user!.id);

    const result = await query(
      `UPDATE users SET
        ${updates.join(', ')},
        updated_at = NOW()
       WHERE id = $${paramIndex}
       RETURNING id, email, full_name, avatar_url, plan`,
      values
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

// Verify premium subscription via RevenueCat
router.post('/me/verify-premium', async (req, res, next) => {
  try {
    const { revenueCatAppUserId } = req.body;

    if (!revenueCatAppUserId || typeof revenueCatAppUserId !== 'string') {
      throw new AppError('revenueCatAppUserId is required', 400);
    }

    const rcApiKey = config.revenuecat.apiKey;
    if (!rcApiKey) {
      throw new AppError('RevenueCat is not configured on this server', 503);
    }

    // Call RevenueCat REST API to get subscriber info
    const rcResponse = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(revenueCatAppUserId)}`,
      {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${rcApiKey}`,
          'Content-Type': 'application/json',
        },
      }
    );

    if (!rcResponse.ok) {
      const errorBody = await rcResponse.text();
      logger.error({ statusCode: rcResponse.status, body: errorBody }, 'RevenueCat API error');
      throw new AppError('Failed to verify subscription with RevenueCat', 502);
    }

    const rcData = await rcResponse.json() as {
      subscriber: {
        entitlements: Record<string, {
          expires_date: string | null;
          purchase_date: string;
          product_identifier: string;
        }>;
      };
    };

    // Check for active premium entitlement
    const premiumEntitlement = rcData.subscriber?.entitlements?.premium;
    let isPremium = false;
    let expiresAt: string | null = null;

    if (premiumEntitlement) {
      const expiresDate = premiumEntitlement.expires_date;
      if (expiresDate === null) {
        // Lifetime / non-expiring entitlement
        isPremium = true;
      } else {
        isPremium = new Date(expiresDate) > new Date();
        expiresAt = expiresDate;
      }
    }

    // Update user plan in the database
    const prevPlanResult = await query(
      `SELECT plan FROM users WHERE id = $1`,
      [req.user!.id]
    );
    const previousPlan = prevPlanResult.rows[0]?.plan;

    const newPlan = isPremium ? 'premium' : 'free';
    const result = await query(
      `UPDATE users SET
        plan = $1,
        plan_expires_at = $2,
        updated_at = NOW()
       WHERE id = $3
       RETURNING id, email, plan, plan_expires_at`,
      [newPlan, expiresAt, req.user!.id]
    );

    if (result.rows.length === 0) {
      throw new AppError('User not found', 404);
    }

    if (previousPlan && previousPlan !== newPlan) {
      const action =
        newPlan === 'premium' ? 'user.plan_upgrade' : 'user.plan_downgrade';
      await AuditService.logFromRequest(req, action, {
        resourceType: 'user',
        resourceId: result.rows[0].id,
        description:
          newPlan === 'premium'
            ? 'Upgraded to premium'
            : 'Downgraded to free',
        metadata: {
          previous_plan: previousPlan,
          new_plan: newPlan,
          expires_at: expiresAt,
        },
      });
    }

    logger.info(
      { userId: req.user!.id, plan: newPlan, expiresAt },
      'Premium verification completed'
    );

    res.json({
      success: true,
      data: {
        plan: result.rows[0].plan,
        planExpiresAt: result.rows[0].plan_expires_at,
        verified: true,
      },
    });
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

    if (!userResult.rows[0].password_hash) {
      throw new AppError('Password is not set for this account', 400);
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

    // Blacklist the current access token using its actual remaining TTL
    const authHeader = req.headers.authorization;
    if (authHeader?.startsWith('Bearer ')) {
      const accessToken = authHeader.substring(7);
      await blacklistTokenAuto(accessToken);
    }

    // Invalidate all refresh tokens (force re-login on other devices)
    await query(
      `DELETE FROM refresh_tokens WHERE user_id = $1`,
      [req.user!.id]
    );

    // Audit log: password changed
    await AuditService.logFromRequest(req, 'user.update', {
      resourceType: 'user',
      resourceId: req.user!.id,
      description: 'Password changed',
    });

    res.json({ message: 'Password changed successfully' });
  } catch (error) {
    next(error);
  }
});

// Delete account
// For email users: requires password confirmation.
// For OAuth users (no password): requires confirmDelete=true in body.
router.delete('/me', async (req, res, next) => {
  try {
    const { password, confirmDelete } = req.body || {};

    // Get user info to determine auth method
    const userResult = await query(
      `SELECT password_hash, auth_provider FROM users WHERE id = $1`,
      [req.user!.id]
    );

    if (userResult.rows.length === 0) {
      throw new AppError('User not found', 404);
    }

    const user = userResult.rows[0];

    if (user.password_hash) {
      // Email user: require password confirmation
      if (!password) {
        throw new AppError('Password is required to delete your account', 400);
      }
      const valid = await bcrypt.compare(password, user.password_hash);
      if (!valid) {
        throw new AppError('Invalid password', 401);
      }
    } else {
      // OAuth user: require explicit confirmation flag
      if (confirmDelete !== true) {
        throw new AppError('Please confirm account deletion by setting confirmDelete to true', 400);
      }
    }

    // Delete user (cascades to all related data)
    await query(`DELETE FROM users WHERE id = $1`, [req.user!.id]);

    await AuditService.logFromRequest(req, 'user.delete', {
      resourceType: 'user',
      resourceId: req.user!.id,
      description: 'User deleted account',
    });

    res.json({ message: 'Account deleted successfully' });
  } catch (error) {
    next(error);
  }
});

export default router;
