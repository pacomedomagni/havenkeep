"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const audit_service_1 = require("../services/audit.service");
const errors_1 = require("../utils/errors");
const router = (0, express_1.Router)();
// All audit routes require authentication
router.use(auth_1.authenticate);
/**
 * GET /api/v1/audit/logs
 * Query audit logs with filters (admin or own logs)
 */
router.get('/logs', async (req, res) => {
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
    res.json({
        logs: result.logs,
        pagination: {
            total: result.total,
            limit: filters.limit,
            offset: filters.offset,
            hasMore: result.total > filters.offset + filters.limit,
        },
    });
});
/**
 * GET /api/v1/audit/logs/me
 * Get current user's audit logs
 */
router.get('/logs/me', async (req, res) => {
    const user = req.user;
    const { limit = '50', offset = '0' } = req.query;
    const result = await audit_service_1.AuditService.getUserLogs(user.id, Math.min(parseInt(limit, 10), 100), parseInt(offset, 10));
    res.json({
        logs: result.logs,
        pagination: {
            total: result.total,
            limit: parseInt(limit, 10),
            offset: parseInt(offset, 10),
            hasMore: result.total > parseInt(offset, 10) + parseInt(limit, 10),
        },
    });
});
/**
 * GET /api/v1/audit/logs/resource/:resourceType/:resourceId
 * Get audit logs for a specific resource
 */
router.get('/logs/resource/:resourceType/:resourceId', async (req, res) => {
    const user = req.user;
    const { resourceType, resourceId } = req.params;
    const { limit = '50', offset = '0' } = req.query;
    const result = await audit_service_1.AuditService.getResourceLogs(resourceType, resourceId, Math.min(parseInt(limit, 10), 100), parseInt(offset, 10));
    // Non-admins can only see logs for resources they own
    if (!user.isAdmin) {
        result.logs = result.logs.filter(log => log.user_id === user.id);
    }
    res.json({
        logs: result.logs,
        pagination: {
            total: result.total,
            limit: parseInt(limit, 10),
            offset: parseInt(offset, 10),
            hasMore: result.total > parseInt(offset, 10) + parseInt(limit, 10),
        },
    });
});
/**
 * GET /api/v1/audit/security
 * Get recent security events (admin only)
 */
router.get('/security', async (req, res) => {
    const user = req.user;
    if (!user.isAdmin) {
        throw new errors_1.AppError('Unauthorized - Admin access required', 403);
    }
    const { limit = '100' } = req.query;
    const events = await audit_service_1.AuditService.getRecentSecurityEvents(Math.min(parseInt(limit, 10), 500));
    res.json({ events });
});
/**
 * GET /api/v1/audit/stats
 * Get audit log statistics
 */
router.get('/stats', async (req, res) => {
    const user = req.user;
    if (!user.isAdmin) {
        throw new errors_1.AppError('Unauthorized - Admin access required', 403);
    }
    const { startDate, endDate } = req.query;
    const stats = await audit_service_1.AuditService.getStats(startDate ? new Date(startDate) : undefined, endDate ? new Date(endDate) : undefined);
    res.json({ stats });
});
/**
 * GET /api/v1/audit/activity-summary
 * Get user activity summary (admin only)
 */
router.get('/activity-summary', async (req, res) => {
    const user = req.user;
    if (!user.isAdmin) {
        throw new errors_1.AppError('Unauthorized - Admin access required', 403);
    }
    const { userId } = req.query;
    const summary = await audit_service_1.AuditService.getUserActivitySummary(userId);
    res.json({ summary });
});
/**
 * POST /api/v1/audit/cleanup
 * Manually trigger audit log cleanup (admin only)
 */
router.post('/cleanup', async (req, res) => {
    const user = req.user;
    if (!user.isAdmin) {
        throw new errors_1.AppError('Unauthorized - Admin access required', 403);
    }
    await audit_service_1.AuditService.cleanup();
    // Log the cleanup action
    await audit_service_1.AuditService.logFromRequest(req, 'system.maintenance_start', {
        description: 'Audit log cleanup triggered manually',
    });
    res.json({
        success: true,
        message: 'Audit log cleanup completed',
    });
});
exports.default = router;
//# sourceMappingURL=audit.js.map