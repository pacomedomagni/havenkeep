import { Router, Request, Response } from 'express';
import { authenticate } from '../middleware/auth';
import { AuditService, AuditAction, AuditSeverity } from '../services/audit.service';
import { AppError } from '../utils/errors';

const router = Router();

// All audit routes require authentication
router.use(authenticate);

/**
 * GET /api/v1/audit/logs
 * Query audit logs with filters (admin or own logs)
 */
router.get('/logs', async (req: Request, res: Response) => {
  const user = req.user!;
  const {
    action,
    severity,
    resourceType,
    resourceId,
    startDate,
    endDate,
    success,
    limit = '50',
    offset = '0',
  } = req.query;

  // Non-admins can only see their own logs
  const userId = user.isAdmin ? (req.query.userId as string) : user.id;

  const filters = {
    userId,
    action: action as AuditAction | undefined,
    severity: severity as AuditSeverity | undefined,
    resourceType: resourceType as string | undefined,
    resourceId: resourceId as string | undefined,
    startDate: startDate ? new Date(startDate as string) : undefined,
    endDate: endDate ? new Date(endDate as string) : undefined,
    success: success !== undefined ? success === 'true' : undefined,
    limit: Math.min(parseInt(limit as string, 10), 100),
    offset: parseInt(offset as string, 10),
  };

  const result = await AuditService.query(filters);

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
router.get('/logs/me', async (req: Request, res: Response) => {
  const user = req.user!;
  const { limit = '50', offset = '0' } = req.query;

  const result = await AuditService.getUserLogs(
    user.id,
    Math.min(parseInt(limit as string, 10), 100),
    parseInt(offset as string, 10)
  );

  res.json({
    logs: result.logs,
    pagination: {
      total: result.total,
      limit: parseInt(limit as string, 10),
      offset: parseInt(offset as string, 10),
      hasMore: result.total > parseInt(offset as string, 10) + parseInt(limit as string, 10),
    },
  });
});

/**
 * GET /api/v1/audit/logs/resource/:resourceType/:resourceId
 * Get audit logs for a specific resource
 */
router.get('/logs/resource/:resourceType/:resourceId', async (req: Request, res: Response) => {
  const user = req.user!;
  const { resourceType, resourceId } = req.params;
  const { limit = '50', offset = '0' } = req.query;

  const result = await AuditService.getResourceLogs(
    resourceType,
    resourceId,
    Math.min(parseInt(limit as string, 10), 100),
    parseInt(offset as string, 10)
  );

  // Non-admins can only see logs for resources they own
  if (!user.isAdmin) {
    result.logs = result.logs.filter(log => log.user_id === user.id);
  }

  res.json({
    logs: result.logs,
    pagination: {
      total: result.total,
      limit: parseInt(limit as string, 10),
      offset: parseInt(offset as string, 10),
      hasMore: result.total > parseInt(offset as string, 10) + parseInt(limit as string, 10),
    },
  });
});

/**
 * GET /api/v1/audit/security
 * Get recent security events (admin only)
 */
router.get('/security', async (req: Request, res: Response) => {
  const user = req.user!;

  if (!user.isAdmin) {
    throw new AppError('Unauthorized - Admin access required', 403);
  }

  const { limit = '100' } = req.query;

  const events = await AuditService.getRecentSecurityEvents(
    Math.min(parseInt(limit as string, 10), 500)
  );

  res.json({ events });
});

/**
 * GET /api/v1/audit/stats
 * Get audit log statistics
 */
router.get('/stats', async (req: Request, res: Response) => {
  const user = req.user!;

  if (!user.isAdmin) {
    throw new AppError('Unauthorized - Admin access required', 403);
  }

  const { startDate, endDate } = req.query;

  const stats = await AuditService.getStats(
    startDate ? new Date(startDate as string) : undefined,
    endDate ? new Date(endDate as string) : undefined
  );

  res.json({ stats });
});

/**
 * GET /api/v1/audit/activity-summary
 * Get user activity summary (admin only)
 */
router.get('/activity-summary', async (req: Request, res: Response) => {
  const user = req.user!;

  if (!user.isAdmin) {
    throw new AppError('Unauthorized - Admin access required', 403);
  }

  const { userId } = req.query;

  const summary = await AuditService.getUserActivitySummary(userId as string | undefined);

  res.json({ summary });
});

/**
 * POST /api/v1/audit/cleanup
 * Manually trigger audit log cleanup (admin only)
 */
router.post('/cleanup', async (req: Request, res: Response) => {
  const user = req.user!;

  if (!user.isAdmin) {
    throw new AppError('Unauthorized - Admin access required', 403);
  }

  await AuditService.cleanup();

  // Log the cleanup action
  await AuditService.logFromRequest(req, 'system.maintenance_start', {
    description: 'Audit log cleanup triggered manually',
  });

  res.json({
    success: true,
    message: 'Audit log cleanup completed',
  });
});

export default router;
