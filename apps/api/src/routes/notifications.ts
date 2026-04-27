import { Router } from 'express';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { NotificationsService } from '../services/notifications.service';
import {
  getNotificationsQuerySchema,
  recordActionSchema,
  notificationParamsSchema,
  updatePreferencesSchema,
} from '../validators/notifications.validator';
import { asyncHandler } from '../utils/async-handler';
import { writeRateLimiter } from '../middleware/rateLimiter';
import { idempotency } from '../middleware/idempotency';
import { pool } from '../db';
import { sendSuccess, sendMessage } from '../utils/response';

const router = Router();

// All routes require authentication
router.use(authenticate);

/**
 * @route   GET /api/v1/notifications
 * @desc    Get user's notifications with pagination and optional filters
 * @access  Private
 */
router.get(
  '/',
  validate(getNotificationsQuerySchema, 'query'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const { type, unread } = req.query;
    const unreadFilter =
      typeof unread === 'boolean'
        ? unread
        : unread !== undefined
        ? unread === 'true'
        : undefined;

    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit as string, 10) || 50));
    const offset = (page - 1) * limit;

    const result = await NotificationsService.getUserNotifications(userId, {
      limit,
      offset,
      type: type as any,
      unread: unreadFilter,
    });

    const notifications = result.notifications.map((notification) => {
      const data = notification.data || {};
      const fallbackActionData = notification.item_id
        ? { item_id: notification.item_id }
        : null;
      const actionType = (data as any).action_type ?? (notification.item_id ? 'view_item' : null);
      const actionData = (data as any).action_data ?? fallbackActionData;

      return {
        ...notification,
        is_read: notification.opened_at != null,
        scheduled_at: notification.sent_at || notification.created_at,
        action_type: actionType,
        action_data: actionData,
      };
    });

    sendSuccess(res, notifications, {
      pagination: {
        page,
        limit,
        total: result.total,
        total_pages: Math.ceil(result.total / limit),
      },
    });
  })
);

/**
 * @route   GET /api/v1/notifications/unread-count
 * @desc    Get unread notification count
 * @access  Private
 */
router.get(
  '/unread-count',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const count = await NotificationsService.getUnreadCount(userId);

    sendSuccess(res, { count });
  })
);

/**
 * @route   GET /api/v1/notifications/tip
 * @desc    Get a contextual tip based on the current user's state
 * @access  Private
 */
router.get(
  '/tip',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;

    // Query user state in parallel: item count, last maintenance date,
    // notification preferences, and expired warranty count + active warranty count
    const [itemCountRes, lastMaintenanceRes, prefsRes, expiredWarrantyRes, activeWarrantyRes] =
      await Promise.all([
        pool.query(
          `SELECT COUNT(*)::int AS count FROM items WHERE user_id = $1 AND is_archived = FALSE`,
          [userId]
        ),
        pool.query(
          `SELECT MAX(completed_date) AS last_date FROM maintenance_history WHERE user_id = $1`,
          [userId]
        ),
        pool.query(`SELECT * FROM notification_preferences WHERE user_id = $1`, [userId]),
        pool.query(
          `SELECT COUNT(*)::int AS count FROM items
           WHERE user_id = $1 AND is_archived = FALSE
             AND warranty_end_date < CURRENT_DATE`,
          [userId]
        ),
        pool.query(
          `SELECT COUNT(*)::int AS count FROM items
           WHERE user_id = $1 AND is_archived = FALSE
             AND warranty_end_date >= CURRENT_DATE`,
          [userId]
        ),
      ]);

    const itemCount: number = itemCountRes.rows[0].count;
    const lastMaintenanceDate: string | null = lastMaintenanceRes.rows[0].last_date;
    const _prefs = prefsRes.rows[0] || null;
    const expiredWarrantyCount: number = expiredWarrantyRes.rows[0].count;
    const activeWarrantyCount: number = activeWarrantyRes.rows[0].count;

    // Determine the contextual category and trigger based on user state
    let targetCategory: string;
    let targetTrigger: string | null;

    if (itemCount === 0) {
      targetCategory = 'new_user';
      targetTrigger = 'no_items';
    } else if (!lastMaintenanceDate) {
      targetCategory = 'maintenance';
      targetTrigger = 'no_maintenance';
    } else if (expiredWarrantyCount > 0) {
      targetCategory = 'warranty';
      targetTrigger = 'expired_warranty';
    } else if (activeWarrantyCount > 0) {
      targetCategory = 'warranty';
      targetTrigger = 'active_warranty';
    } else if (itemCount >= 20) {
      targetCategory = 'power_user';
      targetTrigger = 'many_items';
    } else {
      targetCategory = 'general';
      targetTrigger = null;
    }

    // Query contextual tips from the database
    let tipsResult = await pool.query(
      `SELECT content, category FROM tips
       WHERE is_active = TRUE
         AND category = $1
         AND ($2::VARCHAR IS NULL OR trigger_condition IS NULL OR trigger_condition = $2)
       ORDER BY id`,
      [targetCategory, targetTrigger]
    );

    // Fall back to general tips if no contextual tips found
    if (tipsResult.rows.length === 0) {
      tipsResult = await pool.query(
        `SELECT content, category FROM tips
         WHERE is_active = TRUE AND category = 'general'
         ORDER BY id`
      );
    }

    let tip: string;
    let category: string;

    if (tipsResult.rows.length > 0) {
      // F045: rotate tips by UTC day-of-year so a server in a non-UTC zone
      // doesn't tip an extra day across DST. Same epoch on every replica.
      const now = new Date();
      const utcStartOfYear = Date.UTC(now.getUTCFullYear(), 0, 0);
      const dayOfYear = Math.floor((now.getTime() - utcStartOfYear) / 86_400_000);
      const selected = tipsResult.rows[dayOfYear % tipsResult.rows.length];
      tip = selected.content;
      category = selected.category;
    } else {
      // Hardcoded ultimate fallback in case the tips table is empty
      tip = 'Keep your home items organized and their warranties tracked.';
      category = 'general';
    }

    sendSuccess(res, { tip, category });
  })
);

/**
 * @route   PUT /api/v1/notifications/read-all
 * @desc    Mark all notifications as read
 * @access  Private
 */
router.put(
  '/read-all',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const count = await NotificationsService.markAllAsRead(userId);

    sendSuccess(res, { updated: count }, { message: `${count} notification(s) marked as read` });
  })
);

/**
 * @route   PUT /api/v1/notifications/:id/read
 * @desc    Mark a single notification as read
 * @access  Private
 */
router.put(
  '/:id/read',
  validate(notificationParamsSchema, 'params'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const notification = await NotificationsService.markAsRead(req.params.id, userId);

    sendSuccess(res, notification, { message: 'Notification marked as read' });
  })
);

/**
 * @route   POST /api/v1/notifications/:id/action
 * @desc    Record an action taken on a notification
 * @access  Private
 */
router.post(
  '/:id/action',
  validate(notificationParamsSchema, 'params'),
  validate(recordActionSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const { action } = req.body;
    const notification = await NotificationsService.recordAction(req.params.id, userId, action);

    sendSuccess(res, notification, { message: 'Action recorded successfully' });
  })
);

/**
 * @route   GET /api/v1/notifications/preferences
 * @desc    Get notification preferences for the current user
 * @access  Private
 */
router.get(
  '/preferences',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const result = await NotificationsService.getPreferences(userId);

    sendSuccess(res, result);
  })
);

/**
 * @route   PUT /api/v1/notifications/preferences
 * @desc    Create or update notification preferences
 * @access  Private
 */
router.put(
  '/preferences',
  writeRateLimiter,
  validate(updatePreferencesSchema),
  idempotency('notifications:preferences'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const prefs = { ...req.body, userId };
    const result = await NotificationsService.upsertPreferences(userId, prefs);

    sendSuccess(res, result);
  })
);

/**
 * @route   DELETE /api/v1/notifications/:id
 * @desc    Delete a notification
 * @access  Private
 */
router.delete(
  '/:id',
  validate(notificationParamsSchema, 'params'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    await NotificationsService.deleteNotification(req.params.id, userId);

    sendMessage(res, 'Notification deleted successfully');
  })
);

export default router;
