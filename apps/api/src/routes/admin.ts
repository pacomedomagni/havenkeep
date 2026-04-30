import { Router } from 'express';
import Joi from 'joi';
import { query, getClient } from '../db';
import { harvestUserKeys, flattenHarvest, removeKeysBestEffort } from '../utils/storage-cleanup';
import { authenticate, requireAdmin, invalidateUserCache } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { paginationSchema } from '../validators';
import { userIdParamSchema, dateRangeQuerySchema, rejectPartnerBodySchema } from '../validators/admin.validator';
import { writeRateLimiter } from '../middleware/rateLimiter';
import { AppError } from '../utils/errors';
import { AuditService } from '../services/audit.service';
import { getRedisClient } from '../utils/redis';
import { logger } from '../utils/logger';
import { sendSuccess, sendMessage } from '../utils/response';

const ADMIN_STATS_TTL = 60; // 60 seconds

// Strip control chars + cap length so a malicious email/note can't smuggle
// fake newline-delimited audit entries (Ch01-F058).
function sanitizeAuditText(value: unknown, max = 200): string {
  if (typeof value !== 'string') return '';
  return value
    .replace(/[\x00-\x1f\x7f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

const router = Router();
router.use(authenticate);

// Audit Ch01-F074: /admin/me must be admin-only. Partners and regular users
// have /users/me + /partners/me already; this route was being treated as a
// generic "who am I" but its name and presence under /admin imply admin
// scope.
router.get('/me', requireAdmin, (req, res) => {
  sendSuccess(res, {
    id: req.user!.id,
    email: req.user!.email,
    plan: req.user!.plan,
    is_admin: req.user!.isAdmin,
    is_partner: req.user!.isPartner,
  });
});

// All routes below require admin
router.use(requireAdmin);

// Admin stats overview (basic)
router.get('/stats', async (req, res, next) => {
  try {
    // Check Redis cache first
    try {
      const redis = await getRedisClient();
      const cached = await redis.get('admin:stats');
      if (cached) {
        return sendSuccess(res, JSON.parse(cached));
      }
    } catch (err) {
      logger.warn({ err }, 'Redis cache read failed for admin:stats, falling back to DB');
    }

    // Audit Ch01-F075: every count below now excludes soft-deleted users.
    // Items + partner_gifts + warranty_claims are scoped to non-deleted
    // users via the FK; we filter at the source so the totals reflect the
    // live customer base, not historical churn.
    const stats = await query(`
      SELECT
        (SELECT COUNT(*) FROM users WHERE deleted_at IS NULL) as total_users,
        (SELECT COUNT(*) FROM users WHERE plan = 'premium' AND deleted_at IS NULL) as premium_users,
        (SELECT COUNT(*) FROM items i JOIN users u ON u.id = i.user_id WHERE u.deleted_at IS NULL) as total_items,
        (SELECT COALESCE(SUM(i.price), 0) FROM items i JOIN users u ON u.id = i.user_id WHERE u.deleted_at IS NULL) as total_value,
        (SELECT COUNT(*) FROM partners p JOIN users u ON u.id = p.user_id WHERE p.is_active = TRUE AND u.deleted_at IS NULL) as active_partners,
        (SELECT COUNT(*) FROM partner_gifts) as total_gifts,
        (SELECT COUNT(*) FROM warranty_claims wc JOIN users u ON u.id = wc.user_id WHERE u.deleted_at IS NULL) as total_claims
    `);

    // Cache the result in Redis with 60-second TTL
    try {
      const redis = await getRedisClient();
      await redis.set('admin:stats', JSON.stringify(stats.rows[0]), { EX: ADMIN_STATS_TTL });
    } catch (err) {
      logger.warn({ err }, 'Redis cache write failed for admin:stats');
    }

    sendSuccess(res, stats.rows[0]);
  } catch (error) {
    next(error);
  }
});

// S2-K: audit log hash-chain integrity check. Returns `{ ok: true }` when
// the chain is intact, otherwise `{ ok: false, brokenAt }` with the first
// row whose hash doesn't agree with its predecessor. Backed by the
// `verify_audit_chain()` SQL function installed in mig 065.
router.get('/audit/verify', async (req, res, next) => {
  try {
    const broken = await AuditService.verifyHashChain();
    if (broken.length === 0) {
      sendSuccess(res, { ok: true, lastVerifiedAt: new Date().toISOString() });
      return;
    }
    sendSuccess(res, {
      ok: false,
      lastVerifiedAt: new Date().toISOString(),
      brokenAt: {
        id: broken[0].broken_id,
        at: broken[0].broken_at,
      },
      brokenCount: broken.length,
    });
  } catch (error) {
    next(error);
  }
});

// Full admin stats (dashboard overview)
router.get('/stats/full', async (req, res, next) => {
  try {
    // Check Redis cache first
    try {
      const redis = await getRedisClient();
      const cached = await redis.get('admin:stats:full');
      if (cached) {
        return sendSuccess(res, JSON.parse(cached));
      }
    } catch (err) {
      logger.warn({ err }, 'Redis cache read failed for admin:stats:full, falling back to DB');
    }

    // S1-D: every users count filters soft-deletes so stats reflect live
    // accounts. Items don't have soft-delete (only is_archived); intent
    // here is "all items ever indexed," so leave the items counts alone.
    const stats = await query(`
      SELECT
        (SELECT COUNT(*) FROM users WHERE deleted_at IS NULL) AS total_users,
        (SELECT COUNT(*) FROM users WHERE plan = 'premium' AND deleted_at IS NULL) AS premium_users,
        (SELECT COUNT(*) FROM items) AS total_items,
        (SELECT COUNT(*) FROM items WHERE created_at >= NOW() - INTERVAL '24 hours') AS items_last_24h,
        (SELECT COUNT(*) FROM users WHERE created_at >= NOW() - INTERVAL '24 hours' AND deleted_at IS NULL) AS signups_last_24h,
        (SELECT COUNT(*) FROM users WHERE created_at >= NOW() - INTERVAL '7 days' AND deleted_at IS NULL) AS signups_last_7d,
        (SELECT COUNT(*) FROM users WHERE created_at >= NOW() - INTERVAL '30 days' AND deleted_at IS NULL) AS signups_last_30d,
        (SELECT COALESCE(SUM(price), 0) FROM items) AS total_value_protected,
        (SELECT COUNT(DISTINCT ua.user_id) FROM user_analytics ua WHERE ua.last_active_at >= NOW() - INTERVAL '24 hours') AS dau,
        (SELECT COUNT(DISTINCT ua.user_id) FROM user_analytics ua WHERE ua.last_active_at >= NOW() - INTERVAL '7 days') AS wau,
        (SELECT COUNT(DISTINCT ua.user_id) FROM user_analytics ua WHERE ua.last_active_at >= NOW() - INTERVAL '30 days') AS mau
    `);

    // Cache the result in Redis with 60-second TTL
    try {
      const redis = await getRedisClient();
      await redis.set('admin:stats:full', JSON.stringify(stats.rows[0]), { EX: ADMIN_STATS_TTL });
    } catch (err) {
      logger.warn({ err }, 'Redis cache write failed for admin:stats:full');
    }

    sendSuccess(res, stats.rows[0]);
  } catch (error) {
    next(error);
  }
});

// Daily signups for charts
router.get('/stats/daily-signups', validate(dateRangeQuerySchema, 'query'), async (req, res, next) => {
  try {
    const days = (req.query.days as any) || 30;
    const result = await query(`
      SELECT
        DATE(created_at) AS date,
        COUNT(*) AS count
      FROM users
      WHERE created_at >= NOW() - MAKE_INTERVAL(days => $1)
      GROUP BY DATE(created_at)
      ORDER BY date ASC
    `, [days]);
    sendSuccess(res, result.rows);
  } catch (error) {
    next(error);
  }
});

// Daily items for charts
router.get('/stats/daily-items', validate(dateRangeQuerySchema, 'query'), async (req, res, next) => {
  try {
    const days = (req.query.days as any) || 30;
    const result = await query(`
      SELECT
        DATE(created_at) AS date,
        COUNT(*) AS count
      FROM items
      WHERE created_at >= NOW() - MAKE_INTERVAL(days => $1)
      GROUP BY DATE(created_at)
      ORDER BY date ASC
    `, [days]);
    sendSuccess(res, result.rows);
  } catch (error) {
    next(error);
  }
});

// User activity list
router.get('/users/activity', async (req, res, next) => {
  try {
    const result = await query(`
      SELECT
        u.id,
        u.email,
        u.full_name,
        u.plan,
        u.created_at,
        COUNT(DISTINCT i.id)::int AS total_items,
        COALESCE(SUM(i.price), 0)::numeric AS total_value,
        MAX(GREATEST(i.created_at, i.updated_at)) AS last_activity
      FROM users u
      LEFT JOIN items i ON i.user_id = u.id AND i.is_archived = FALSE
      WHERE u.deleted_at IS NULL
      GROUP BY u.id, u.email, u.full_name, u.plan, u.created_at
      ORDER BY u.created_at DESC
      LIMIT 500
    `);
    sendSuccess(res, result.rows);
  } catch (error) {
    next(error);
  }
});

// Admin user listing with pagination
router.get('/users', validate(paginationSchema, 'query'), async (req, res, next) => {
  try {
    const { page, limit } = req.query as any;

    // BE-1/2/3: Explicitly convert and clamp pagination params to safe integers
    const pageNum = Math.max(1, parseInt(page as string, 10) || 1);
    const limitNum = Math.min(100, Math.max(1, parseInt(limit as string, 10) || 20));
    const offset = (pageNum - 1) * limitNum;

    const [result, countResult] = await Promise.all([
      query(
        `SELECT * FROM user_stats ORDER BY created_at DESC LIMIT $1 OFFSET $2`,
        [limitNum, offset]
      ),
      query(`SELECT COUNT(*) FROM users`),
    ]);

    const total = parseInt(countResult.rows[0].count, 10);

    sendSuccess(res, result.rows, {
      pagination: {
        page: pageNum,
        limit: limitNum,
        total,
        total_pages: Math.ceil(total / limitNum),
      },
    });
  } catch (error) {
    next(error);
  }
});

// Audit Ch01-F052/F058: suspend records a sanitized reason in the audit
// metadata so investigators can see WHY without trusting raw input.
const suspendBodySchema = Joi.object({
  reason: Joi.string().trim().max(500).optional(),
  cancel_revenuecat: Joi.boolean().optional(),
}).rename('cancelRevenuecat', 'cancel_revenuecat', { ignoreUndefined: true, override: false });

// Suspend user (downgrade to free and invalidate all sessions)
router.put('/users/:id/suspend',
  writeRateLimiter,
  validate(userIdParamSchema, 'params'),
  validate(suspendBodySchema, 'body'),
  async (req, res, next) => {
  try {
    const { id } = req.params;

    // Check if target user exists and whether they are an admin
    const targetUser = await query(
      `SELECT id, email, is_admin FROM users WHERE id = $1`,
      [id]
    );

    if (targetUser.rows.length === 0) {
      throw new AppError('User not found', 404);
    }

    if (targetUser.rows[0].is_admin) {
      // Attempting to suspend another admin is an anomalous event — log it
      // as a security signal so a rogue admin doesn't fly under the radar.
      await AuditService.logFromRequest(req, 'admin.settings_change', {
        severity: 'warning',
        resourceType: 'user',
        resourceId: id,
        description: `Admin attempted to suspend another admin: ${sanitizeAuditText(targetUser.rows[0].email)}`,
        success: false,
        errorMessage: 'suspend_admin_blocked',
      }).catch(() => {});
      throw new AppError('Cannot suspend an admin user', 400);
    }

    // Capture the prior plan so unsuspend can restore it. We're inside an
    // implicit auto-commit so this is a single SET-and-CASE statement.
    await query(
      `UPDATE users
          SET plan_before_suspend = CASE
                                      WHEN plan <> 'suspended' THEN plan
                                      ELSE plan_before_suspend
                                    END,
              plan = 'suspended',
              updated_at = NOW()
        WHERE id = $1`,
      [id],
    );

    // Invalidate all refresh tokens so the suspended user gets signed out
    await query(`DELETE FROM refresh_tokens WHERE user_id = $1`, [id]);

    // 2.3: drop the user-row cache so other replicas don't keep a fresh
    // 'plan' value live for the next 10s. A short window where a hostile
    // session keeps authenticating as premium is exactly what audit-P-HI-03
    // flagged.
    await invalidateUserCache(id);

    const reason = sanitizeAuditText((req.body as any)?.reason);
    await AuditService.logFromRequest(req, 'admin.settings_change', {
      severity: 'warning',
      resourceType: 'user',
      resourceId: id,
      description: `Admin suspended user: ${sanitizeAuditText(targetUser.rows[0].email)}`,
      metadata: reason ? { reason } : undefined,
    });

    sendSuccess(res, { id, email: targetUser.rows[0].email }, { message: 'User suspended' });
  } catch (error) {
    next(error);
  }
});

// Unsuspend user (restore to prior plan).
//
// 3.16: previously this also cleared `deleted_at` + `deletion_scheduled_for`,
// which silently overrode a soft-delete the user had initiated themselves.
// That's the wrong shape — recovering a soft-deleted account is the user's
// decision (via /me/recover), not an admin side-effect. Two changes:
//
//   1. Refuse to unsuspend a soft-deleted row. The admin sees a 409 and
//      learns the user has a deletion in flight; if the admin wants to
//      reverse it they have to cancel the deletion explicitly via a
//      separate path (currently /me/recover from the user's session, or
//      a future admin "cancel deletion" route).
//   2. The plan restore prefers `plan_before_suspend`, then
//      `plan_before_delete` (in case the user was suspended *while*
//      soft-deleted at some prior point), then 'free'.
router.put('/users/:id/unsuspend', validate(userIdParamSchema, 'params'), async (req, res, next) => {
  try {
    const { id } = req.params;

    const targetUser = await query(
      `SELECT id, deleted_at FROM users WHERE id = $1 AND plan = 'suspended'`,
      [id],
    );
    if (targetUser.rows.length === 0) {
      // Either the user doesn't exist or they aren't suspended — disambiguate.
      const userExists = await query(`SELECT id, plan FROM users WHERE id = $1`, [id]);
      if (userExists.rows.length === 0) {
        throw new AppError('User not found', 404);
      }
      throw new AppError(`User is not suspended (current plan: ${userExists.rows[0].plan})`, 400);
    }
    if (targetUser.rows[0].deleted_at) {
      throw new AppError(
        'Cannot unsuspend a soft-deleted account; the user must recover it first via /me/recover',
        409,
      );
    }

    const result = await query(
      `UPDATE users
          SET plan = COALESCE(plan_before_suspend, plan_before_delete, 'free'),
              plan_before_suspend = NULL,
              updated_at = NOW()
        WHERE id = $1 AND plan = 'suspended'
        RETURNING id, email, plan`,
      [id],
    );

    if (result.rows.length === 0) {
      // Defensive: a concurrent delete or unsuspend won the race.
      throw new AppError('User state changed during unsuspend; retry', 409);
    }

    // 2.3: same reason as suspend — the cached row still has plan='suspended'
    // until the 10s TTL expires; drop it now.
    await invalidateUserCache(id);

    await AuditService.logFromRequest(req, 'admin.settings_change', {
      severity: 'info',
      resourceType: 'user',
      resourceId: id,
      description: `Admin unsuspended user: ${result.rows[0].email}`,
    });

    sendSuccess(res, result.rows[0], { message: 'User unsuspended' });
  } catch (error) {
    next(error);
  }
});

// Audit Ch01-F059: hard-delete is irreversible and cascades across 19+
// tables. Require an explicit `{ confirm: 'DELETE', reason: '<200 chars>' }`
// body so a stray DELETE call from a misconfigured admin tool can't wipe a
// real user. The reason is recorded in audit metadata for forensic review.
const adminDeleteUserBodySchema = Joi.object({
  confirm: Joi.string().valid('DELETE').required(),
  reason: Joi.string().trim().min(1).max(500).required(),
});

router.delete(
  '/users/:id',
  writeRateLimiter,
  validate(userIdParamSchema, 'params'),
  validate(adminDeleteUserBodySchema, 'body'),
  async (req, res, next) => {
    try {
      const { id } = req.params;
      const { reason } = req.body;

      if (id === req.user!.id) {
        throw new AppError('Cannot delete your own account', 400);
      }

      // 1.1: harvest every MinIO key the user owns BEFORE the SQL
      // DELETE cascades. Without this, every avatar / item image /
      // document / thumbnail leaks permanently into the bucket.
      const client = await getClient();
      let harvest: Awaited<ReturnType<typeof harvestUserKeys>> | null = null;
      let result;
      try {
        await client.query('BEGIN');
        harvest = await harvestUserKeys(client, id);
        await client.query(`DELETE FROM refresh_tokens WHERE user_id = $1`, [id]);
        result = await client.query(
          `DELETE FROM users WHERE id = $1 RETURNING id, email`,
          [id],
        );
        if (result.rows.length === 0) {
          await client.query('ROLLBACK').catch(() => {});
          throw new AppError('User not found', 404);
        }
        await client.query('COMMIT');
      } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        throw err;
      } finally {
        client.release();
      }

      // Post-commit cleanup. Best-effort.
      if (harvest) {
        await removeKeysBestEffort(flattenHarvest(harvest));
      }

      await AuditService.logFromRequest(req, 'admin.user_delete', {
        severity: 'critical',
        resourceType: 'user',
        resourceId: id,
        description: `Admin deleted user: ${sanitizeAuditText(result.rows[0].email)}`,
        metadata: { reason: sanitizeAuditText(reason) },
      });

      sendSuccess(res, result.rows[0], { message: 'User deleted' });
    } catch (error) {
      next(error);
    }
  },
);

// ========== PARTNER MANAGEMENT ==========

// List pending partners (status = 'pending')
router.get('/partners/pending', async (req, res, next) => {
  try {
    const result = await query(
      `SELECT p.*, u.email, u.full_name
       FROM partners p
       JOIN users u ON u.id = p.user_id
       WHERE p.status = 'pending'
       ORDER BY p.created_at DESC`
    );

    sendSuccess(res, result.rows);
  } catch (error) {
    next(error);
  }
});

// H-A9 (audit): partner status state-machine guards.
//
// The prior approve / reject routes flipped status unconditionally with
// no prior-state check, no audit-metadata capture of the transition,
// and no session/cache invalidation on revoke. Three problems:
//   1. A previously rejected partner could be silently re-approved via
//      `rejected -> active` with no two-admin gate or re-review. The
//      audit row said "Admin approved" with no prior-status context.
//   2. A revoked partner kept in-flight refresh tokens and a 10s-cached
//      user-row claiming is_partner=true. Combined with H-A8's prior
//      shape, the dashboard middleware also kept routing them to the
//      partner shell for up to JWT_EXPIRES_IN.
//   3. No prior_status in the audit log meant "how did this partner
//      end up active?" had to be reconstructed from updated_at scans.
//
// Allowed transitions:
//   pending  -> active    via /approve  (no-op if already active)
//   pending  -> rejected  via /reject
//   active   -> rejected  via /reject   (revoke — burns sessions)
//   rejected -> *         REFUSED. A separate /reinstate route can be
//                         added later with stricter gating; for now an
//                         operator can manually flip via SQL with full
//                         forensic context.
async function loadPartnerForStateChange(
  id: string,
): Promise<{ id: string; user_id: string; status: string; company_name: string | null }> {
  const lookup = await query<{
    id: string;
    user_id: string;
    status: string;
    company_name: string | null;
  }>(
    `SELECT id, user_id, status, company_name FROM partners WHERE id = $1`,
    [id],
  );
  if (lookup.rows.length === 0) {
    throw new AppError('Partner not found', 404);
  }
  return lookup.rows[0];
}

// Approve a partner (status = 'active')
router.put('/partners/:id/approve', validate(userIdParamSchema, 'params'), async (req, res, next) => {
  try {
    const { id } = req.params;
    const partner = await loadPartnerForStateChange(id);
    const priorStatus = partner.status;

    if (priorStatus === 'active') {
      // Idempotent — surface the current row but skip the audit /
      // session-invalidation churn. The dashboard's "approve" button
      // can race a concurrent admin click; both should not produce
      // two audit rows.
      sendSuccess(res, partner, { message: 'Partner already active' });
      return;
    }
    if (priorStatus !== 'pending') {
      throw new AppError(
        `Cannot transition partner from '${priorStatus}' to 'active'. Use a dedicated reinstate flow for previously-rejected partners.`,
        409,
        'CONFLICT',
      );
    }

    const result = await query(
      `UPDATE partners
         SET status = 'active', is_active = TRUE, updated_at = NOW()
         WHERE id = $1
         RETURNING *`,
      [id]
    );

    await AuditService.logFromRequest(req, 'admin.settings_change', {
      severity: 'info',
      resourceType: 'partner',
      resourceId: id,
      description: `Admin approved partner: ${result.rows[0].company_name || id}`,
      metadata: { from: priorStatus, to: 'active' },
    });

    // Drop the cached user row so the next call sees is_partner=true
    // immediately (otherwise the partner waits up to 10s for the cache
    // to expire before they can use partner endpoints).
    await invalidateUserCache(partner.user_id);

    sendSuccess(res, result.rows[0], { message: 'Partner approved' });
  } catch (error) {
    next(error);
  }
});

// Reject a partner (status = 'rejected'). Optional reason is captured in the
// audit log so an admin can answer "why was this partner rejected?" later
// (audit Ch10-W041). Stored as a string up to 1KB.
router.put('/partners/:id/reject', validate(userIdParamSchema, 'params'), validate(rejectPartnerBodySchema), async (req, res, next) => {
  try {
    const { id } = req.params;
    const reasonRaw = typeof req.body?.reason === 'string' ? req.body.reason.trim() : '';
    const reason = reasonRaw.slice(0, 1024);

    const partner = await loadPartnerForStateChange(id);
    const priorStatus = partner.status;

    if (priorStatus === 'rejected') {
      sendSuccess(res, partner, { message: 'Partner already rejected' });
      return;
    }
    if (priorStatus !== 'pending' && priorStatus !== 'active') {
      throw new AppError(
        `Cannot transition partner from '${priorStatus}' to 'rejected'.`,
        409,
        'CONFLICT',
      );
    }

    const result = await query(
      `UPDATE partners
         SET status = 'rejected', is_active = FALSE, updated_at = NOW()
         WHERE id = $1
         RETURNING *`,
      [id]
    );

    await AuditService.logFromRequest(req, 'admin.settings_change', {
      severity: 'warning',
      resourceType: 'partner',
      resourceId: id,
      description:
        reason.length > 0
          ? `Admin rejected partner ${result.rows[0].company_name || id}: ${reason}`
          : `Admin rejected partner: ${result.rows[0].company_name || id}`,
      metadata: { from: priorStatus, to: 'rejected', ...(reason ? { reason } : {}) },
    });

    // active -> rejected is a session-revocation event, mirroring
    // /admin/users/:id/suspend. Burn every refresh token + invalidate
    // the user-row cache so an in-flight bearer token can't keep
    // exercising partner endpoints (the API's per-call requireAdmin/
    // requirePartner re-derives anyway, but this closes the race).
    if (priorStatus === 'active') {
      await query(`DELETE FROM refresh_tokens WHERE user_id = $1`, [partner.user_id]);
    }
    await invalidateUserCache(partner.user_id);

    sendSuccess(res, result.rows[0], { message: 'Partner rejected' });
  } catch (error) {
    next(error);
  }
});

// ========== PARTNER & COMMISSION ADMIN ENDPOINTS ==========

// Paginated list of ALL partners with user info and aggregate counts
router.get('/partners', validate(paginationSchema, 'query'), async (req, res, next) => {
  try {
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit as string, 10) || 20));
    const offset = (page - 1) * limit;

    const conditions: string[] = [];
    const params: any[] = [];
    let paramIndex = 1;

    if (typeof req.query.status === 'string') {
      const allowed = new Set(['pending', 'active', 'rejected']);
      if (!allowed.has(req.query.status)) {
        throw new AppError('Invalid status filter. Must be pending, active, or rejected.', 400);
      }
      conditions.push(`p.status = $${paramIndex++}`);
      params.push(req.query.status);
    } else if (req.query.is_active !== undefined) {
      // Legacy filter — translate to status. New callers should use ?status=.
      const isActive = req.query.is_active === 'true';
      conditions.push(`p.status = $${paramIndex++}`);
      params.push(isActive ? 'active' : 'pending');
    }

    if (req.query.partner_type) {
      conditions.push(`p.partner_type = $${paramIndex++}`);
      params.push(req.query.partner_type);
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    const [result, countResult] = await Promise.all([
      query(
        // Audit Ch01-F063: stripe_account_id is sensitive (it appears in the
        // Stripe dashboard URL and lets an admin pivot to the connected
        // account). Replace with a boolean `has_stripe_account` so admin UI
        // can show "connected" without leaking the real id. Audit Ch01-F065:
        // exclude soft-deleted user rows so the listing matches reality.
        `SELECT
          p.id,
          p.user_id,
          p.company_name,
          p.partner_type,
          p.phone,
          p.license_number,
          p.service_areas,
          p.brand_color,
          p.logo_url,
          (p.stripe_account_id IS NOT NULL) AS has_stripe_account,
          p.stripe_onboarded,
          u.referral_code,
          p.is_active,
          p.status,
          p.created_at,
          p.updated_at,
          u.email,
          u.full_name,
          COALESCE(SUM(pc.amount), 0)::numeric AS total_commissions_earned,
          COUNT(DISTINCT pg.id)::int AS total_gifts,
          (SELECT COUNT(*) FROM users ref WHERE ref.referred_by = p.user_id AND ref.deleted_at IS NULL)::int AS total_referrals
        FROM partners p
        JOIN users u ON u.id = p.user_id
        LEFT JOIN partner_commissions pc ON pc.partner_id = p.id
        LEFT JOIN partner_gifts pg ON pg.partner_id = p.id
        ${whereClause}${whereClause ? ' AND ' : 'WHERE '}u.deleted_at IS NULL
        GROUP BY p.id, u.email, u.full_name
        ORDER BY p.created_at DESC
        LIMIT $${paramIndex++} OFFSET $${paramIndex++}`,
        [...params, limit, offset]
      ),
      query(
        `SELECT COUNT(*) FROM partners p ${whereClause}`,
        params
      ),
    ]);

    const total = parseInt(countResult.rows[0].count, 10);

    sendSuccess(res, result.rows, {
      pagination: {
        page,
        limit,
        total,
        total_pages: Math.ceil(total / limit),
      },
    });
  } catch (error) {
    next(error);
  }
});

// Single partner detail with commission stats, gift count, referral count
router.get('/partners/:id', validate(userIdParamSchema, 'params'), async (req, res, next) => {
  try {
    const { id } = req.params;

    const result = await query(
      // Same `has_stripe_account` boolean as the list endpoint — Ch01-F063.
      // Admin UI can hit Stripe dashboard via partner email if needed.
      `SELECT
        p.id,
        p.user_id,
        p.company_name,
        p.partner_type,
        p.phone,
        p.license_number,
        p.service_areas,
        p.brand_color,
        p.logo_url,
        (p.stripe_account_id IS NOT NULL) AS has_stripe_account,
        p.stripe_onboarded,
        u.referral_code,
        p.is_active,
        p.status,
        p.created_at,
        p.updated_at,
        u.email,
        u.full_name,
        COALESCE(SUM(pc.amount) FILTER (WHERE pc.status = 'pending'), 0)::numeric AS total_pending_amount,
        COALESCE(SUM(pc.amount) FILTER (WHERE pc.status = 'paid' AND pc.stripe_transfer_id IS NOT NULL), 0)::numeric AS total_paid_amount,
        COUNT(DISTINCT pg.id)::int AS gift_count,
        (SELECT COUNT(*) FROM users ref WHERE ref.referred_by = p.user_id AND ref.deleted_at IS NULL)::int AS referral_count
      FROM partners p
      JOIN users u ON u.id = p.user_id
      LEFT JOIN partner_commissions pc ON pc.partner_id = p.id
      LEFT JOIN partner_gifts pg ON pg.partner_id = p.id
      WHERE p.id = $1 AND u.deleted_at IS NULL
      GROUP BY p.id, u.email, u.full_name`,
      [id]
    );

    if (result.rows.length === 0) {
      throw new AppError('Partner not found', 404);
    }

    sendSuccess(res, result.rows[0]);
  } catch (error) {
    next(error);
  }
});

// All commissions across all partners, paginated
router.get('/commissions', validate(paginationSchema, 'query'), async (req, res, next) => {
  try {
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit as string, 10) || 20));
    const offset = (page - 1) * limit;

    const conditions: string[] = [];
    const params: any[] = [];
    let paramIndex = 1;

    if (req.query.status) {
      const validStatuses = ['pending', 'approved', 'paid', 'cancelled'];
      if (!validStatuses.includes(req.query.status as string)) {
        throw new AppError('Invalid status. Must be one of: pending, approved, paid, cancelled', 400);
      }
      conditions.push(`pc.status = $${paramIndex++}`);
      params.push(req.query.status);
    }

    if (req.query.partner_id) {
      const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      if (!uuidRegex.test(req.query.partner_id as string)) {
        throw new AppError('Invalid partner_id format', 400);
      }
      conditions.push(`pc.partner_id = $${paramIndex++}`);
      params.push(req.query.partner_id);
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    const [result, countResult] = await Promise.all([
      query(
        `SELECT
          pc.id,
          pc.partner_id,
          pc.reference_id,
          pc.amount,
          pc.status,
          pc.created_at,
          p.company_name,
          u.email
        FROM partner_commissions pc
        JOIN partners p ON p.id = pc.partner_id
        JOIN users u ON u.id = p.user_id
        ${whereClause}
        ORDER BY pc.created_at DESC
        LIMIT $${paramIndex++} OFFSET $${paramIndex++}`,
        [...params, limit, offset]
      ),
      query(
        `SELECT COUNT(*) FROM partner_commissions pc ${whereClause}`,
        params
      ),
    ]);

    const total = parseInt(countResult.rows[0].count, 10);

    sendSuccess(res, result.rows, {
      pagination: {
        page,
        limit,
        total,
        total_pages: Math.ceil(total / limit),
      },
    });
  } catch (error) {
    next(error);
  }
});

// Aggregate commission stats across all partners
router.get('/commissions/stats', async (req, res, next) => {
  try {
    const result = await query(`
      SELECT
        COALESCE(SUM(amount) FILTER (WHERE status = 'pending'), 0)::numeric AS total_pending_amount,
        COALESCE(SUM(amount) FILTER (WHERE status = 'approved'), 0)::numeric AS total_approved_amount,
        COALESCE(SUM(amount) FILTER (WHERE status = 'paid'), 0)::numeric AS total_paid_amount,
        COALESCE(SUM(amount) FILTER (WHERE status = 'cancelled'), 0)::numeric AS total_cancelled_amount,
        COUNT(*) FILTER (WHERE status = 'pending')::int AS count_pending,
        COUNT(*) FILTER (WHERE status = 'approved')::int AS count_approved,
        COUNT(*) FILTER (WHERE status = 'paid')::int AS count_paid,
        COUNT(*) FILTER (WHERE status = 'cancelled')::int AS count_cancelled
      FROM partner_commissions
    `);

    sendSuccess(res, result.rows[0]);
  } catch (error) {
    next(error);
  }
});

export default router;
