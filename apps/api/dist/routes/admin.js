"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const db_1 = require("../db");
const auth_1 = require("../middleware/auth");
const validate_1 = require("../middleware/validate");
const validators_1 = require("../validators");
const admin_validator_1 = require("../validators/admin.validator");
const errors_1 = require("../utils/errors");
const router = (0, express_1.Router)();
router.use(auth_1.authenticate);
// Current user info (accessible to admins AND partners)
router.get('/me', (req, res) => {
    res.json({
        user: {
            id: req.user.id,
            email: req.user.email,
            plan: req.user.plan,
            isAdmin: req.user.isAdmin,
            isPartner: req.user.isPartner,
        },
    });
});
// All routes below require admin
router.use(auth_1.requireAdmin);
// Admin stats overview (basic)
router.get('/stats', async (req, res, next) => {
    try {
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
        res.json({ stats: stats.rows[0] });
    }
    catch (error) {
        next(error);
    }
});
// Full admin stats (dashboard overview)
router.get('/stats/full', async (req, res, next) => {
    try {
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
        res.json({ stats: stats.rows[0] });
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
        res.json({ data: result.rows });
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
        res.json({ data: result.rows });
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
    `);
        res.json({ users: result.rows });
    }
    catch (error) {
        next(error);
    }
});
// Admin user listing with pagination
router.get('/users', (0, validate_1.validate)(validators_1.paginationSchema, 'query'), async (req, res, next) => {
    try {
        const { page, limit } = req.query;
        const offset = (page - 1) * limit;
        const [result, countResult] = await Promise.all([
            (0, db_1.query)(`SELECT * FROM user_stats ORDER BY created_at DESC LIMIT $1 OFFSET $2`, [limit, offset]),
            (0, db_1.query)(`SELECT COUNT(*) FROM users`),
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
    }
    catch (error) {
        next(error);
    }
});
// Suspend user (set plan to free)
router.put('/users/:id/suspend', (0, validate_1.validate)(admin_validator_1.userIdParamSchema, 'params'), async (req, res, next) => {
    try {
        const { id } = req.params;
        const result = await (0, db_1.query)(`UPDATE users SET plan = 'free', updated_at = NOW() WHERE id = $1 RETURNING id, email`, [id]);
        if (result.rows.length === 0) {
            throw new errors_1.AppError('User not found', 404);
        }
        res.json({ success: true, message: 'User suspended', user: result.rows[0] });
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
        // Delete refresh tokens first (prevents token refresh after deletion)
        await (0, db_1.query)(`DELETE FROM refresh_tokens WHERE user_id = $1`, [id]);
        // Delete user (FK cascades handle items, homes, documents, etc.)
        const result = await (0, db_1.query)(`DELETE FROM users WHERE id = $1 RETURNING id, email`, [id]);
        if (result.rows.length === 0) {
            throw new errors_1.AppError('User not found', 404);
        }
        res.json({ success: true, message: 'User deleted', user: result.rows[0] });
    }
    catch (error) {
        next(error);
    }
});
exports.default = router;
//# sourceMappingURL=admin.js.map