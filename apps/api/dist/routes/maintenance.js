"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const validate_1 = require("../middleware/validate");
const validators_1 = require("../validators");
const maintenance_service_1 = require("../services/maintenance.service");
const maintenance_validator_1 = require("../validators/maintenance.validator");
const async_handler_1 = require("../utils/async-handler");
const rateLimiter_1 = require("../middleware/rateLimiter");
const response_1 = require("../utils/response");
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
    (0, response_1.sendSuccess)(res, schedules);
}));
/**
 * @route   GET /api/v1/maintenance/due
 * @desc    Get all due maintenance tasks across all user items
 * @access  Private
 */
router.get('/due', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const summary = await maintenance_service_1.MaintenanceService.getUserMaintenanceSummary(userId);
    (0, response_1.sendSuccess)(res, summary);
}));
/**
 * @route   GET /api/v1/maintenance/due/:itemId
 * @desc    Get due maintenance tasks for a specific item
 * @access  Private
 */
router.get('/due/:itemId', (0, validate_1.validate)(maintenance_validator_1.getItemDueParamsSchema, 'params'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const result = await maintenance_service_1.MaintenanceService.getItemMaintenanceDue(userId, req.params.itemId);
    (0, response_1.sendSuccess)(res, result);
}));
/**
 * @route   POST /api/v1/maintenance/log
 * @desc    Log a completed maintenance task
 * @access  Private
 */
router.post('/log', rateLimiter_1.writeRateLimiter, (0, validate_1.validate)(maintenance_validator_1.logMaintenanceSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const entry = await maintenance_service_1.MaintenanceService.logMaintenance(userId, req.body);
    (0, response_1.sendSuccess)(res, entry, { status: 201, message: 'Maintenance task logged successfully' });
}));
/**
 * @route   GET /api/v1/maintenance/history
 * @desc    Get maintenance history with pagination and optional item filter
 * @access  Private
 */
router.get('/history', (0, validate_1.validate)(maintenance_validator_1.getHistoryQuerySchema, 'query'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const { itemId } = req.query;
    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 50));
    const offset = (page - 1) * limit;
    const result = await maintenance_service_1.MaintenanceService.getMaintenanceHistory(userId, {
        limit,
        offset,
        itemId: itemId,
    });
    (0, response_1.sendSuccess)(res, result.history, {
        pagination: {
            page,
            limit,
            total: result.total,
            total_pages: Math.ceil(result.total / limit),
        },
    });
}));
/**
 * @route   DELETE /api/v1/maintenance/history/:id
 * @desc    Delete a maintenance log entry
 * @access  Private
 */
router.delete('/history/:id', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), rateLimiter_1.writeRateLimiter, (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    await maintenance_service_1.MaintenanceService.deleteMaintenanceLog(req.params.id, userId);
    (0, response_1.sendMessage)(res, 'Maintenance log entry deleted successfully');
}));
/**
 * @route   GET /api/v1/maintenance/savings
 * @desc    Get preventive maintenance savings summary
 * @access  Private
 */
router.get('/savings', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const savings = await maintenance_service_1.MaintenanceService.getPreventiveSavings(userId);
    (0, response_1.sendSuccess)(res, savings);
}));
exports.default = router;
//# sourceMappingURL=maintenance.js.map