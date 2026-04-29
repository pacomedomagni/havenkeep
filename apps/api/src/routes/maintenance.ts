import { Router } from 'express';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { uuidParamSchema } from '../validators';
import { MaintenanceService } from '../services/maintenance.service';
import {
  getCategoryParamsSchema,
  getItemDueParamsSchema,
  logMaintenanceSchema,
  getHistoryQuerySchema,
  getDueQuerySchema,
} from '../validators/maintenance.validator';
import { asyncHandler } from '../utils/async-handler';
import { writeRateLimiter } from '../middleware/rateLimiter';
import { sendSuccess, sendMessage } from '../utils/response';

const router = Router();

// All routes require authentication
router.use(authenticate);

/**
 * @route   GET /api/v1/maintenance/schedules/:category
 * @desc    Get maintenance schedules for a given item category
 * @access  Private
 */
router.get(
  '/schedules/:category',
  validate(getCategoryParamsSchema, 'params'),
  asyncHandler(async (req, res) => {
    const schedules = await MaintenanceService.getSchedulesByCategory(
      req.params.category as any
    );

    sendSuccess(res, schedules);
  })
);

/**
 * @route   GET /api/v1/maintenance/due
 * @desc    Get all due maintenance tasks across all user items
 * @access  Private
 */
router.get(
  '/due',
  validate(getDueQuerySchema, 'query'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const homeId = req.query.homeId as string | undefined;
    const summary = await MaintenanceService.getUserMaintenanceSummary(userId, homeId);

    sendSuccess(res, summary);
  })
);

/**
 * @route   GET /api/v1/maintenance/due/:itemId
 * @desc    Get due maintenance tasks for a specific item
 * @access  Private
 */
router.get(
  '/due/:itemId',
  validate(getItemDueParamsSchema, 'params'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const result = await MaintenanceService.getItemMaintenanceDue(
      userId,
      req.params.itemId
    );

    sendSuccess(res, result);
  })
);

/**
 * @route   POST /api/v1/maintenance/log
 * @desc    Log a completed maintenance task
 * @access  Private
 */
router.post(
  '/log',
  writeRateLimiter,
  validate(logMaintenanceSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const entry = await MaintenanceService.logMaintenance(userId, req.body);

    sendSuccess(res, entry, { status: 201, message: 'Maintenance task logged successfully' });
  })
);

/**
 * @route   GET /api/v1/maintenance/history
 * @desc    Get maintenance history with pagination and optional item filter
 * @access  Private
 */
router.get(
  '/history',
  validate(getHistoryQuerySchema, 'query'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const { itemId, homeId } = req.query;

    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit as string, 10) || 50));
    const offset = (page - 1) * limit;

    const result = await MaintenanceService.getMaintenanceHistory(userId, {
      limit,
      offset,
      itemId: itemId as string,
      homeId: homeId as string | undefined,
    });

    sendSuccess(res, result.history, {
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
 * @route   DELETE /api/v1/maintenance/history/:id
 * @desc    Delete a maintenance log entry
 * @access  Private
 */
router.delete(
  '/history/:id',
  validate(uuidParamSchema, 'params'),
  writeRateLimiter,
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    await MaintenanceService.deleteMaintenanceLog(req.params.id, userId);

    sendMessage(res, 'Maintenance log entry deleted successfully');
  })
);

/**
 * @route   GET /api/v1/maintenance/savings
 * @desc    Get preventive maintenance savings summary
 * @access  Private
 */
router.get(
  '/savings',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const savings = await MaintenanceService.getPreventiveSavings(userId);

    sendSuccess(res, savings);
  })
);

export default router;
