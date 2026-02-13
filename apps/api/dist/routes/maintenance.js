"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const validate_1 = require("../middleware/validate");
const maintenance_service_1 = require("../services/maintenance.service");
const maintenance_validator_1 = require("../validators/maintenance.validator");
const async_handler_1 = require("../utils/async-handler");
const router = (0, express_1.Router)();
// All routes require authentication
router.use(auth_1.authenticate);
/**
 * @route   GET /api/v1/maintenance/schedules/:category
 * @desc    Get maintenance schedules for a given item category
 * @access  Private
 */
router.get('/schedules/:category', (0, validate_1.validate)(maintenance_validator_1.getCategoryParamsSchema, 'params'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const schedules = await maintenance_service_1.MaintenanceService.getSchedulesByCategory(req.params.category);
    res.json({
        success: true,
        data: schedules,
    });
}));
/**
 * @route   GET /api/v1/maintenance/due
 * @desc    Get all due maintenance tasks across all user items
 * @access  Private
 */
router.get('/due', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const summary = await maintenance_service_1.MaintenanceService.getUserMaintenanceSummary(userId);
    res.json({
        success: true,
        data: summary,
    });
}));
/**
 * @route   GET /api/v1/maintenance/due/:itemId
 * @desc    Get due maintenance tasks for a specific item
 * @access  Private
 */
router.get('/due/:itemId', (0, validate_1.validate)(maintenance_validator_1.getItemDueParamsSchema, 'params'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const result = await maintenance_service_1.MaintenanceService.getItemMaintenanceDue(userId, req.params.itemId);
    res.json({
        success: true,
        data: result,
    });
}));
/**
 * @route   POST /api/v1/maintenance/log
 * @desc    Log a completed maintenance task
 * @access  Private
 */
router.post('/log', (0, validate_1.validate)(maintenance_validator_1.logMaintenanceSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const entry = await maintenance_service_1.MaintenanceService.logMaintenance(userId, req.body);
    res.status(201).json({
        success: true,
        data: entry,
        message: 'Maintenance task logged successfully',
    });
}));
/**
 * @route   GET /api/v1/maintenance/history
 * @desc    Get maintenance history with pagination and optional item filter
 * @access  Private
 */
router.get('/history', (0, validate_1.validate)(maintenance_validator_1.getHistoryQuerySchema, 'query'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const { limit, offset, item_id } = req.query;
    const result = await maintenance_service_1.MaintenanceService.getMaintenanceHistory(userId, {
        limit: Number(limit),
        offset: Number(offset),
        itemId: item_id,
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
}));
/**
 * @route   DELETE /api/v1/maintenance/history/:id
 * @desc    Delete a maintenance log entry
 * @access  Private
 */
router.delete('/history/:id', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    await maintenance_service_1.MaintenanceService.deleteMaintenanceLog(req.params.id, userId);
    res.json({
        success: true,
        message: 'Maintenance log entry deleted successfully',
    });
}));
/**
 * @route   GET /api/v1/maintenance/savings
 * @desc    Get preventive maintenance savings summary
 * @access  Private
 */
router.get('/savings', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const savings = await maintenance_service_1.MaintenanceService.getPreventiveSavings(userId);
    res.json({
        success: true,
        data: savings,
    });
}));
exports.default = router;
//# sourceMappingURL=maintenance.js.map