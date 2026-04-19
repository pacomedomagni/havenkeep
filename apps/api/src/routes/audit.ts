import { Router, Request, Response } from 'express';
import { authenticate } from '../middleware/auth';
import { AuditService, AuditAction, AuditSeverity } from '../services/audit.service';
import { AppError } from '../utils/errors';
import { asyncHandler } from '../utils/async-handler';
import { sendSuccess, sendMessage } from '../utils/response';

const router = Router();

// All audit routes require authentication
router.use(authenticate);

/**
 * GET /api/v1/audit/logs
 * Query audit logs with filters (admin or own logs)
 */
router.get('/logs', asyncHandler(async (req: Request, res: Response) => {
  const user = req.user!;
  const {
    action,
    severity,
    resourceType,
    resourceId,
    startDate,
    endDate,
    success,
    page: pageRaw = '1',
    limit: limitRaw = '50',
  } = req.query;

  // Non-admins can only see their own logs
  const userId = user.isAdmin ? (req.query.userId as string) : user.id;

  const page = Math.max(1, parseInt(pageRaw as string, 10) || 1);
  const limit = Math.min(100, Math.max(1, parseInt(limitRaw as string, 10) || 50));
  const offset = (page - 1) * limit;

  const filters = {
    userId,
    action: action as AuditAction | undefined,
    severity: severity as AuditSeverity | undefined,
    resourceType: resourceType as string | undefined,
    resourceId: resourceId as string | undefined,
    startDate: startDate ? new Date(startDate as string) : undefined,
    endDate: endDate ? new Date(endDate as string) : undefined,
    success: success !== undefined ? success === 'true' : undefined,
    limit,
    offset,
  };

  const result = await AuditService.query(filters);

  sendSuccess(res, result.logs, {
    pagination: {
      page,
      limit,
      total: result.total,
      total_pages: Math.ceil(result.total / limit),
    },
  });
}));

/**
 * GET /api/v1/audit/logs/me
 * Get current user's audit logs
 */
router.get('/logs/me', asyncHandler(async (req: Request, res: Response) => {
  const user = req.user!;
  const { page: pageRaw = '1', limit: limitRaw = '50' } = req.query;
  const page = Math.max(1, parseInt(pageRaw as string, 10) || 1);
  const limit = Math.min(100, Math.max(1, parseInt(limitRaw as string, 10) || 50));
  const offset = (page - 1) * limit;

  const result = await AuditService.getUserLogs(user.id, limit, offset);

  sendSuccess(res, result.logs, {
    pagination: {
      page,
      limit,
      total: result.total,
      total_pages: Math.ceil(result.total / limit),
    },
  });
}));

/**
 * GET /api/v1/audit/logs/resource/:resourceType/:resourceId
 * Get audit logs for a specific resource
 */
router.get('/logs/resource/:resourceType/:resourceId', asyncHandler(async (req: Request, res: Response) => {
  const user = req.user!;
  const { resourceType, resourceId } = req.params;
  const { page: pageRaw = '1', limit: limitRaw = '50' } = req.query;
  const page = Math.max(1, parseInt(pageRaw as string, 10) || 1);
  const limit = Math.min(100, Math.max(1, parseInt(limitRaw as string, 10) || 50));
  const offset = (page - 1) * limit;

  const result = user.isAdmin
    ? await AuditService.getResourceLogs(resourceType, resourceId, limit, offset)
    : await AuditService.query({
        userId: user.id,
        resourceType,
        resourceId,
        limit,
        offset,
      });

  sendSuccess(res, result.logs, {
    pagination: {
      page,
      limit,
      total: result.total,
      total_pages: Math.ceil(result.total / limit),
    },
  });
}));

/**
 * GET /api/v1/audit/security
 * Get recent security events (admin only)
 */
router.get('/security', asyncHandler(async (req: Request, res: Response) => {
  const user = req.user!;

  if (!user.isAdmin) {
    throw new AppError('Unauthorized - Admin access required', 403);
  }

  const { limit = '100' } = req.query;

  const events = await AuditService.getRecentSecurityEvents(
    Math.min(parseInt(limit as string, 10), 500)
  );

  sendSuccess(res, events);
}));

/**
 * GET /api/v1/audit/stats
 * Get audit log statistics
 */
router.get('/stats', asyncHandler(async (req: Request, res: Response) => {
  const user = req.user!;

  if (!user.isAdmin) {
    throw new AppError('Unauthorized - Admin access required', 403);
  }

  const { startDate, endDate } = req.query;

  const stats = await AuditService.getStats(
    startDate ? new Date(startDate as string) : undefined,
    endDate ? new Date(endDate as string) : undefined
  );

  sendSuccess(res, stats);
}));

/**
 * GET /api/v1/audit/activity-summary
 * Get user activity summary (admin only)
 */
router.get('/activity-summary', asyncHandler(async (req: Request, res: Response) => {
  const user = req.user!;

  if (!user.isAdmin) {
    throw new AppError('Unauthorized - Admin access required', 403);
  }

  const { userId } = req.query;

  const summary = await AuditService.getUserActivitySummary(userId as string | undefined);

  sendSuccess(res, summary);
}));

/**
 * POST /api/v1/audit/cleanup
 * Manually trigger audit log cleanup (admin only)
 */
router.post('/cleanup', asyncHandler(async (req: Request, res: Response) => {
  const user = req.user!;

  if (!user.isAdmin) {
    throw new AppError('Unauthorized - Admin access required', 403);
  }

  await AuditService.cleanup();

  // Log the cleanup action
  await AuditService.logFromRequest(req, 'system.maintenance_start', {
    description: 'Audit log cleanup triggered manually',
  });

  sendMessage(res, 'Audit log cleanup completed');
}));

export default router;
