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

    const decoded = jwt.verify(token, config.jwt.secret) as {
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
      const result = await query(
        `SELECT u.id, u.email, u.plan, u.is_admin, u.plan_expires_at, u.email_verified,
                u.deleted_at,
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

    if (userRow.deleted_at) {
      throw new AppError('Account is closed', 401);
    }
    if (userRow.plan === 'suspended') {
      throw new AppError('Account suspended', 403);
    }

    // Audit Ch01-F042: prefer the DB email over the JWT claim — it survives
    // a /me/change-email between token issue and use.
    const role: 'admin' | 'partner' | 'user' =
      userRow.is_admin ? 'admin' : userRow.is_partner ? 'partner' : 'user';
    req.user = {
      id: userRow.id,
      email: userRow.email,
      plan: userRow.plan,
      role,
      isAdmin: role === 'admin',
      isPartner: role === 'partner' || role === 'admin',
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

export function requirePremium(req: Request, res: Response, next: NextFunction) {
  if (req.user?.plan !== 'premium') {
    return next(new AppError('Premium plan required', 403));
  }

  // Default-deny: a premium row with no expiry is a data bug (every paid
  // path should set plan_expires_at). Treat it as expired rather than
  // grant indefinite premium — the user only loses access for one
  // request, while the underlying bug surfaces in logs and can be fixed.
  if (!req.user.planExpiresAt) {
    logger.warn(
      { userId: req.user.id },
      'requirePremium: user has plan=premium but plan_expires_at is NULL — treating as expired',
    );
    return next(new AppError('Premium plan has expired', 403));
  }

  const expiresAtUtc = new Date(req.user.planExpiresAt).getTime();
  const nowUtc = Date.now();
  const PREMIUM_GRACE_PERIOD_MS = 24 * 60 * 60 * 1000;
  if (expiresAtUtc + PREMIUM_GRACE_PERIOD_MS < nowUtc) {
    return next(new AppError('Premium plan has expired', 403));
  }

  next();
}
