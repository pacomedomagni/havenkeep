"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const validate_1 = require("../middleware/validate");
const notifications_service_1 = require("../services/notifications.service");
const notifications_validator_1 = require("../validators/notifications.validator");
const async_handler_1 = require("../utils/async-handler");
const rateLimiter_1 = require("../middleware/rateLimiter");
const db_1 = require("../db");
const response_1 = require("../utils/response");
const router = (0, express_1.Router)();
// All routes require authentication
router.use(auth_1.authenticate);
/**
 * @route   GET /api/v1/notifications
 * @desc    Get user's notifications with pagination and optional filters
 * @access  Private
 */
router.get('/', (0, validate_1.validate)(notifications_validator_1.getNotificationsQuerySchema, 'query'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const { type, unread } = req.query;
    const unreadFilter = typeof unread === 'boolean'
        ? unread
        : unread !== undefined
            ? unread === 'true'
            : undefined;
    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 50));
    const offset = (page - 1) * limit;
    const result = await notifications_service_1.NotificationsService.getUserNotifications(userId, {
        limit,
        offset,
        type: type,
        unread: unreadFilter,
    });
    const notifications = result.notifications.map((notification) => {
        const data = notification.data || {};
        const fallbackActionData = notification.item_id
            ? { item_id: notification.item_id }
            : null;
        const actionType = data.action_type ?? (notification.item_id ? 'view_item' : null);
        const actionData = data.action_data ?? fallbackActionData;
        return {
            ...notification,
            is_read: notification.opened_at != null,
            scheduled_at: notification.sent_at || notification.created_at,
            action_type: actionType,
            action_data: actionData,
        };
    });
    (0, response_1.sendSuccess)(res, notifications, {
        pagination: {
            page,
            limit,
            total: result.total,
            total_pages: Math.ceil(result.total / limit),
        },
    });
}));
/**
 * @route   GET /api/v1/notifications/unread-count
 * @desc    Get unread notification count
 * @access  Private
 */
router.get('/unread-count', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const count = await notifications_service_1.NotificationsService.getUnreadCount(userId);
    (0, response_1.sendSuccess)(res, { count });
}));
/**
 * @route   GET /api/v1/notifications/tip
 * @desc    Get a contextual tip based on the current user's state
 * @access  Private
 */
router.get('/tip', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    // Query user state in parallel: item count, last maintenance date,
    // notification preferences, and expired warranty count + active warranty count
    const [itemCountRes, lastMaintenanceRes, prefsRes, expiredWarrantyRes, activeWarrantyRes] = await Promise.all([
        db_1.pool.query(`SELECT COUNT(*)::int AS count FROM items WHERE user_id = $1 AND is_archived = FALSE`, [userId]),
        db_1.pool.query(`SELECT MAX(completed_date) AS last_date FROM maintenance_history WHERE user_id = $1`, [userId]),
        db_1.pool.query(`SELECT * FROM notification_preferences WHERE user_id = $1`, [userId]),
        db_1.pool.query(`SELECT COUNT(*)::int AS count FROM items
           WHERE user_id = $1 AND is_archived = FALSE
             AND warranty_end_date < CURRENT_DATE`, [userId]),
        db_1.pool.query(`SELECT COUNT(*)::int AS count FROM items
           WHERE user_id = $1 AND is_archived = FALSE
             AND warranty_end_date >= CURRENT_DATE`, [userId]),
    ]);
    const itemCount = itemCountRes.rows[0].count;
    const lastMaintenanceDate = lastMaintenanceRes.rows[0].last_date;
    const _prefs = prefsRes.rows[0] || null;
    const expiredWarrantyCount = expiredWarrantyRes.rows[0].count;
    const activeWarrantyCount = activeWarrantyRes.rows[0].count;
    // Determine the contextual category and trigger based on user state
    let targetCategory;
    let targetTrigger;
    if (itemCount === 0) {
        targetCategory = 'new_user';
        targetTrigger = 'no_items';
    }
    else if (!lastMaintenanceDate) {
        targetCategory = 'maintenance';
        targetTrigger = 'no_maintenance';
    }
    else if (expiredWarrantyCount > 0) {
        targetCategory = 'warranty';
        targetTrigger = 'expired_warranty';
    }
    else if (activeWarrantyCount > 0) {
        targetCategory = 'warranty';
        targetTrigger = 'active_warranty';
    }
    else if (itemCount >= 20) {
        targetCategory = 'power_user';
        targetTrigger = 'many_items';
    }
    else {
        targetCategory = 'general';
        targetTrigger = null;
    }
    // Query contextual tips from the database
    let tipsResult = await db_1.pool.query(`SELECT content, category FROM tips
       WHERE is_active = TRUE
         AND category = $1
         AND ($2::VARCHAR IS NULL OR trigger_condition IS NULL OR trigger_condition = $2)
       ORDER BY id`, [targetCategory, targetTrigger]);
    // Fall back to general tips if no contextual tips found
    if (tipsResult.rows.length === 0) {
        tipsResult = await db_1.pool.query(`SELECT content, category FROM tips
         WHERE is_active = TRUE AND category = 'general'
         ORDER BY id`);
    }
    let tip;
    let category;
    if (tipsResult.rows.length > 0) {
        // Rotate tips by day of year
        const now = new Date();
        const startOfYear = new Date(now.getFullYear(), 0, 0);
        const dayOfYear = Math.floor((now.getTime() - startOfYear.getTime()) / (1000 * 60 * 60 * 24));
        const selected = tipsResult.rows[dayOfYear % tipsResult.rows.length];
        tip = selected.content;
        category = selected.category;
    }
    else {
        // Hardcoded ultimate fallback in case the tips table is empty
        tip = 'Keep your home items organized and their warranties tracked.';
        category = 'general';
    }
    (0, response_1.sendSuccess)(res, { tip, category });
}));
/**
 * @route   PUT /api/v1/notifications/read-all
 * @desc    Mark all notifications as read
 * @access  Private
 */
router.put('/read-all', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const count = await notifications_service_1.NotificationsService.markAllAsRead(userId);
    (0, response_1.sendSuccess)(res, { updated: count }, { message: `${count} notification(s) marked as read` });
}));
/**
 * @route   PUT /api/v1/notifications/:id/read
 * @desc    Mark a single notification as read
 * @access  Private
 */
router.put('/:id/read', (0, validate_1.validate)(notifications_validator_1.notificationParamsSchema, 'params'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const notification = await notifications_service_1.NotificationsService.markAsRead(req.params.id, userId);
    (0, response_1.sendSuccess)(res, notification, { message: 'Notification marked as read' });
}));
/**
 * @route   POST /api/v1/notifications/:id/action
 * @desc    Record an action taken on a notification
 * @access  Private
 */
router.post('/:id/action', (0, validate_1.validate)(notifications_validator_1.notificationParamsSchema, 'params'), (0, validate_1.validate)(notifications_validator_1.recordActionSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const { action } = req.body;
    const notification = await notifications_service_1.NotificationsService.recordAction(req.params.id, userId, action);
    (0, response_1.sendSuccess)(res, notification, { message: 'Action recorded successfully' });
}));
/**
 * @route   GET /api/v1/notifications/preferences
 * @desc    Get notification preferences for the current user
 * @access  Private
 */
router.get('/preferences', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const result = await notifications_service_1.NotificationsService.getPreferences(userId);
    (0, response_1.sendSuccess)(res, result);
}));
/**
 * @route   PUT /api/v1/notifications/preferences
 * @desc    Create or update notification preferences
 * @access  Private
 */
router.put('/preferences', rateLimiter_1.writeRateLimiter, (0, validate_1.validate)(notifications_validator_1.updatePreferencesSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const prefs = { ...req.body, userId };
    const result = await notifications_service_1.NotificationsService.upsertPreferences(userId, prefs);
    (0, response_1.sendSuccess)(res, result);
}));
/**
 * @route   DELETE /api/v1/notifications/:id
 * @desc    Delete a notification
 * @access  Private
 */
router.delete('/:id', (0, validate_1.validate)(notifications_validator_1.notificationParamsSchema, 'params'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    await notifications_service_1.NotificationsService.deleteNotification(req.params.id, userId);
    (0, response_1.sendMessage)(res, 'Notification deleted successfully');
}));
exports.default = router;
//# sourceMappingURL=notifications.js.map