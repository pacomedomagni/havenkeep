"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.authenticate = authenticate;
exports.requireAdmin = requireAdmin;
exports.requirePremium = requirePremium;
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const config_1 = require("../config");
const errors_1 = require("../utils/errors");
const db_1 = require("../db");
const token_blacklist_1 = require("../utils/token-blacklist");
const logger_1 = require("../utils/logger");
const redis_1 = require("../utils/redis");
// In-memory cache for admin verification with 10-second TTL
const adminCache = new Map();
const ADMIN_CACHE_TTL_MS = 10_000; // 10 seconds
function getCachedAdminStatus(userId) {
    const entry = adminCache.get(userId);
    if (!entry)
        return null;
    if (Date.now() > entry.expiresAt) {
        adminCache.delete(userId);
        return null;
    }
    return entry.isAdmin;
}
function setCachedAdminStatus(userId, isAdmin) {
    adminCache.set(userId, { isAdmin, expiresAt: Date.now() + ADMIN_CACHE_TTL_MS });
}
async function authenticate(req, res, next) {
    try {
        const authHeader = req.headers.authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            throw new errors_1.AppError('No token provided', 401);
        }
        const token = authHeader.substring(7);
        // Check if token has been revoked
        if (await (0, token_blacklist_1.isTokenBlacklisted)(token)) {
            throw new errors_1.AppError('Token has been revoked', 401);
        }
        const decoded = jsonwebtoken_1.default.verify(token, config_1.config.jwt.secret);
        // Get user from database (cached in Redis with 10s TTL to reduce DB load)
        const userCacheKey = `user:${decoded.userId}`;
        let userRow = null;
        // Check Redis cache first
        try {
            const redis = await (0, redis_1.getRedisClient)();
            const cached = await redis.get(userCacheKey);
            if (cached) {
                userRow = JSON.parse(cached);
            }
        }
        catch (err) {
            logger_1.logger.warn({ err, userId: decoded.userId }, 'Redis cache read failed for user, falling back to DB');
        }
        // On cache miss, query the database and populate cache
        if (!userRow) {
            const result = await (0, db_1.query)(`SELECT u.id, u.email, u.plan, u.is_admin, u.plan_expires_at, u.email_verified,
                (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = u.id AND p.is_active = TRUE)) as is_partner
         FROM users u WHERE u.id = $1`, [decoded.userId]);
            if (result.rows.length === 0) {
                throw new errors_1.AppError('Invalid token', 401);
            }
            userRow = result.rows[0];
            // Cache the user row in Redis with a 10-second TTL
            try {
                const redis = await (0, redis_1.getRedisClient)();
                await redis.set(userCacheKey, JSON.stringify(userRow), { EX: 10 });
            }
            catch (err) {
                logger_1.logger.warn({ err, userId: decoded.userId }, 'Redis cache write failed for user');
            }
        }
        // BE-8: Reject requests from suspended users immediately.
        // When a user is suspended, their plan is set to 'suspended' and their
        // refresh tokens are deleted, but an existing access token may still be valid
        // until it expires. This check ensures suspended users cannot use the API
        // even with a valid access token.
        if (userRow.plan === 'suspended') {
            throw new errors_1.AppError('Account suspended', 403);
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
    }
    catch (error) {
        if (error instanceof jsonwebtoken_1.default.JsonWebTokenError) {
            next(new errors_1.AppError('Invalid token', 401));
        }
        else {
            next(error);
        }
    }
}
async function requireAdmin(req, res, next) {
    if (!req.user?.isAdmin) {
        return next(new errors_1.AppError('Admin access required', 403));
    }
    // Verify admin status against the database (with 30s in-memory cache)
    // to prevent stale JWT claims from granting admin access after revocation.
    const userId = req.user.id;
    const cached = getCachedAdminStatus(userId);
    if (cached !== null) {
        if (!cached) {
            return next(new errors_1.AppError('Admin access required', 403));
        }
        return next();
    }
    try {
        const result = await (0, db_1.query)('SELECT is_admin FROM users WHERE id = $1', [userId]);
        const isAdmin = result.rows.length > 0 && result.rows[0].is_admin === true;
        setCachedAdminStatus(userId, isAdmin);
        if (!isAdmin) {
            return next(new errors_1.AppError('Admin access required', 403));
        }
        next();
    }
    catch (error) {
        logger_1.logger.error({ error, userId }, 'Failed to verify admin status from database');
        return next(new errors_1.AppError('Internal server error', 500));
    }
}
function requirePremium(req, res, next) {
    if (req.user?.plan !== 'premium') {
        return next(new errors_1.AppError('Premium plan required', 403));
    }
    // If plan_expires_at is set, verify it hasn't expired (null means lifetime).
    // Both sides are compared in UTC to avoid timezone drift issues.
    if (req.user.planExpiresAt) {
        const expiresAtUtc = new Date(req.user.planExpiresAt).getTime();
        const nowUtc = Date.now();
        const PREMIUM_GRACE_PERIOD_MS = 24 * 60 * 60 * 1000; // 24 hours
        if (expiresAtUtc + PREMIUM_GRACE_PERIOD_MS < nowUtc) {
            return next(new errors_1.AppError('Premium plan has expired', 403));
        }
    }
    next();
}
//# sourceMappingURL=auth.js.map