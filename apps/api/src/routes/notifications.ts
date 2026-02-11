import { Router } from 'express';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { NotificationsService } from '../services/notifications.service';
import {
  getNotificationsQuerySchema,
  recordActionSchema,
  notificationParamsSchema,
} from '../validators/notifications.validator';
import { asyncHandler } from '../utils/async-handler';

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
    const { limit, offset, type, unread } = req.query;

    const result = await NotificationsService.getUserNotifications(userId, {
      limit: Number(limit),
      offset: Number(offset),
      type: type as any,
      unread: unread !== undefined ? unread === 'true' || unread === true : undefined,
    });

    res.json({
      success: true,
      data: result.notifications,
      pagination: {
        total: result.total,
        limit: Number(limit),
        offset: Number(offset),
        has_more: result.total > Number(offset) + result.notifications.length,
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

    res.json({
      success: true,
      data: { count },
    });
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

    res.json({
      success: true,
      data: { updated: count },
      message: `${count} notification(s) marked as read`,
    });
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

    res.json({
      success: true,
      data: notification,
      message: 'Notification marked as read',
    });
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

    res.json({
      success: true,
      data: notification,
      message: 'Action recorded successfully',
    });
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

    res.json({
      success: true,
      message: 'Notification deleted successfully',
    });
  })
);

export default router;
