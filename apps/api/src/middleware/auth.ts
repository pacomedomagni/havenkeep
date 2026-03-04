import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { config } from '../config';
import { AppError } from '../utils/errors';
import { query } from '../db';
import { isTokenBlacklisted } from '../utils/token-blacklist';
import { logger } from '../utils/logger';
import { getRedisClient } from '../utils/redis';

export type AuthRequest = Request;

// In-memory cache for admin verification with 10-second TTL
const adminCache = new Map<string, { isAdmin: boolean; expiresAt: number }>();
const ADMIN_CACHE_TTL_MS = 10_000; // 10 seconds

function getCachedAdminStatus(userId: string): boolean | null {
  const entry = adminCache.get(userId);
  if (!entry) return null;
  if (Date.now() > entry.expiresAt) {
    adminCache.delete(userId);
    return null;
  }
  return entry.isAdmin;
}

function setCachedAdminStatus(userId: string, isAdmin: boolean): void {
  adminCache.set(userId, { isAdmin, expiresAt: Date.now() + ADMIN_CACHE_TTL_MS });
}

export async function authenticate(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new AppError('No token provided', 401);
    }

    const token = authHeader.substring(7);

    // Check if token has been revoked
    if (await isTokenBlacklisted(token)) {
      throw new AppError('Token has been revoked', 401);
    }

    const decoded = jwt.verify(token, config.jwt.secret) as {
      userId: string;
      email: string;
    };

    // Get user from database (cached in Redis with 10s TTL to reduce DB load)
    const userCacheKey = `user:${decoded.userId}`;
    let userRow: any = null;

    // Check Redis cache first
    try {
      const redis = await getRedisClient();
      const cached = await redis.get(userCacheKey);
      if (cached) {
        userRow = JSON.parse(cached);
      }
    } catch (err) {
      logger.warn({ err, userId: decoded.userId }, 'Redis cache read failed for user, falling back to DB');
    }

    // On cache miss, query the database and populate cache
    if (!userRow) {
      const result = await query(
        `SELECT u.id, u.email, u.plan, u.is_admin, u.plan_expires_at, u.email_verified,
                (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = u.id AND p.is_active = TRUE)) as is_partner
         FROM users u WHERE u.id = $1`,
        [decoded.userId]
      );

      if (result.rows.length === 0) {
        throw new AppError('Invalid token', 401);
      }

      userRow = result.rows[0];

      // Cache the user row in Redis with a 10-second TTL
      try {
        const redis = await getRedisClient();
        await redis.set(userCacheKey, JSON.stringify(userRow), { EX: 10 });
      } catch (err) {
        logger.warn({ err, userId: decoded.userId }, 'Redis cache write failed for user');
      }
    }

    // BE-8: Reject requests from suspended users immediately.
    // When a user is suspended, their plan is set to 'suspended' and their
    // refresh tokens are deleted, but an existing access token may still be valid
    // until it expires. This check ensures suspended users cannot use the API
    // even with a valid access token.
    if (userRow.plan === 'suspended') {
      throw new AppError('Account suspended', 403);
    }

    req.user = {
      id: userRow.id,
      email: userRow.email,
      plan: userRow.plan,
      isAdmin: userRow.is_admin,
      isPartner: userRow.is_partner,
      planExpiresAt: userRow.plan_expires_at ?? null,
      emailVerified: userRow.email_verified ?? false,
    };

    next();
  } catch (error) {
    if (error instanceof jwt.JsonWebTokenError) {
      next(new AppError('Invalid token', 401));
    } else {
      next(error);
    }
  }
}

export async function requireAdmin(req: Request, res: Response, next: NextFunction) {
  if (!req.user?.isAdmin) {
    return next(new AppError('Admin access required', 403));
  }

  // Verify admin status against the database (with 30s in-memory cache)
  // to prevent stale JWT claims from granting admin access after revocation.
  const userId = req.user.id;
  const cached = getCachedAdminStatus(userId);

  if (cached !== null) {
    if (!cached) {
      return next(new AppError('Admin access required', 403));
    }
    return next();
  }

  try {
    const result = await query('SELECT is_admin FROM users WHERE id = $1', [userId]);
    const isAdmin = result.rows.length > 0 && result.rows[0].is_admin === true;
    setCachedAdminStatus(userId, isAdmin);

    if (!isAdmin) {
      return next(new AppError('Admin access required', 403));
    }
    next();
  } catch (error) {
    logger.error({ error, userId }, 'Failed to verify admin status from database');
    return next(new AppError('Internal server error', 500));
  }
}

export function requirePremium(req: Request, res: Response, next: NextFunction) {
  if (req.user?.plan !== 'premium') {
    return next(new AppError('Premium plan required', 403));
  }

  // If plan_expires_at is set, verify it hasn't expired (null means lifetime).
  // Both sides are compared in UTC to avoid timezone drift issues.
  if (req.user.planExpiresAt) {
    const expiresAtUtc = new Date(req.user.planExpiresAt).getTime();
    const nowUtc = Date.now();
    const PREMIUM_GRACE_PERIOD_MS = 24 * 60 * 60 * 1000; // 24 hours
    if (expiresAtUtc + PREMIUM_GRACE_PERIOD_MS < nowUtc) {
      return next(new AppError('Premium plan has expired', 403));
    }
  }

  next();
}
