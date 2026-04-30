import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { config } from '../config';
import { AppError } from '../utils/errors';
import { query } from '../db';
import { isTokenBlacklisted } from '../utils/token-blacklist';
import { logger, requestContext } from '../utils/logger';
import { getRedisClient } from '../utils/redis';

export type AuthRequest = Request;

const USER_CACHE_TTL_SEC = 10;

// Track Redis-cache failures so we don't spam the log on every request when
// Redis flaps (Ch01-F043). Once we've seen N misses in a row, log only one
// warning per minute. Reset to verbose on first success.
let redisFailWindow: { count: number; lastLogAt: number } = { count: 0, lastLogAt: 0 };
const REDIS_FAIL_LOG_INTERVAL_MS = 60_000;

function noteRedisFailure(err: unknown, userId: string): void {
  const now = Date.now();
  redisFailWindow.count += 1;
  if (now - redisFailWindow.lastLogAt > REDIS_FAIL_LOG_INTERVAL_MS) {
    logger.warn(
      { err, userId, suppressed: redisFailWindow.count - 1 },
      'Redis user-cache read/write failure (rate-limited log)',
    );
    redisFailWindow.lastLogAt = now;
    redisFailWindow.count = 0;
  }
}

function noteRedisSuccess(): void {
  if (redisFailWindow.count > 0) {
    redisFailWindow = { count: 0, lastLogAt: 0 };
  }
}

/// 2.3: drops the cached `user:<id>` row used by `authenticate()`. Call
/// from any event that mutates fields the cache stores
/// (`plan`, `is_admin`, `deleted_at`, `email_verified`, `plan_expires_at`,
/// or the partner-status JOIN) so other replicas don't keep authorising
/// the user under the previous state for the next 10s. Failures are
/// logged but not thrown — the worst case is the cache TTL still expires
/// in <=10s.
export async function invalidateUserCache(userId: string): Promise<void> {
  try {
    const redis = await getRedisClient();
    await redis.del(`user:${userId}`);
  } catch (err) {
    logger.warn({ err, userId }, 'invalidateUserCache failed');
  }
}

export async function authenticate(
  req: Request,
  res: Response,
  next: NextFunction,
) {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new AppError('No token provided', 401);
    }

    const token = authHeader.substring(7);

    if (await isTokenBlacklisted(token)) {
      throw new AppError('Token has been revoked', 401);
    }

    // S-HI-02: pin algorithms. The Apple JWT verification at auth.ts:1079
    // already pins ['RS256']; do the same for our HS256 access tokens so a
    // future JWT_SECRET swap to RSA-public-key material can't be exploited
    // via HS256 forgery.
    const decoded = jwt.verify(token, config.jwt.secret, { algorithms: ['HS256'] }) as {
      userId: string;
      email: string;
    };

    const userCacheKey = `user:${decoded.userId}`;
    let userRow: any = null;

    try {
      const redis = await getRedisClient();
      const cached = await redis.get(userCacheKey);
      if (cached) {
        userRow = JSON.parse(cached);
        noteRedisSuccess();
      }
    } catch (err) {
      noteRedisFailure(err, decoded.userId);
    }

    if (!userRow) {
      // Audit Ch01-F040: include `deleted_at` so a soft-deleted user with a
      // still-valid access token is rejected on the next call. The plan
      // check below rejects 'suspended' users on the same path.
      // C13b: also pull deletion_scheduled_for so we can carve out an
      // exception for POST /me/recover during the cooling-off window.
      const result = await query(
        `SELECT u.id, u.email, u.plan, u.is_admin, u.plan_expires_at, u.email_verified,
                u.deleted_at, u.deletion_scheduled_for,
                (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = u.id AND p.is_active = TRUE)) as is_partner
         FROM users u WHERE u.id = $1`,
        [decoded.userId],
      );

      if (result.rows.length === 0) {
        throw new AppError('Invalid token', 401);
      }

      userRow = result.rows[0];

      try {
        const redis = await getRedisClient();
        await redis.set(userCacheKey, JSON.stringify(userRow), { EX: USER_CACHE_TTL_SEC });
        noteRedisSuccess();
      } catch (err) {
        noteRedisFailure(err, decoded.userId);
      }
    }

    // C13b: /me/recover is the one authenticated route a soft-deleted user
    // must be able to reach during the 30-day cooling-off window — the
    // delete-confirmation email tells the user "log back in to recover"
    // and the recover handler validates ownership before flipping
    // deleted_at back. Every other authenticated path stays closed.
    // Note: soft-delete also sets plan='suspended' so the recover-bypass
    // must short-circuit BOTH gates below, not just the deleted_at one.
    const isRecoverEndpoint =
      req.method === 'POST' &&
      (req.path === '/me/recover' ||
        req.path.endsWith('/me/recover') ||
        req.originalUrl?.endsWith('/users/me/recover'));
    const withinGrace =
      !!userRow.deletion_scheduled_for &&
      new Date(userRow.deletion_scheduled_for) > new Date();
    const recoverBypass = userRow.deleted_at && isRecoverEndpoint && withinGrace;

    if (userRow.deleted_at && !recoverBypass) {
      throw new AppError('Account is closed', 401);
    }
    if (userRow.plan === 'suspended' && !recoverBypass) {
      throw new AppError('Account suspended', 403);
    }

    // Audit Ch01-F042: prefer the DB email over the JWT claim — it survives
    // a /me/change-email between token issue and use.
    //
    // 3.17: isPartner now reflects the literal `partners` row only.
    // Admins are no longer auto-elevated to partner; routes that should
    // accept either need to use `requireAdminOrPartner` explicitly.
    // This stops admin tooling from accidentally exercising partner
    // payout / earnings code paths that have no `partners` row backing
    // them.
    const role: 'admin' | 'partner' | 'user' =
      userRow.is_admin ? 'admin' : userRow.is_partner ? 'partner' : 'user';
    req.user = {
      id: userRow.id,
      email: userRow.email,
      plan: userRow.plan,
      role,
      isAdmin: role === 'admin',
      isPartner: userRow.is_partner === true,
      planExpiresAt: userRow.plan_expires_at ? new Date(userRow.plan_expires_at) : null,
      emailVerified: userRow.email_verified ?? false,
    };

    // Thread userId into the AsyncLocalStorage store so every downstream log
    // line carries it without manual plumbing (Phase 3 Ch11-I017).
    const ctx = requestContext.getStore();
    if (ctx) ctx.userId = userRow.id;

    next();
  } catch (error) {
    if (error instanceof jwt.JsonWebTokenError) {
      next(new AppError('Invalid token', 401));
    } else {
      next(error);
    }
  }
}

/**
 * `requireAdmin` re-checks the DB admin flag every call (Ch01-F039: the prior
 * 10s in-memory cache duplicated the Redis user cache). The Redis user cache
 * already has a 10s TTL, so a fresh DB check on each /admin route still gives
 * the operator a 10-second worst-case window to revoke admin via the user
 * cache, while the per-call DB read closes the audit-flagged "stale isAdmin
 * survives admin demotion" hole.
 */
export async function requireAdmin(req: Request, res: Response, next: NextFunction) {
  if (!req.user?.isAdmin) {
    return next(new AppError('Admin access required', 403));
  }

  try {
    const result = await query(
      `SELECT is_admin FROM users WHERE id = $1 AND deleted_at IS NULL`,
      [req.user.id],
    );
    const isAdmin = result.rows.length > 0 && result.rows[0].is_admin === true;
    if (!isAdmin) {
      return next(new AppError('Admin access required', 403));
    }
    next();
  } catch (error) {
    logger.error({ error, userId: req.user.id }, 'Failed to verify admin status from database');
    return next(new AppError('Internal server error', 500));
  }
}

/**
 * Fresh per-call DB check of `users.is_admin` for routes that don't *require*
 * admin but BRANCH on it (e.g. /audit/logs lets admins query any user, others
 * see only their own). The cached `req.user.isAdmin` lives for up to 10s
 * (Redis user-row TTL). Reading directly from the DB closes the
 * "demoted admin retains cross-tenant access for ≤10s" oracle (S-C1).
 *
 * Returns false (and never throws) on lookup failure, so routes that branch
 * on admin-ness fail-closed to "treat as non-admin".
 */
export async function verifyAdminFresh(userId: string): Promise<boolean> {
  try {
    const result = await query(
      `SELECT is_admin FROM users WHERE id = $1 AND deleted_at IS NULL`,
      [userId],
    );
    return result.rows.length > 0 && result.rows[0].is_admin === true;
  } catch (err) {
    logger.error({ err, userId }, 'verifyAdminFresh DB lookup failed; treating as non-admin');
    return false;
  }
}

/// 3.17: explicit "either admin or actual partner" gate. After 3.17,
/// `isPartner` is true ONLY when the user has a row in `partners` —
/// admins are no longer transparently elevated. Routes that legitimately
/// accept either (admin tooling that operates on partner-owned data)
/// must use this middleware rather than `requirePartner`.
export function requireAdminOrPartner(req: Request, res: Response, next: NextFunction) {
  if (!req.user?.isAdmin && !req.user?.isPartner) {
    return next(new AppError('Admin or partner access required', 403));
  }
  next();
}

export function requirePremium(req: Request, res: Response, next: NextFunction) {
  if (req.user?.plan !== 'premium') {
    return next(new AppError('Premium plan required', 403));
  }

  // 1.11: `plan_expires_at IS NULL` on a premium row is a non-expiring
  // entitlement (RevenueCat lifetime purchases / admin-granted lifetime).
  // The /me/verify-premium handler in users.ts mints exactly this shape,
  // so the middleware must accept it instead of treating NULL as expired.
  if (req.user.planExpiresAt === null || req.user.planExpiresAt === undefined) {
    return next();
  }

  const expiresAtUtc = new Date(req.user.planExpiresAt).getTime();
  const nowUtc = Date.now();
  const PREMIUM_GRACE_PERIOD_MS = 24 * 60 * 60 * 1000;
  if (expiresAtUtc + PREMIUM_GRACE_PERIOD_MS < nowUtc) {
    return next(new AppError('Premium plan has expired', 403));
  }

  next();
}
