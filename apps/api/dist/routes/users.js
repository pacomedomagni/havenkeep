"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const crypto_1 = __importDefault(require("crypto"));
const bcryptjs_1 = __importDefault(require("bcryptjs"));
const db_1 = require("../db");
const auth_1 = require("../middleware/auth");
const errors_1 = require("../utils/errors");
const validate_1 = require("../middleware/validate");
const validators_1 = require("../validators");
const users_validator_1 = require("../validators/users.validator");
const auth_validator_1 = require("../validators/auth.validator");
const token_blacklist_1 = require("../utils/token-blacklist");
const config_1 = require("../config");
const logger_1 = require("../utils/logger");
const audit_service_1 = require("../services/audit.service");
const email_service_1 = require("../services/email.service");
const rateLimiter_1 = require("../middleware/rateLimiter");
const async_handler_1 = require("../utils/async-handler");
const response_1 = require("../utils/response");
const router = (0, express_1.Router)();
router.use(auth_1.authenticate);
// Get current user profile
router.get('/me', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const result = await (0, db_1.query)(`SELECT id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
            referred_by, referral_code, email_verified, apple_user_id, is_admin, created_at, updated_at,
            (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = users.id AND p.is_active = TRUE)) as is_partner
     FROM users WHERE id = $1`, [req.user.id]);
    if (result.rows.length === 0) {
        throw new errors_1.AppError('User not found', 404);
    }
    (0, response_1.sendSuccess)(res, result.rows[0]);
}));
// Update user profile
router.put('/me', rateLimiter_1.writeRateLimiter, (0, validate_1.validate)(validators_1.updateUserSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
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
        throw new errors_1.AppError('No fields to update', 400);
    }
    values.push(req.user.id);
    const result = await (0, db_1.query)(`UPDATE users SET
      ${updates.join(', ')},
      updated_at = NOW()
     WHERE id = $${paramIndex}
     RETURNING id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
               referred_by, referral_code, email_verified, apple_user_id, is_admin, created_at, updated_at,
               (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = users.id AND p.is_active = TRUE)) as is_partner`, values);
    if (result.rows.length === 0) {
        throw new errors_1.AppError('User not found', 404);
    }
    (0, response_1.sendSuccess)(res, result.rows[0]);
}));
// Register push notification token
router.post('/push-token', rateLimiter_1.writeRateLimiter, (0, validate_1.validate)(validators_1.pushTokenSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const { fcmToken, platform } = req.body;
    await (0, db_1.query)(`INSERT INTO user_push_tokens (user_id, fcm_token, platform, updated_at)
     VALUES ($1, $2, $3, NOW())
     ON CONFLICT (user_id, fcm_token)
     DO UPDATE SET platform = $3, updated_at = NOW()`, [req.user.id, fcmToken, platform || 'unknown']);
    (0, response_1.sendMessage)(res, 'Push token registered');
}));
// Verify premium subscription via RevenueCat
// BE-12: Rate limited to prevent abuse of RevenueCat API calls
router.post('/me/verify-premium', rateLimiter_1.verifyPremiumRateLimiter, (0, async_handler_1.asyncHandler)(async (req, res) => {
    const { revenueCatAppUserId } = req.body;
    if (!revenueCatAppUserId || typeof revenueCatAppUserId !== 'string') {
        throw new errors_1.AppError('revenueCatAppUserId is required', 400);
    }
    const rcApiKey = config_1.config.revenuecat.apiKey;
    if (!rcApiKey) {
        throw new errors_1.AppError('RevenueCat is not configured on this server', 503);
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
        throw new errors_1.AppError('Failed to verify subscription with RevenueCat', 502);
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
        throw new errors_1.AppError('User not found', 404);
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
}));
// Change email — initiates verification flow
router.post('/me/change-email', rateLimiter_1.writeRateLimiter, (0, validate_1.validate)(auth_validator_1.changeEmailSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const { newEmail, password } = req.body;
    // Get current user
    const userResult = await (0, db_1.query)(`SELECT email, password_hash, full_name FROM users WHERE id = $1`, [req.user.id]);
    if (userResult.rows.length === 0) {
        throw new errors_1.AppError('User not found', 404);
    }
    const user = userResult.rows[0];
    if (!user.password_hash) {
        throw new errors_1.AppError('Password is not set for this account. OAuth users cannot change email this way.', 400);
    }
    // Verify current password
    const valid = await bcryptjs_1.default.compare(password, user.password_hash);
    if (!valid) {
        throw new errors_1.AppError('Incorrect password', 401);
    }
    // Ensure new email is different from current
    if (newEmail.toLowerCase() === user.email.toLowerCase()) {
        throw new errors_1.AppError('New email must be different from your current email', 400);
    }
    // Check if new email is already in use
    const existingUser = await (0, db_1.query)(`SELECT id FROM users WHERE LOWER(email) = LOWER($1)`, [newEmail]);
    if (existingUser.rows.length > 0) {
        throw new errors_1.AppError('This email is already in use', 409);
    }
    // Generate a verification token
    const token = crypto_1.default.randomBytes(32).toString('hex');
    const hashedToken = crypto_1.default.createHash('sha256').update(token).digest('hex');
    // Delete any existing change-email tokens for this user
    await (0, db_1.query)(`DELETE FROM email_verification_tokens WHERE user_id = $1 AND metadata->>'type' = 'change_email'`, [req.user.id]);
    // Store the hashed token with new_email metadata
    await (0, db_1.query)(`INSERT INTO email_verification_tokens (user_id, token, metadata, expires_at)
     VALUES ($1, $2, $3, NOW() + INTERVAL '24 hours')`, [
        req.user.id,
        hashedToken,
        JSON.stringify({ type: 'change_email', new_email: newEmail }),
    ]);
    // Build verification URL
    const verifyUrl = `${config_1.config.app.frontendUrl}/verify-email-change?token=${token}`;
    // Send verification email to the NEW address
    await email_service_1.EmailService.sendEmailChangeVerificationEmail({
        to: newEmail,
        user_name: user.full_name || 'there',
        verify_url: verifyUrl,
        new_email: newEmail,
    });
    // Audit log
    await audit_service_1.AuditService.logFromRequest(req, 'user.email_change_requested', {
        resourceType: 'user',
        resourceId: req.user.id,
        description: 'Email change verification sent',
        metadata: { new_email: newEmail },
    });
    logger_1.logger.info({ userId: req.user.id, newEmail }, 'Email change verification sent');
    (0, response_1.sendMessage)(res, 'Verification email sent to your new address. Please check your inbox.');
}));
// Change password
router.put('/me/password', rateLimiter_1.passwordChangeRateLimiter, (0, validate_1.validate)(users_validator_1.changePasswordSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const { currentPassword, newPassword } = req.body;
    // Get current password hash
    const userResult = await (0, db_1.query)(`SELECT password_hash FROM users WHERE id = $1`, [req.user.id]);
    if (userResult.rows.length === 0) {
        throw new errors_1.AppError('User not found', 404);
    }
    if (!userResult.rows[0].password_hash) {
        throw new errors_1.AppError('Password is not set for this account', 400);
    }
    // Verify current password
    const valid = await bcryptjs_1.default.compare(currentPassword, userResult.rows[0].password_hash);
    if (!valid) {
        throw new errors_1.AppError('Current password is incorrect', 401);
    }
    // Prevent setting the same password
    const samePassword = await bcryptjs_1.default.compare(newPassword, userResult.rows[0].password_hash);
    if (samePassword) {
        throw new errors_1.AppError('New password must be different from current password', 400);
    }
    // Hash and update new password
    const newHash = await bcryptjs_1.default.hash(newPassword, 12);
    await (0, db_1.query)(`UPDATE users SET password_hash = $1 WHERE id = $2`, [newHash, req.user.id]);
    // Blacklist the current access token using its actual remaining TTL
    const authHeader = req.headers.authorization;
    if (authHeader?.startsWith('Bearer ')) {
        const accessToken = authHeader.substring(7);
        await (0, token_blacklist_1.blacklistTokenAuto)(accessToken);
    }
    // Invalidate all refresh tokens (force re-login on other devices)
    await (0, db_1.query)(`DELETE FROM refresh_tokens WHERE user_id = $1`, [req.user.id]);
    // Audit log: password changed
    await audit_service_1.AuditService.logFromRequest(req, 'user.update', {
        resourceType: 'user',
        resourceId: req.user.id,
        description: 'Password changed',
    });
    (0, response_1.sendMessage)(res, 'Password changed successfully');
}));
// Delete account (soft-delete with 30-day cooling-off period)
// For email users: requires password confirmation.
// For OAuth users (no password): requires confirmDelete=true in body.
router.delete('/me', (0, validate_1.validate)(users_validator_1.deleteAccountSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const { password, confirmDelete } = req.body || {};
    // Get user info to determine auth method
    const userResult = await (0, db_1.query)(`SELECT password_hash, auth_provider, email, full_name FROM users WHERE id = $1`, [req.user.id]);
    if (userResult.rows.length === 0) {
        throw new errors_1.AppError('User not found', 404);
    }
    const user = userResult.rows[0];
    if (user.password_hash) {
        // Email user: require password confirmation
        if (!password) {
            throw new errors_1.AppError('Password is required to delete your account', 400);
        }
        const valid = await bcryptjs_1.default.compare(password, user.password_hash);
        if (!valid) {
            throw new errors_1.AppError('Invalid password', 401);
        }
    }
    else {
        // OAuth user: require explicit confirmation flag
        if (confirmDelete !== true) {
            throw new errors_1.AppError('Please confirm account deletion by setting confirmDelete to true', 400);
        }
    }
    // Atomic soft-delete + token invalidation
    const client = await (0, db_1.getClient)();
    try {
        await client.query('BEGIN');
        await client.query(`UPDATE users
       SET deleted_at = NOW(),
           deletion_scheduled_for = NOW() + INTERVAL '30 days',
           plan = 'suspended',
           updated_at = NOW()
       WHERE id = $1`, [req.user.id]);
        // Invalidate all refresh tokens to log the user out everywhere
        await client.query(`DELETE FROM refresh_tokens WHERE user_id = $1`, [req.user.id]);
        await client.query('COMMIT');
    }
    catch (txError) {
        await client.query('ROLLBACK');
        throw txError;
    }
    finally {
        client.release();
    }
    // Blacklist the current access token
    const authHeader = req.headers.authorization;
    if (authHeader?.startsWith('Bearer ')) {
        try {
            await (0, token_blacklist_1.blacklistTokenAuto)(authHeader.substring(7));
        }
        catch {
            // Best-effort
        }
    }
    // Fire-and-forget: send account deletion confirmation email
    email_service_1.EmailService.sendAccountDeletionEmail({
        to: user.email,
        user_name: user.full_name || 'there',
    }).catch((err) => {
        logger_1.logger.warn({ error: err, userId: req.user.id }, 'Failed to send account deletion email (non-blocking)');
    });
    await audit_service_1.AuditService.logFromRequest(req, 'user.delete', {
        resourceType: 'user',
        resourceId: req.user.id,
        description: 'User scheduled account for deletion (30-day cooling-off)',
    });
    (0, response_1.sendMessage)(res, 'Account scheduled for deletion in 30 days. You can recover it by logging in before then.');
}));
// Recover a soft-deleted account during the cooling-off period
router.post('/me/recover', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userResult = await (0, db_1.query)(`SELECT id, deleted_at, deletion_scheduled_for FROM users WHERE id = $1`, [req.user.id]);
    if (userResult.rows.length === 0) {
        throw new errors_1.AppError('User not found', 404);
    }
    const user = userResult.rows[0];
    if (!user.deleted_at) {
        throw new errors_1.AppError('Account is not scheduled for deletion', 400);
    }
    // Clear soft-delete markers and restore to free plan
    await (0, db_1.query)(`UPDATE users
     SET deleted_at = NULL,
         deletion_scheduled_for = NULL,
         plan = 'free',
         updated_at = NOW()
     WHERE id = $1`, [req.user.id]);
    await audit_service_1.AuditService.logFromRequest(req, 'user.update', {
        resourceType: 'user',
        resourceId: req.user.id,
        description: 'User recovered account from scheduled deletion',
    });
    (0, response_1.sendMessage)(res, 'Account recovered successfully. Your plan has been set to free.');
}));
exports.default = router;
//# sourceMappingURL=users.js.map