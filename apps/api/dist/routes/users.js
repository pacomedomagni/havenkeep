"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const bcryptjs_1 = __importDefault(require("bcryptjs"));
const db_1 = require("../db");
const auth_1 = require("../middleware/auth");
const errorHandler_1 = require("../middleware/errorHandler");
const validate_1 = require("../middleware/validate");
const validators_1 = require("../validators");
const users_validator_1 = require("../validators/users.validator");
const token_blacklist_1 = require("../utils/token-blacklist");
const config_1 = require("../config");
const logger_1 = require("../utils/logger");
const audit_service_1 = require("../services/audit.service");
const router = (0, express_1.Router)();
router.use(auth_1.authenticate);
// Get current user profile
router.get('/me', async (req, res, next) => {
    try {
        const result = await (0, db_1.query)(`SELECT id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
              referred_by, referral_code, created_at, updated_at
       FROM users WHERE id = $1`, [req.user.id]);
        if (result.rows.length === 0) {
            throw new errorHandler_1.AppError('User not found', 404);
        }
        await audit_service_1.AuditService.logFromRequest(req, 'user.update', {
            resourceType: 'user',
            resourceId: result.rows[0].id,
            description: 'Updated user profile',
            metadata: {
                updated_fields: Object.keys(req.body || {}),
            },
        });
        res.json({ user: result.rows[0] });
    }
    catch (error) {
        next(error);
    }
});
// Update user profile
router.put('/me', (0, validate_1.validate)(validators_1.updateUserSchema), async (req, res, next) => {
    try {
        const { fullName, avatarUrl } = req.body;
        const updates = [];
        const values = [];
        let paramIndex = 1;
        if (fullName !== undefined) {
            updates.push(`full_name = $${paramIndex++}`);
            values.push(fullName);
        }
        if (avatarUrl !== undefined) {
            updates.push(`avatar_url = $${paramIndex++}`);
            values.push(avatarUrl);
        }
        if (updates.length === 0) {
            throw new errorHandler_1.AppError('No fields to update', 400);
        }
        values.push(req.user.id);
        const result = await (0, db_1.query)(`UPDATE users SET
        ${updates.join(', ')},
        updated_at = NOW()
       WHERE id = $${paramIndex}
       RETURNING id, email, full_name, avatar_url, plan`, values);
        if (result.rows.length === 0) {
            throw new errorHandler_1.AppError('User not found', 404);
        }
        res.json({ user: result.rows[0] });
    }
    catch (error) {
        next(error);
    }
});
// Register push notification token
router.post('/push-token', (0, validate_1.validate)(validators_1.pushTokenSchema), async (req, res, next) => {
    try {
        const { fcmToken, platform } = req.body;
        await (0, db_1.query)(`INSERT INTO user_push_tokens (user_id, fcm_token, platform, updated_at)
       VALUES ($1, $2, $3, NOW())
       ON CONFLICT (user_id, fcm_token)
       DO UPDATE SET platform = $3, updated_at = NOW()`, [req.user.id, fcmToken, platform || 'unknown']);
        res.json({ message: 'Push token registered' });
    }
    catch (error) {
        next(error);
    }
});
// Verify premium subscription via RevenueCat
router.post('/me/verify-premium', async (req, res, next) => {
    try {
        const { revenueCatAppUserId } = req.body;
        if (!revenueCatAppUserId || typeof revenueCatAppUserId !== 'string') {
            throw new errorHandler_1.AppError('revenueCatAppUserId is required', 400);
        }
        const rcApiKey = config_1.config.revenuecat.apiKey;
        if (!rcApiKey) {
            throw new errorHandler_1.AppError('RevenueCat is not configured on this server', 503);
        }
        // Call RevenueCat REST API to get subscriber info
        const rcResponse = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(revenueCatAppUserId)}`, {
            method: 'GET',
            headers: {
                'Authorization': `Bearer ${rcApiKey}`,
                'Content-Type': 'application/json',
            },
        });
        if (!rcResponse.ok) {
            const errorBody = await rcResponse.text();
            logger_1.logger.error({ statusCode: rcResponse.status, body: errorBody }, 'RevenueCat API error');
            throw new errorHandler_1.AppError('Failed to verify subscription with RevenueCat', 502);
        }
        const rcData = await rcResponse.json();
        // Check for active premium entitlement
        const premiumEntitlement = rcData.subscriber?.entitlements?.premium;
        let isPremium = false;
        let expiresAt = null;
        if (premiumEntitlement) {
            const expiresDate = premiumEntitlement.expires_date;
            if (expiresDate === null) {
                // Lifetime / non-expiring entitlement
                isPremium = true;
            }
            else {
                isPremium = new Date(expiresDate) > new Date();
                expiresAt = expiresDate;
            }
        }
        // Update user plan in the database
        const prevPlanResult = await (0, db_1.query)(`SELECT plan FROM users WHERE id = $1`, [req.user.id]);
        const previousPlan = prevPlanResult.rows[0]?.plan;
        const newPlan = isPremium ? 'premium' : 'free';
        const result = await (0, db_1.query)(`UPDATE users SET
        plan = $1,
        plan_expires_at = $2,
        updated_at = NOW()
       WHERE id = $3
       RETURNING id, email, plan, plan_expires_at`, [newPlan, expiresAt, req.user.id]);
        if (result.rows.length === 0) {
            throw new errorHandler_1.AppError('User not found', 404);
        }
        if (previousPlan && previousPlan !== newPlan) {
            const action = newPlan === 'premium' ? 'user.plan_upgrade' : 'user.plan_downgrade';
            await audit_service_1.AuditService.logFromRequest(req, action, {
                resourceType: 'user',
                resourceId: result.rows[0].id,
                description: newPlan === 'premium'
                    ? 'Upgraded to premium'
                    : 'Downgraded to free',
                metadata: {
                    previous_plan: previousPlan,
                    new_plan: newPlan,
                    expires_at: expiresAt,
                },
            });
        }
        logger_1.logger.info({ userId: req.user.id, plan: newPlan, expiresAt }, 'Premium verification completed');
        res.json({
            success: true,
            data: {
                plan: result.rows[0].plan,
                planExpiresAt: result.rows[0].plan_expires_at,
                verified: true,
            },
        });
    }
    catch (error) {
        next(error);
    }
});
// Change password
router.put('/me/password', (0, validate_1.validate)(users_validator_1.changePasswordSchema), async (req, res, next) => {
    try {
        const { currentPassword, newPassword } = req.body;
        // Get current password hash
        const userResult = await (0, db_1.query)(`SELECT password_hash FROM users WHERE id = $1`, [req.user.id]);
        if (userResult.rows.length === 0) {
            throw new errorHandler_1.AppError('User not found', 404);
        }
        if (!userResult.rows[0].password_hash) {
            throw new errorHandler_1.AppError('Password is not set for this account', 400);
        }
        // Verify current password
        const valid = await bcryptjs_1.default.compare(currentPassword, userResult.rows[0].password_hash);
        if (!valid) {
            throw new errorHandler_1.AppError('Current password is incorrect', 401);
        }
        // Hash and update new password
        const newHash = await bcryptjs_1.default.hash(newPassword, 12);
        await (0, db_1.query)(`UPDATE users SET password_hash = $1 WHERE id = $2`, [newHash, req.user.id]);
        // Blacklist the current access token so it can't be reused
        const authHeader = req.headers.authorization;
        if (authHeader?.startsWith('Bearer ')) {
            const accessToken = authHeader.substring(7);
            await (0, token_blacklist_1.blacklistToken)(accessToken, 3600);
        }
        // Invalidate all refresh tokens (force re-login on other devices)
        await (0, db_1.query)(`DELETE FROM refresh_tokens WHERE user_id = $1`, [req.user.id]);
        res.json({ message: 'Password changed successfully' });
    }
    catch (error) {
        next(error);
    }
});
// Delete account
router.delete('/me', (0, validate_1.validate)(users_validator_1.deleteAccountSchema), async (req, res, next) => {
    try {
        const { password } = req.body;
        // Verify password before deletion
        const userResult = await (0, db_1.query)(`SELECT password_hash FROM users WHERE id = $1`, [req.user.id]);
        if (userResult.rows.length === 0) {
            throw new errorHandler_1.AppError('User not found', 404);
        }
        if (!userResult.rows[0].password_hash) {
            throw new errorHandler_1.AppError('Cannot verify password for SSO accounts', 400);
        }
        const valid = await bcryptjs_1.default.compare(password, userResult.rows[0].password_hash);
        if (!valid) {
            throw new errorHandler_1.AppError('Invalid password', 401);
        }
        // Delete user (cascades to all related data)
        await (0, db_1.query)(`DELETE FROM users WHERE id = $1`, [req.user.id]);
        await audit_service_1.AuditService.logFromRequest(req, 'user.delete', {
            resourceType: 'user',
            resourceId: req.user.id,
            description: 'User deleted account',
        });
        res.json({ message: 'Account deleted successfully' });
    }
    catch (error) {
        next(error);
    }
});
exports.default = router;
//# sourceMappingURL=users.js.map