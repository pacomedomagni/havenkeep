"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const audit_service_1 = require("../services/audit.service");
const errors_1 = require("../utils/errors");
const async_handler_1 = require("../utils/async-handler");
const response_1 = require("../utils/response");
const router = (0, express_1.Router)();
// All audit routes require authentication
router.use(auth_1.authenticate);
/**
 * GET /api/v1/audit/logs
 * Query audit logs with filters (admin or own logs)
 */
router.get('/logs', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const user = req.user;
    const { action, severity, resourceType, resourceId, startDate, endDate, success, limit = '50', offset = '0', } = req.query;
    // Non-admins can only see their own logs
    const userId = user.isAdmin ? req.query.userId : user.id;
    const filters = {
        userId,
        action: action,
        severity: severity,
        resourceType: resourceType,
        resourceId: resourceId,
        startDate: startDate ? new Date(startDate) : undefined,
        endDate: endDate ? new Date(endDate) : undefined,
        success: success !== undefined ? success === 'true' : undefined,
        limit: Math.min(parseInt(limit, 10), 100),
        offset: parseInt(offset, 10),
    };
    const result = await audit_service_1.AuditService.query(filters);
    (0, response_1.sendSuccess)(res, result.logs, {
        pagination: {
            page: Math.floor(filters.offset / filters.limit) + 1,
            limit: filters.limit,
            total: result.total,
            total_pages: Math.ceil(result.total / filters.limit),
        },
    });
}));
/**
 * GET /api/v1/audit/logs/me
 * Get current user's audit logs
 */
router.get('/logs/me', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const user = req.user;
    const { limit = '50', offset = '0' } = req.query;
    const limitVal = Math.min(parseInt(limit, 10), 100);
    const offsetVal = parseInt(offset, 10);
    const result = await audit_service_1.AuditService.getUserLogs(user.id, limitVal, offsetVal);
    (0, response_1.sendSuccess)(res, result.logs, {
        pagination: {
            page: Math.floor(offsetVal / limitVal) + 1,
            limit: limitVal,
            total: result.total,
            total_pages: Math.ceil(result.total / limitVal),
        },
    });
}));
/**
 * GET /api/v1/audit/logs/resource/:resourceType/:resourceId
 * Get audit logs for a specific resource
 */
router.get('/logs/resource/:resourceType/:resourceId', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const user = req.user;
    const { resourceType, resourceId } = req.params;
    const { limit = '50', offset = '0' } = req.query;
    const limitVal = Math.min(parseInt(limit, 10), 100);
    const offsetVal = parseInt(offset, 10);
    // Non-admins can only see their own logs — pass userId filter to the query
    const result = user.isAdmin
        ? await audit_service_1.AuditService.getResourceLogs(resourceType, resourceId, limitVal, offsetVal)
        : await audit_service_1.AuditService.query({
            userId: user.id,
            resourceType,
            resourceId,
            limit: limitVal,
            offset: offsetVal,
        });
    (0, response_1.sendSuccess)(res, result.logs, {
        pagination: {
            page: Math.floor(offsetVal / limitVal) + 1,
            limit: limitVal,
            total: result.total,
            total_pages: Math.ceil(result.total / limitVal),
        },
    });
}));
/**
 * GET /api/v1/audit/security
 * Get recent security events (admin only)
 */
router.get('/security', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const user = req.user;
    if (!user.isAdmin) {
        throw new errors_1.AppError('Unauthorized - Admin access required', 403);
    }
    const { limit = '100' } = req.query;
    const events = await audit_service_1.AuditService.getRecentSecurityEvents(Math.min(parseInt(limit, 10), 500));
    (0, response_1.sendSuccess)(res, events);
}));
/**
 * GET /api/v1/audit/stats
 * Get audit log statistics
 */
router.get('/stats', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const user = req.user;
    if (!user.isAdmin) {
        throw new errors_1.AppError('Unauthorized - Admin access required', 403);
    }
    const { startDate, endDate } = req.query;
    const stats = await audit_service_1.AuditService.getStats(startDate ? new Date(startDate) : undefined, endDate ? new Date(endDate) : undefined);
    (0, response_1.sendSuccess)(res, stats);
}));
/**
 * GET /api/v1/audit/activity-summary
 * Get user activity summary (admin only)
 */
router.get('/activity-summary', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const user = req.user;
    if (!user.isAdmin) {
        throw new errors_1.AppError('Unauthorized - Admin access required', 403);
    }
    const { userId } = req.query;
    const summary = await audit_service_1.AuditService.getUserActivitySummary(userId);
    (0, response_1.sendSuccess)(res, summary);
}));
/**
 * POST /api/v1/audit/cleanup
 * Manually trigger audit log cleanup (admin only)
 */
router.post('/cleanup', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const user = req.user;
    if (!user.isAdmin) {
        throw new errors_1.AppError('Unauthorized - Admin access required', 403);
    }
    await audit_service_1.AuditService.cleanup();
    // Log the cleanup action
    await audit_service_1.AuditService.logFromRequest(req, 'system.maintenance_start', {
        description: 'Audit log cleanup triggered manually',
    });
    (0, response_1.sendMessage)(res, 'Audit log cleanup completed');
}));
exports.default = router;
//# sourceMappingURL=audit.js.map