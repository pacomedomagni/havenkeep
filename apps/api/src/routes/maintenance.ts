import { Router } from 'express';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { MaintenanceService } from '../services/maintenance.service';
import {
  getCategoryParamsSchema,
  getItemDueParamsSchema,
  logMaintenanceSchema,
  getHistoryQuerySchema,
} from '../validators/maintenance.validator';
import { asyncHandler } from '../utils/async-handler';

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

    res.json({
      success: true,
      data: schedules,
    });
  })
);

/**
 * @route   GET /api/v1/maintenance/due
 * @desc    Get all due maintenance tasks across all user items
 * @access  Private
 */
router.get(
  '/due',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const summary = await MaintenanceService.getUserMaintenanceSummary(userId);

    res.json({
      success: true,
      data: summary,
    });
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

    res.json({
      success: true,
      data: result,
    });
  })
);

/**
 * @route   POST /api/v1/maintenance/log
 * @desc    Log a completed maintenance task
 * @access  Private
 */
router.post(
  '/log',
  validate(logMaintenanceSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const entry = await MaintenanceService.logMaintenance(userId, req.body);

    res.status(201).json({
      success: true,
      data: entry,
      message: 'Maintenance task logged successfully',
    });
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
    const { limit, offset, item_id } = req.query;

    const result = await MaintenanceService.getMaintenanceHistory(userId, {
      limit: Number(limit),
      offset: Number(offset),
      itemId: item_id as string,
    });

    res.json({
      success: true,
      data: result.history,
      pagination: {
        total: result.total,
        limit: Number(limit),
        offset: Number(offset),
        has_more: result.total > Number(offset) + result.history.length,
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
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    await MaintenanceService.deleteMaintenanceLog(req.params.id, userId);

    res.json({
      success: true,
      message: 'Maintenance log entry deleted successfully',
    });
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

    res.json({
      success: true,
      data: savings,
    });
  })
);

export default router;
