"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const db_1 = require("../db");
const auth_1 = require("../middleware/auth");
const validate_1 = require("../middleware/validate");
const validators_1 = require("../validators");
const admin_validator_1 = require("../validators/admin.validator");
const errors_1 = require("../utils/errors");
const audit_service_1 = require("../services/audit.service");
const redis_1 = require("../utils/redis");
const logger_1 = require("../utils/logger");
const response_1 = require("../utils/response");
const ADMIN_STATS_TTL = 60; // 60 seconds
const router = (0, express_1.Router)();
router.use(auth_1.authenticate);
// Current user info (accessible to admins AND partners)
router.get('/me', (req, res) => {
    (0, response_1.sendSuccess)(res, {
        id: req.user.id,
        email: req.user.email,
        plan: req.user.plan,
        is_admin: req.user.isAdmin,
        is_partner: req.user.isPartner,
    });
});
// All routes below require admin
router.use(auth_1.requireAdmin);
// Admin stats overview (basic)
router.get('/stats', async (req, res, next) => {
    try {
        // Check Redis cache first
        try {
            const redis = await (0, redis_1.getRedisClient)();
            const cached = await redis.get('admin:stats');
            if (cached) {
                return (0, response_1.sendSuccess)(res, JSON.parse(cached));
            }
        }
        catch (err) {
            logger_1.logger.warn({ err }, 'Redis cache read failed for admin:stats, falling back to DB');
        }
        const stats = await (0, db_1.query)(`
      SELECT
        (SELECT COUNT(*) FROM users) as total_users,
        (SELECT COUNT(*) FROM users WHERE plan = 'premium') as premium_users,
        (SELECT COUNT(*) FROM items) as total_items,
        (SELECT COALESCE(SUM(price), 0) FROM items) as total_value,
        (SELECT COUNT(*) FROM partners WHERE is_active = TRUE) as active_partners,
        (SELECT COUNT(*) FROM partner_gifts) as total_gifts,
        (SELECT COUNT(*) FROM warranty_claims) as total_claims
    `);
        // Cache the result in Redis with 60-second TTL
        try {
            const redis = await (0, redis_1.getRedisClient)();
            await redis.set('admin:stats', JSON.stringify(stats.rows[0]), { EX: ADMIN_STATS_TTL });
        }
        catch (err) {
            logger_1.logger.warn({ err }, 'Redis cache write failed for admin:stats');
        }
        (0, response_1.sendSuccess)(res, stats.rows[0]);
    }
    catch (error) {
        next(error);
    }
});
// Full admin stats (dashboard overview)
router.get('/stats/full', async (req, res, next) => {
    try {
        // Check Redis cache first
        try {
            const redis = await (0, redis_1.getRedisClient)();
            const cached = await redis.get('admin:stats:full');
            if (cached) {
                return (0, response_1.sendSuccess)(res, JSON.parse(cached));
            }
        }
        catch (err) {
            logger_1.logger.warn({ err }, 'Redis cache read failed for admin:stats:full, falling back to DB');
        }
        const stats = await (0, db_1.query)(`
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
        // Cache the result in Redis with 60-second TTL
        try {
            const redis = await (0, redis_1.getRedisClient)();
            await redis.set('admin:stats:full', JSON.stringify(stats.rows[0]), { EX: ADMIN_STATS_TTL });
        }
        catch (err) {
            logger_1.logger.warn({ err }, 'Redis cache write failed for admin:stats:full');
        }
        (0, response_1.sendSuccess)(res, stats.rows[0]);
    }
    catch (error) {
        next(error);
    }
});
// Daily signups for charts
router.get('/stats/daily-signups', (0, validate_1.validate)(admin_validator_1.dateRangeQuerySchema, 'query'), async (req, res, next) => {
    try {
        const days = req.query.days || 30;
        const result = await (0, db_1.query)(`
      SELECT
        DATE(created_at) AS date,
        COUNT(*) AS count
      FROM users
      WHERE created_at >= NOW() - MAKE_INTERVAL(days => $1)
      GROUP BY DATE(created_at)
      ORDER BY date ASC
    `, [days]);
        (0, response_1.sendSuccess)(res, result.rows);
    }
    catch (error) {
        next(error);
    }
});
// Daily items for charts
router.get('/stats/daily-items', (0, validate_1.validate)(admin_validator_1.dateRangeQuerySchema, 'query'), async (req, res, next) => {
    try {
        const days = req.query.days || 30;
        const result = await (0, db_1.query)(`
      SELECT
        DATE(created_at) AS date,
        COUNT(*) AS count
      FROM items
      WHERE created_at >= NOW() - MAKE_INTERVAL(days => $1)
      GROUP BY DATE(created_at)
      ORDER BY date ASC
    `, [days]);
        (0, response_1.sendSuccess)(res, result.rows);
    }
    catch (error) {
        next(error);
    }
});
// User activity list
router.get('/users/activity', async (req, res, next) => {
    try {
        const result = await (0, db_1.query)(`
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
        (0, response_1.sendSuccess)(res, result.rows);
    }
    catch (error) {
        next(error);
    }
});
// Admin user listing with pagination
router.get('/users', (0, validate_1.validate)(validators_1.paginationSchema, 'query'), async (req, res, next) => {
    try {
        const { page, limit } = req.query;
        // BE-1/2/3: Explicitly convert and clamp pagination params to safe integers
        const pageNum = Math.max(1, parseInt(page, 10) || 1);
        const limitNum = Math.min(100, Math.max(1, parseInt(limit, 10) || 20));
        const offset = (pageNum - 1) * limitNum;
        const [result, countResult] = await Promise.all([
            (0, db_1.query)(`SELECT * FROM user_stats ORDER BY created_at DESC LIMIT $1 OFFSET $2`, [limitNum, offset]),
            (0, db_1.query)(`SELECT COUNT(*) FROM users`),
        ]);
        const total = parseInt(countResult.rows[0].count, 10);
        (0, response_1.sendSuccess)(res, result.rows, {
            pagination: {
                page: pageNum,
                limit: limitNum,
                total,
                total_pages: Math.ceil(total / limitNum),
            },
        });
    }
    catch (error) {
        next(error);
    }
});
// Suspend user (downgrade to free and invalidate all sessions)
router.put('/users/:id/suspend', (0, validate_1.validate)(admin_validator_1.userIdParamSchema, 'params'), async (req, res, next) => {
    try {
        const { id } = req.params;
        // Check if target user exists and whether they are an admin
        const targetUser = await (0, db_1.query)(`SELECT id, email, is_admin FROM users WHERE id = $1`, [id]);
        if (targetUser.rows.length === 0) {
            throw new errors_1.AppError('User not found', 404);
        }
        if (targetUser.rows[0].is_admin) {
            throw new errors_1.AppError('Cannot suspend an admin user', 400);
        }
        await (0, db_1.query)(`UPDATE users SET plan = 'suspended', updated_at = NOW() WHERE id = $1`, [id]);
        // Invalidate all refresh tokens so the suspended user gets signed out
        await (0, db_1.query)(`DELETE FROM refresh_tokens WHERE user_id = $1`, [id]);
        await audit_service_1.AuditService.logFromRequest(req, 'admin.settings_change', {
            severity: 'warning',
            resourceType: 'user',
            resourceId: id,
            description: `Admin suspended user: ${targetUser.rows[0].email}`,
        });
        (0, response_1.sendSuccess)(res, { id, email: targetUser.rows[0].email }, { message: 'User suspended' });
    }
    catch (error) {
        next(error);
    }
});
// Unsuspend user (restore to free plan, user can verify premium separately)
router.put('/users/:id/unsuspend', (0, validate_1.validate)(admin_validator_1.userIdParamSchema, 'params'), async (req, res, next) => {
    try {
        const { id } = req.params;
        const result = await (0, db_1.query)(`UPDATE users SET plan = 'free', updated_at = NOW() WHERE id = $1 AND plan = 'suspended' RETURNING id, email`, [id]);
        if (result.rows.length === 0) {
            // Check if user exists at all
            const userExists = await (0, db_1.query)(`SELECT id, plan FROM users WHERE id = $1`, [id]);
            if (userExists.rows.length === 0) {
                throw new errors_1.AppError('User not found', 404);
            }
            throw new errors_1.AppError(`User is not suspended (current plan: ${userExists.rows[0].plan})`, 400);
        }
        await audit_service_1.AuditService.logFromRequest(req, 'admin.settings_change', {
            severity: 'info',
            resourceType: 'user',
            resourceId: id,
            description: `Admin unsuspended user: ${result.rows[0].email}`,
        });
        (0, response_1.sendSuccess)(res, result.rows[0], { message: 'User unsuspended' });
    }
    catch (error) {
        next(error);
    }
});
// Delete user (cascades via FK constraints)
// Note: Even if the user has an active access token, the authenticate middleware
// fetches the user from DB on every request — once the user row is deleted,
// any subsequent API call with the old token will fail with "Invalid token".
router.delete('/users/:id', (0, validate_1.validate)(admin_validator_1.userIdParamSchema, 'params'), async (req, res, next) => {
    try {
        const { id } = req.params;
        // Prevent admin from deleting their own account
        if (id === req.user.id) {
            throw new errors_1.AppError('Cannot delete your own account', 400);
        }
        // Delete refresh tokens first (prevents token refresh after deletion)
        await (0, db_1.query)(`DELETE FROM refresh_tokens WHERE user_id = $1`, [id]);
        // Delete user (FK cascades handle items, homes, documents, etc.)
        const result = await (0, db_1.query)(`DELETE FROM users WHERE id = $1 RETURNING id, email`, [id]);
        if (result.rows.length === 0) {
            throw new errors_1.AppError('User not found', 404);
        }
        await audit_service_1.AuditService.logFromRequest(req, 'admin.user_delete', {
            severity: 'critical',
            resourceType: 'user',
            resourceId: id,
            description: `Admin deleted user: ${result.rows[0].email}`,
        });
        (0, response_1.sendSuccess)(res, result.rows[0], { message: 'User deleted' });
    }
    catch (error) {
        next(error);
    }
});
// ========== PARTNER MANAGEMENT ==========
// List pending partners (is_active = false)
router.get('/partners/pending', async (req, res, next) => {
    try {
        const result = await (0, db_1.query)(`SELECT p.*, u.email, u.full_name
       FROM partners p
       JOIN users u ON u.id = p.user_id
       WHERE p.is_active = FALSE
       ORDER BY p.created_at DESC`);
        (0, response_1.sendSuccess)(res, result.rows);
    }
    catch (error) {
        next(error);
    }
});
// Approve a partner (set is_active = true)
router.put('/partners/:id/approve', (0, validate_1.validate)(admin_validator_1.userIdParamSchema, 'params'), async (req, res, next) => {
    try {
        const { id } = req.params;
        const result = await (0, db_1.query)(`UPDATE partners SET is_active = TRUE, updated_at = NOW()
       WHERE id = $1
       RETURNING *`, [id]);
        if (result.rows.length === 0) {
            throw new errors_1.AppError('Partner not found', 404);
        }
        await audit_service_1.AuditService.logFromRequest(req, 'admin.settings_change', {
            severity: 'info',
            resourceType: 'partner',
            resourceId: id,
            description: `Admin approved partner: ${result.rows[0].company_name || id}`,
        });
        (0, response_1.sendSuccess)(res, result.rows[0], { message: 'Partner approved' });
    }
    catch (error) {
        next(error);
    }
});
// Reject a partner (set is_active = false)
router.put('/partners/:id/reject', (0, validate_1.validate)(admin_validator_1.userIdParamSchema, 'params'), async (req, res, next) => {
    try {
        const { id } = req.params;
        const result = await (0, db_1.query)(`UPDATE partners SET is_active = FALSE, updated_at = NOW()
       WHERE id = $1
       RETURNING *`, [id]);
        if (result.rows.length === 0) {
            throw new errors_1.AppError('Partner not found', 404);
        }
        await audit_service_1.AuditService.logFromRequest(req, 'admin.settings_change', {
            severity: 'warning',
            resourceType: 'partner',
            resourceId: id,
            description: `Admin rejected partner: ${result.rows[0].company_name || id}`,
        });
        (0, response_1.sendSuccess)(res, result.rows[0], { message: 'Partner rejected' });
    }
    catch (error) {
        next(error);
    }
});
// ========== PARTNER & COMMISSION ADMIN ENDPOINTS ==========
// Paginated list of ALL partners with user info and aggregate counts
router.get('/partners', (0, validate_1.validate)(validators_1.paginationSchema, 'query'), async (req, res, next) => {
    try {
        const page = Math.max(1, parseInt(req.query.page, 10) || 1);
        const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 20));
        const offset = (page - 1) * limit;
        const conditions = [];
        const params = [];
        let paramIndex = 1;
        if (req.query.is_active !== undefined) {
            const isActive = req.query.is_active === 'true';
            conditions.push(`p.is_active = $${paramIndex++}`);
            params.push(isActive);
        }
        if (req.query.partner_type) {
            conditions.push(`p.partner_type = $${paramIndex++}`);
            params.push(req.query.partner_type);
        }
        const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
        const [result, countResult] = await Promise.all([
            (0, db_1.query)(`SELECT
          p.id,
          p.user_id,
          p.company_name,
          p.partner_type,
          p.phone,
          p.license_number,
          p.service_areas,
          p.brand_color,
          p.logo_url,
          p.stripe_account_id,
          p.stripe_onboarded,
          u.referral_code,
          p.is_active,
          p.created_at,
          p.updated_at,
          u.email,
          u.full_name,
          COALESCE(SUM(pc.amount), 0)::numeric AS total_commissions_earned,
          COUNT(DISTINCT pg.id)::int AS total_gifts,
          (SELECT COUNT(*) FROM users ref WHERE ref.referred_by = p.user_id)::int AS total_referrals
        FROM partners p
        JOIN users u ON u.id = p.user_id
        LEFT JOIN partner_commissions pc ON pc.partner_id = p.id
        LEFT JOIN partner_gifts pg ON pg.partner_id = p.id
        ${whereClause}
        GROUP BY p.id, u.email, u.full_name
        ORDER BY p.created_at DESC
        LIMIT $${paramIndex++} OFFSET $${paramIndex++}`, [...params, limit, offset]),
            (0, db_1.query)(`SELECT COUNT(*) FROM partners p ${whereClause}`, params),
        ]);
        const total = parseInt(countResult.rows[0].count, 10);
        (0, response_1.sendSuccess)(res, result.rows, {
            pagination: {
                page,
                limit,
                total,
                total_pages: Math.ceil(total / limit),
            },
        });
    }
    catch (error) {
        next(error);
    }
});
// Single partner detail with commission stats, gift count, referral count
router.get('/partners/:id', (0, validate_1.validate)(admin_validator_1.userIdParamSchema, 'params'), async (req, res, next) => {
    try {
        const { id } = req.params;
        const result = await (0, db_1.query)(`SELECT
        p.id,
        p.user_id,
        p.company_name,
        p.partner_type,
        p.phone,
        p.license_number,
        p.service_areas,
        p.brand_color,
        p.logo_url,
        p.stripe_account_id,
        p.stripe_onboarded,
        u.referral_code,
        p.is_active,
        p.created_at,
        p.updated_at,
        u.email,
        u.full_name,
        COALESCE(SUM(pc.amount) FILTER (WHERE pc.status = 'pending'), 0)::numeric AS total_pending_amount,
        COALESCE(SUM(pc.amount) FILTER (WHERE pc.status = 'paid'), 0)::numeric AS total_paid_amount,
        COUNT(DISTINCT pg.id)::int AS gift_count,
        (SELECT COUNT(*) FROM users ref WHERE ref.referred_by = p.user_id)::int AS referral_count
      FROM partners p
      JOIN users u ON u.id = p.user_id
      LEFT JOIN partner_commissions pc ON pc.partner_id = p.id
      LEFT JOIN partner_gifts pg ON pg.partner_id = p.id
      WHERE p.id = $1
      GROUP BY p.id, u.email, u.full_name`, [id]);
        if (result.rows.length === 0) {
            throw new errors_1.AppError('Partner not found', 404);
        }
        (0, response_1.sendSuccess)(res, result.rows[0]);
    }
    catch (error) {
        next(error);
    }
});
// All commissions across all partners, paginated
router.get('/commissions', (0, validate_1.validate)(validators_1.paginationSchema, 'query'), async (req, res, next) => {
    try {
        const page = Math.max(1, parseInt(req.query.page, 10) || 1);
        const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 20));
        const offset = (page - 1) * limit;
        const conditions = [];
        const params = [];
        let paramIndex = 1;
        if (req.query.status) {
            const validStatuses = ['pending', 'approved', 'paid', 'cancelled'];
            if (!validStatuses.includes(req.query.status)) {
                throw new errors_1.AppError('Invalid status. Must be one of: pending, approved, paid, cancelled', 400);
            }
            conditions.push(`pc.status = $${paramIndex++}`);
            params.push(req.query.status);
        }
        if (req.query.partner_id) {
            const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
            if (!uuidRegex.test(req.query.partner_id)) {
                throw new errors_1.AppError('Invalid partner_id format', 400);
            }
            conditions.push(`pc.partner_id = $${paramIndex++}`);
            params.push(req.query.partner_id);
        }
        const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
        const [result, countResult] = await Promise.all([
            (0, db_1.query)(`SELECT
          pc.id,
          pc.partner_id,
          pc.reference_id,
          pc.amount,
          pc.status,
          pc.created_at,
          p.company_name,
          u.email
        FROM partner_commissions pc
        JOIN partners p ON p.id = pc.partner_id
        JOIN users u ON u.id = p.user_id
        ${whereClause}
        ORDER BY pc.created_at DESC
        LIMIT $${paramIndex++} OFFSET $${paramIndex++}`, [...params, limit, offset]),
            (0, db_1.query)(`SELECT COUNT(*) FROM partner_commissions pc ${whereClause}`, params),
        ]);
        const total = parseInt(countResult.rows[0].count, 10);
        (0, response_1.sendSuccess)(res, result.rows, {
            pagination: {
                page,
                limit,
                total,
                total_pages: Math.ceil(total / limit),
            },
        });
    }
    catch (error) {
        next(error);
    }
});
// Aggregate commission stats across all partners
router.get('/commissions/stats', async (req, res, next) => {
    try {
        const result = await (0, db_1.query)(`
      SELECT
        COALESCE(SUM(amount) FILTER (WHERE status = 'pending'), 0)::numeric AS total_pending_amount,
        COALESCE(SUM(amount) FILTER (WHERE status = 'approved'), 0)::numeric AS total_approved_amount,
        COALESCE(SUM(amount) FILTER (WHERE status = 'paid'), 0)::numeric AS total_paid_amount,
        COALESCE(SUM(amount) FILTER (WHERE status = 'cancelled'), 0)::numeric AS total_cancelled_amount,
        COUNT(*) FILTER (WHERE status = 'pending')::int AS count_pending,
        COUNT(*) FILTER (WHERE status = 'approved')::int AS count_approved,
        COUNT(*) FILTER (WHERE status = 'paid')::int AS count_paid,
        COUNT(*) FILTER (WHERE status = 'cancelled')::int AS count_cancelled
      FROM partner_commissions
    `);
        (0, response_1.sendSuccess)(res, result.rows[0]);
    }
    catch (error) {
        next(error);
    }
});
exports.default = router;
//# sourceMappingURL=admin.js.map