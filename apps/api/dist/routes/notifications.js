"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const validate_1 = require("../middleware/validate");
const notifications_service_1 = require("../services/notifications.service");
const notifications_validator_1 = require("../validators/notifications.validator");
const async_handler_1 = require("../utils/async-handler");
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
    const { limit, offset, type, unread } = req.query;
    const unreadFilter = typeof unread === 'boolean'
        ? unread
        : unread !== undefined
            ? unread === 'true'
            : undefined;
    const result = await notifications_service_1.NotificationsService.getUserNotifications(userId, {
        limit: Number(limit),
        offset: Number(offset),
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
    res.json({
        success: true,
        data: notifications,
        pagination: {
            total: result.total,
            limit: Number(limit),
            offset: Number(offset),
            has_more: result.total > Number(offset) + result.notifications.length,
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
    res.json({
        success: true,
        data: { count },
    });
}));
/**
 * @route   PUT /api/v1/notifications/read-all
 * @desc    Mark all notifications as read
 * @access  Private
 */
router.put('/read-all', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const count = await notifications_service_1.NotificationsService.markAllAsRead(userId);
    res.json({
        success: true,
        data: { updated: count },
        message: `${count} notification(s) marked as read`,
    });
}));
/**
 * @route   PUT /api/v1/notifications/:id/read
 * @desc    Mark a single notification as read
 * @access  Private
 */
router.put('/:id/read', (0, validate_1.validate)(notifications_validator_1.notificationParamsSchema, 'params'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const notification = await notifications_service_1.NotificationsService.markAsRead(req.params.id, userId);
    res.json({
        success: true,
        data: notification,
        message: 'Notification marked as read',
    });
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
    res.json({
        success: true,
        data: notification,
        message: 'Action recorded successfully',
    });
}));
/**
 * @route   GET /api/v1/notifications/preferences
 * @desc    Get notification preferences for the current user
 * @access  Private
 */
router.get('/preferences', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const result = await notifications_service_1.NotificationsService.getPreferences(userId);
    res.json({
        success: true,
        data: result,
    });
}));
/**
 * @route   PUT /api/v1/notifications/preferences
 * @desc    Create or update notification preferences
 * @access  Private
 */
router.put('/preferences', (0, validate_1.validate)(notifications_validator_1.updatePreferencesSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const prefs = { ...req.body, user_id: userId };
    const result = await notifications_service_1.NotificationsService.upsertPreferences(userId, prefs);
    res.json({
        success: true,
        data: result,
    });
}));
/**
 * @route   DELETE /api/v1/notifications/:id
 * @desc    Delete a notification
 * @access  Private
 */
router.delete('/:id', (0, validate_1.validate)(notifications_validator_1.notificationParamsSchema, 'params'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    await notifications_service_1.NotificationsService.deleteNotification(req.params.id, userId);
    res.json({
        success: true,
        message: 'Notification deleted successfully',
    });
}));
exports.default = router;
//# sourceMappingURL=notifications.js.map