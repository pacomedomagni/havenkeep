import { Router, Request, Response } from 'express';
import { authenticate, requireAdmin, verifyAdminFresh } from '../middleware/auth';
import { AuditService, AuditAction, AuditSeverity } from '../services/audit.service';
import { AppError } from '../utils/errors';
import { asyncHandler } from '../utils/async-handler';
import { sendSuccess, sendMessage } from '../utils/response';
import { readRateLimiter } from '../middleware/rateLimiter';

const router = Router();

// All audit routes require authentication
router.use(authenticate);

// F089: per-IP cap on read endpoints. /audit/logs returns admin-grade data
// and the join is expensive — keep it from doubling as a scraper API.
router.use((req, res, next) => {
  if (req.method === 'GET') return readRateLimiter(req, res, next);
  return next();
});

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

  // S-C1: re-derive admin from the DB instead of trusting the cached
  // req.user.isAdmin (10s TTL). A demoted admin must lose cross-tenant
  // read access immediately, not after the cache expires.
  const isAdminFresh = await verifyAdminFresh(user.id);

  // Non-admins can only see their own logs
  const userId = isAdminFresh ? (req.query.userId as string) : user.id;

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

  // S-C1: fresh DB-derived admin check (see /logs comment).
  const isAdminFresh = await verifyAdminFresh(user.id);

  const result = isAdminFresh
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
// S-C1: requireAdmin middleware does a fresh DB read on every call;
// removes the 10s stale-cache window for demoted admins.
router.get('/security', requireAdmin, asyncHandler(async (req: Request, res: Response) => {
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
router.get('/stats', requireAdmin, asyncHandler(async (req: Request, res: Response) => {
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
router.get('/activity-summary', requireAdmin, asyncHandler(async (req: Request, res: Response) => {
  const { userId } = req.query;

  const summary = await AuditService.getUserActivitySummary(userId as string | undefined);

  sendSuccess(res, summary);
}));

/**
 * POST /api/v1/audit/cleanup
 * Manually trigger audit log cleanup (admin only).
 *
 * Cleanup is irreversible — it deletes years of audit history — so this
 * route requires the caller to supply both:
 *   - confirm: 'PURGE'             (string token typed in by the operator)
 *   - confirmation_phrase: any 64+ char operator-typed phrase that matches
 *     the configured CLEANUP_CONFIRMATION_PHRASE env var (HMAC-compared).
 * The audit row produced for the cleanup itself is logged BEFORE running so
 * the trail of *who triggered* survives even though the trigger removes
 * older info-level entries.
 */
router.post('/cleanup', requireAdmin, asyncHandler(async (req: Request, res: Response) => {
  const { confirm, confirmation_phrase } = req.body ?? {};
  if (confirm !== 'PURGE') {
    throw new AppError(
      "Audit cleanup requires `confirm: 'PURGE'` in the request body",
      400,
    );
  }
  const expected = process.env.AUDIT_CLEANUP_CONFIRMATION_PHRASE;
  if (!expected || expected.length < 32) {
    throw new AppError(
      'Audit cleanup not configured: AUDIT_CLEANUP_CONFIRMATION_PHRASE env var must be set (>=32 chars)',
      503,
    );
  }
  const a = Buffer.from(String(confirmation_phrase ?? ''), 'utf8');
  const b = Buffer.from(expected, 'utf8');
  // Constant-time compare; reject if length mismatches.
  const equalLen = a.length === b.length;
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const crypto = require('crypto') as typeof import('crypto');
  if (!equalLen || !crypto.timingSafeEqual(a, b)) {
    throw new AppError('Confirmation phrase does not match', 403);
  }

  // Log BEFORE running so the actor is captured even if the cleanup wipes
  // older info-level rows.
  await AuditService.logFromRequest(req, 'system.maintenance_start', {
    severity: 'critical',
    description: 'Audit log cleanup triggered manually (irreversible)',
    metadata: { confirmed: true },
  });

  await AuditService.cleanup();

  sendMessage(res, 'Audit log cleanup completed');
}));

export default router;
