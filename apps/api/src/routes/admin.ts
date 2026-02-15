import { Router } from 'express';
import { query } from '../db';
import { authenticate, requireAdmin } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { paginationSchema } from '../validators';
import { userIdParamSchema, dateRangeQuerySchema } from '../validators/admin.validator';
import { AppError } from '../utils/errors';
import { AuditService } from '../services/audit.service';

const router = Router();
router.use(authenticate);

// Current user info (accessible to admins AND partners)
router.get('/me', (req, res) => {
  res.json({
    user: {
      id: req.user!.id,
      email: req.user!.email,
      plan: req.user!.plan,
      isAdmin: req.user!.isAdmin,
      isPartner: req.user!.isPartner,
    },
  });
});

// All routes below require admin
router.use(requireAdmin);

// Admin stats overview (basic)
router.get('/stats', async (req, res, next) => {
  try {
    const stats = await query(`
      SELECT
        (SELECT COUNT(*) FROM users) as total_users,
        (SELECT COUNT(*) FROM users WHERE plan = 'premium') as premium_users,
        (SELECT COUNT(*) FROM items) as total_items,
        (SELECT COALESCE(SUM(price), 0) FROM items) as total_value,
        (SELECT COUNT(*) FROM partners WHERE is_active = TRUE) as active_partners,
        (SELECT COUNT(*) FROM partner_gifts) as total_gifts,
        (SELECT COUNT(*) FROM warranty_claims) as total_claims
    `);
    res.json({ stats: stats.rows[0] });
  } catch (error) {
    next(error);
  }
});

// Full admin stats (dashboard overview)
router.get('/stats/full', async (req, res, next) => {
  try {
    const stats = await query(`
      SELECT
        (SELECT COUNT(*) FROM users) AS total_users,
        (SELECT COUNT(*) FROM users WHERE plan = 'premium') AS premium_users,
        (SELECT COUNT(*) FROM items) AS total_items,
        (SELECT COUNT(*) FROM items WHERE created_at >= NOW() - INTERVAL '24 hours') AS items_last_24h,
        (SELECT COUNT(*) FROM users WHERE created_at >= NOW() - INTERVAL '24 hours') AS signups_last_24h,
        (SELECT COUNT(*) FROM users WHERE created_at >= NOW() - INTERVAL '7 days') AS signups_last_7d,
        (SELECT COUNT(*) FROM users WHERE created_at >= NOW() - INTERVAL '30 days') AS signups_last_30d,
        (SELECT COALESCE(SUM(price), 0) FROM items) AS total_value_protected,
        (SELECT COUNT(DISTINCT ua.user_id) FROM user_analytics ua WHERE ua.last_active_at >= NOW() - INTERVAL '24 hours') AS dau,
        (SELECT COUNT(DISTINCT ua.user_id) FROM user_analytics ua WHERE ua.last_active_at >= NOW() - INTERVAL '7 days') AS wau,
        (SELECT COUNT(DISTINCT ua.user_id) FROM user_analytics ua WHERE ua.last_active_at >= NOW() - INTERVAL '30 days') AS mau
    `);
    res.json({ stats: stats.rows[0] });
  } catch (error) {
    next(error);
  }
});

// Daily signups for charts
router.get('/stats/daily-signups', validate(dateRangeQuerySchema, 'query'), async (req, res, next) => {
  try {
    const days = (req.query.days as any) || 30;
    const result = await query(`
      SELECT
        DATE(created_at) AS date,
        COUNT(*) AS count
      FROM users
      WHERE created_at >= NOW() - MAKE_INTERVAL(days => $1)
      GROUP BY DATE(created_at)
      ORDER BY date ASC
    `, [days]);
    res.json({ data: result.rows });
  } catch (error) {
    next(error);
  }
});

// Daily items for charts
router.get('/stats/daily-items', validate(dateRangeQuerySchema, 'query'), async (req, res, next) => {
  try {
    const days = (req.query.days as any) || 30;
    const result = await query(`
      SELECT
        DATE(created_at) AS date,
        COUNT(*) AS count
      FROM items
      WHERE created_at >= NOW() - MAKE_INTERVAL(days => $1)
      GROUP BY DATE(created_at)
      ORDER BY date ASC
    `, [days]);
    res.json({ data: result.rows });
  } catch (error) {
    next(error);
  }
});

// User activity list
router.get('/users/activity', async (req, res, next) => {
  try {
    const result = await query(`
      SELECT
        u.id,
        u.email,
        u.full_name,
        u.plan,
        u.created_at,
        COUNT(DISTINCT i.id)::int AS total_items,
        COALESCE(SUM(i.price), 0)::numeric AS total_value,
        MAX(GREATEST(i.created_at, i.updated_at)) AS last_activity
      FROM users u
      LEFT JOIN items i ON i.user_id = u.id AND i.is_archived = FALSE
      GROUP BY u.id, u.email, u.full_name, u.plan, u.created_at
      ORDER BY u.created_at DESC
      LIMIT 500
    `);
    res.json({ users: result.rows });
  } catch (error) {
    next(error);
  }
});

// Admin user listing with pagination
router.get('/users', validate(paginationSchema, 'query'), async (req, res, next) => {
  try {
    const { page, limit } = req.query as any;
    const offset = (page - 1) * limit;

    const [result, countResult] = await Promise.all([
      query(
        `SELECT * FROM user_stats ORDER BY created_at DESC LIMIT $1 OFFSET $2`,
        [limit, offset]
      ),
      query(`SELECT COUNT(*) FROM users`),
    ]);

    const total = parseInt(countResult.rows[0].count, 10);

    res.json({
      users: result.rows,
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    });
  } catch (error) {
    next(error);
  }
});

// Suspend user (downgrade to free and invalidate all sessions)
router.put('/users/:id/suspend', validate(userIdParamSchema, 'params'), async (req, res, next) => {
  try {
    const { id } = req.params;

    // Check if target user exists and whether they are an admin
    const targetUser = await query(
      `SELECT id, email, is_admin FROM users WHERE id = $1`,
      [id]
    );

    if (targetUser.rows.length === 0) {
      throw new AppError('User not found', 404);
    }

    if (targetUser.rows[0].is_admin) {
      throw new AppError('Cannot suspend an admin user', 400);
    }

    await query(
      `UPDATE users SET plan = 'suspended', updated_at = NOW() WHERE id = $1`,
      [id]
    );

    // Invalidate all refresh tokens so the suspended user gets signed out
    await query(`DELETE FROM refresh_tokens WHERE user_id = $1`, [id]);

    await AuditService.logFromRequest(req, 'admin.settings_change', {
      severity: 'warning',
      resourceType: 'user',
      resourceId: id,
      description: `Admin suspended user: ${targetUser.rows[0].email}`,
    });

    res.json({ success: true, message: 'User suspended', user: { id, email: targetUser.rows[0].email } });
  } catch (error) {
    next(error);
  }
});

// Unsuspend user (restore to free plan, user can verify premium separately)
router.put('/users/:id/unsuspend', validate(userIdParamSchema, 'params'), async (req, res, next) => {
  try {
    const { id } = req.params;

    const result = await query(
      `UPDATE users SET plan = 'free', updated_at = NOW() WHERE id = $1 AND plan = 'suspended' RETURNING id, email`,
      [id]
    );

    if (result.rows.length === 0) {
      // Check if user exists at all
      const userExists = await query(`SELECT id, plan FROM users WHERE id = $1`, [id]);
      if (userExists.rows.length === 0) {
        throw new AppError('User not found', 404);
      }
      throw new AppError(`User is not suspended (current plan: ${userExists.rows[0].plan})`, 400);
    }

    await AuditService.logFromRequest(req, 'admin.settings_change', {
      severity: 'info',
      resourceType: 'user',
      resourceId: id,
      description: `Admin unsuspended user: ${result.rows[0].email}`,
    });

    res.json({ success: true, message: 'User unsuspended', user: result.rows[0] });
  } catch (error) {
    next(error);
  }
});

// Delete user (cascades via FK constraints)
// Note: Even if the user has an active access token, the authenticate middleware
// fetches the user from DB on every request — once the user row is deleted,
// any subsequent API call with the old token will fail with "Invalid token".
router.delete('/users/:id', validate(userIdParamSchema, 'params'), async (req, res, next) => {
  try {
    const { id } = req.params;

    // Prevent admin from deleting their own account
    if (id === req.user!.id) {
      throw new AppError('Cannot delete your own account', 400);
    }

    // Delete refresh tokens first (prevents token refresh after deletion)
    await query(`DELETE FROM refresh_tokens WHERE user_id = $1`, [id]);

    // Delete user (FK cascades handle items, homes, documents, etc.)
    const result = await query(
      `DELETE FROM users WHERE id = $1 RETURNING id, email`,
      [id]
    );

    if (result.rows.length === 0) {
      throw new AppError('User not found', 404);
    }

    await AuditService.logFromRequest(req, 'admin.user_delete', {
      severity: 'critical',
      resourceType: 'user',
      resourceId: id,
      description: `Admin deleted user: ${result.rows[0].email}`,
    });

    res.json({ success: true, message: 'User deleted', user: result.rows[0] });
  } catch (error) {
    next(error);
  }
});

export default router;
