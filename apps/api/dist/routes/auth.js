"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const bcryptjs_1 = __importDefault(require("bcryptjs"));
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const crypto_1 = __importDefault(require("crypto"));
const db_1 = require("../db");
const config_1 = require("../config");
const errorHandler_1 = require("../middleware/errorHandler");
const rateLimiter_1 = require("../middleware/rateLimiter");
const validate_1 = require("../middleware/validate");
const validators_1 = require("../validators");
const auth_validator_1 = require("../validators/auth.validator");
const logger_1 = require("../utils/logger");
const audit_service_1 = require("../services/audit.service");
const email_service_1 = require("../services/email.service");
const token_blacklist_1 = require("../utils/token-blacklist");
const referral_code_1 = require("../utils/referral-code");
const router = (0, express_1.Router)();
// Helper to get IP address
const getIpAddress = (req) => {
    const ip = req.headers['x-forwarded-for']?.split(',')[0]?.trim() ||
        req.headers['x-real-ip'] ||
        req.socket.remoteAddress;
    if (!ip) {
        logger_1.logger.warn({ path: req.path }, 'Could not determine client IP address');
        return 'unknown';
    }
    return ip;
};
async function resolveReferredBy(referralCode) {
    if (!referralCode)
        return null;
    const result = await (0, db_1.query)(`SELECT id FROM users WHERE referral_code = $1`, [referralCode]);
    return result.rows.length > 0 ? result.rows[0].id : null;
}
// Register
router.post('/register', rateLimiter_1.authRateLimiter, (0, validate_1.validate)(validators_1.registerSchema), async (req, res, next) => {
    try {
        const { email, password, fullName, referralCode } = req.body;
        // Check if user exists
        const existing = await (0, db_1.query)('SELECT id FROM users WHERE email = $1', [email.toLowerCase()]);
        if (existing.rows.length > 0) {
            throw new errorHandler_1.AppError('Email already registered', 409);
        }
        // Hash password with bcrypt rounds=12
        const passwordHash = await bcryptjs_1.default.hash(password, 12);
        const referredBy = await resolveReferredBy(referralCode);
        const userReferralCode = await (0, referral_code_1.generateUniqueReferralCode)();
        // Create user
        const result = await (0, db_1.query)(`INSERT INTO users (email, password_hash, full_name, referral_code, referred_by)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
                 referred_by, referral_code, is_admin, created_at, updated_at`, [email.toLowerCase(), passwordHash, fullName, userReferralCode, referredBy]);
        const user = result.rows[0];
        // Create default home
        await (0, db_1.query)(`INSERT INTO homes (user_id, name) VALUES ($1, $2)`, [user.id, 'My Home']);
        // Audit log: successful registration
        await audit_service_1.AuditService.logAuth({
            action: 'auth.register',
            userId: user.id,
            email: user.email,
            ipAddress: getIpAddress(req),
            userAgent: req.get('user-agent'),
            success: true,
        });
        // Generate tokens
        const accessToken = jsonwebtoken_1.default.sign({ userId: user.id, email: user.email }, config_1.config.jwt.secret, { expiresIn: config_1.config.jwt.expiresIn });
        const refreshToken = jsonwebtoken_1.default.sign({ userId: user.id }, config_1.config.jwt.refreshSecret, { expiresIn: config_1.config.jwt.refreshExpiresIn });
        // Store refresh token
        const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
        await (0, db_1.query)(`INSERT INTO refresh_tokens (user_id, token, expires_at)
       VALUES ($1, $2, $3)`, [user.id, refreshToken, expiresAt]);
        res.status(201).json({
            user: {
                id: user.id,
                email: user.email,
                full_name: user.full_name,
                avatar_url: user.avatar_url || null,
                auth_provider: user.auth_provider || 'email',
                plan: user.plan,
                plan_expires_at: user.plan_expires_at || null,
                referred_by: user.referred_by || null,
                referral_code: user.referral_code || null,
                is_admin: user.is_admin || false,
                is_partner: false,
                created_at: user.created_at,
                updated_at: user.updated_at,
            },
            accessToken,
            refreshToken,
        });
    }
    catch (error) {
        // Audit log: failed registration
        await audit_service_1.AuditService.logAuth({
            action: 'auth.register',
            email: req.body.email,
            ipAddress: getIpAddress(req),
            userAgent: req.get('user-agent'),
            success: false,
            errorMessage: error instanceof Error ? error.message : 'Registration failed',
        });
        next(error);
    }
});
// Login
router.post('/login', rateLimiter_1.authRateLimiter, (0, validate_1.validate)(validators_1.loginSchema), async (req, res, next) => {
    try {
        const { email, password } = req.body;
        // Get user
        const result = await (0, db_1.query)(`SELECT u.id, u.email, u.password_hash, u.full_name, u.avatar_url, u.auth_provider, u.plan,
              u.plan_expires_at, u.referred_by, u.referral_code, u.is_admin, u.created_at, u.updated_at,
              (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = u.id AND p.is_active = TRUE)) as is_partner
       FROM users u WHERE u.email = $1`, [email.toLowerCase()]);
        if (result.rows.length === 0) {
            throw new errorHandler_1.AppError('Invalid credentials', 401);
        }
        const user = result.rows[0];
        // Verify password
        if (!user.password_hash) {
            throw new errorHandler_1.AppError('Invalid credentials', 401);
        }
        const valid = await bcryptjs_1.default.compare(password, user.password_hash);
        if (!valid) {
            // Audit log: failed login (wrong password)
            await audit_service_1.AuditService.logAuth({
                action: 'auth.login',
                userId: user.id,
                email: user.email,
                ipAddress: getIpAddress(req),
                userAgent: req.get('user-agent'),
                success: false,
                errorMessage: 'Invalid password',
            });
            throw new errorHandler_1.AppError('Invalid credentials', 401);
        }
        // Generate tokens
        const accessToken = jsonwebtoken_1.default.sign({ userId: user.id, email: user.email }, config_1.config.jwt.secret, { expiresIn: config_1.config.jwt.expiresIn });
        const refreshToken = jsonwebtoken_1.default.sign({ userId: user.id }, config_1.config.jwt.refreshSecret, { expiresIn: config_1.config.jwt.refreshExpiresIn });
        // Store refresh token
        const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
        await (0, db_1.query)(`INSERT INTO refresh_tokens (user_id, token, expires_at)
       VALUES ($1, $2, $3)`, [user.id, refreshToken, expiresAt]);
        // Audit log: successful login
        await audit_service_1.AuditService.logAuth({
            action: 'auth.login',
            userId: user.id,
            email: user.email,
            ipAddress: getIpAddress(req),
            userAgent: req.get('user-agent'),
            success: true,
        });
        res.json({
            user: {
                id: user.id,
                email: user.email,
                full_name: user.full_name,
                avatar_url: user.avatar_url || null,
                auth_provider: user.auth_provider || 'email',
                plan: user.plan,
                plan_expires_at: user.plan_expires_at || null,
                referred_by: user.referred_by || null,
                referral_code: user.referral_code || null,
                is_admin: user.is_admin,
                is_partner: user.is_partner,
                created_at: user.created_at,
                updated_at: user.updated_at,
            },
            accessToken,
            refreshToken,
        });
    }
    catch (error) {
        // Audit log: failed login (user not found or other error)
        if (error instanceof errorHandler_1.AppError && error.statusCode === 401) {
            await audit_service_1.AuditService.logAuth({
                action: 'auth.login',
                email: req.body.email,
                ipAddress: getIpAddress(req),
                userAgent: req.get('user-agent'),
                success: false,
                errorMessage: 'Invalid credentials',
            });
        }
        next(error);
    }
});
// Refresh token
router.post('/refresh', rateLimiter_1.refreshRateLimiter, (0, validate_1.validate)(validators_1.refreshTokenSchema), async (req, res, next) => {
    try {
        const { refreshToken } = req.body;
        // Verify refresh token
        const decoded = jsonwebtoken_1.default.verify(refreshToken, config_1.config.jwt.refreshSecret);
        // Check if token exists and not expired
        const tokenResult = await (0, db_1.query)(`SELECT user_id FROM refresh_tokens
       WHERE token = $1 AND expires_at > NOW()`, [refreshToken]);
        if (tokenResult.rows.length === 0) {
            throw new errorHandler_1.AppError('Invalid refresh token', 401);
        }
        // Get user
        const userResult = await (0, db_1.query)(`SELECT id, email FROM users WHERE id = $1`, [decoded.userId]);
        if (userResult.rows.length === 0) {
            throw new errorHandler_1.AppError('User not found', 401);
        }
        const user = userResult.rows[0];
        // Blacklist the old access token so it can't be reused after refresh
        const authHeader = req.headers.authorization;
        if (authHeader?.startsWith('Bearer ')) {
            const oldAccessToken = authHeader.substring(7);
            try {
                const decoded = jsonwebtoken_1.default.decode(oldAccessToken);
                if (decoded?.exp) {
                    const remainingSeconds = decoded.exp - Math.floor(Date.now() / 1000);
                    if (remainingSeconds > 0) {
                        await (0, token_blacklist_1.blacklistToken)(oldAccessToken, remainingSeconds);
                    }
                }
            }
            catch {
                // Best-effort: don't block refresh if blacklisting fails
            }
        }
        // Generate new access token
        const accessToken = jsonwebtoken_1.default.sign({ userId: user.id, email: user.email }, config_1.config.jwt.secret, { expiresIn: config_1.config.jwt.expiresIn });
        res.json({ accessToken });
    }
    catch (error) {
        next(error);
    }
});
// Logout
router.post('/logout', rateLimiter_1.refreshRateLimiter, (0, validate_1.validate)(validators_1.refreshTokenSchema), async (req, res, next) => {
    try {
        const { refreshToken } = req.body;
        let userId;
        // Blacklist the current access token so it can't be reused
        const authHeader = req.headers.authorization;
        if (authHeader?.startsWith('Bearer ')) {
            const accessToken = authHeader.substring(7);
            try {
                await (0, token_blacklist_1.blacklistToken)(accessToken, 3600);
            }
            catch (blacklistError) {
                // Best-effort: don't block logout if Redis/blacklist fails
                logger_1.logger.warn({ error: blacklistError }, 'Failed to blacklist access token during logout');
            }
        }
        if (refreshToken) {
            // Get user ID from refresh token before deleting
            const tokenResult = await (0, db_1.query)(`SELECT user_id FROM refresh_tokens WHERE token = $1`, [refreshToken]);
            if (tokenResult.rows.length > 0) {
                userId = tokenResult.rows[0].user_id;
            }
            await (0, db_1.query)(`DELETE FROM refresh_tokens WHERE token = $1`, [refreshToken]);
            // Invalidate any unused password reset tokens for this user
            if (userId) {
                await (0, db_1.query)(`UPDATE password_reset_tokens SET used = TRUE WHERE user_id = $1 AND used = FALSE`, [userId]);
            }
        }
        // Audit log: logout
        if (userId) {
            await audit_service_1.AuditService.logAuth({
                action: 'auth.logout',
                userId,
                ipAddress: getIpAddress(req),
                userAgent: req.get('user-agent'),
                success: true,
            });
        }
        res.json({ message: 'Logged out successfully' });
    }
    catch (error) {
        next(error);
    }
});
// Forgot password - request reset
router.post('/forgot-password', rateLimiter_1.passwordResetRateLimiter, (0, validate_1.validate)(auth_validator_1.forgotPasswordSchema), async (req, res, next) => {
    try {
        const { email } = req.body;
        const result = await (0, db_1.query)(`SELECT id, email, full_name FROM users WHERE email = $1`, [email.toLowerCase()]);
        // Always return success to prevent email enumeration
        if (result.rows.length === 0) {
            res.json({ message: 'If an account exists with that email, a reset link has been sent.' });
            return;
        }
        const user = result.rows[0];
        // Invalidate any existing reset tokens
        await (0, db_1.query)(`UPDATE password_reset_tokens SET used = TRUE WHERE user_id = $1 AND used = FALSE`, [user.id]);
        // Generate reset token
        const resetToken = crypto_1.default.randomBytes(32).toString('hex');
        const expiresAt = new Date();
        expiresAt.setHours(expiresAt.getHours() + 1); // 1 hour expiry
        await (0, db_1.query)(`INSERT INTO password_reset_tokens (user_id, token, expires_at)
       VALUES ($1, $2, $3)`, [user.id, resetToken, expiresAt]);
        // Send password reset email
        const resetUrl = `${config_1.config.app.frontendUrl}/reset-password?token=${resetToken}`;
        logger_1.logger.info({ userId: user.id, resetUrl }, 'Password reset requested');
        // Fire-and-forget: don't block the HTTP response on email delivery
        email_service_1.EmailService.sendPasswordResetEmail({
            to: user.email,
            user_name: user.full_name || 'there',
            reset_url: resetUrl,
        }).catch((emailError) => {
            logger_1.logger.error({ error: emailError, userId: user.id }, 'Failed to send password reset email');
        });
        // Audit log: password reset requested
        await audit_service_1.AuditService.logAuth({
            action: 'auth.password_reset_request',
            userId: user.id,
            email: user.email,
            ipAddress: getIpAddress(req),
            userAgent: req.get('user-agent'),
            success: true,
        });
        res.json({ message: 'If an account exists with that email, a reset link has been sent.' });
    }
    catch (error) {
        next(error);
    }
});
// Reset password with token
router.post('/reset-password', rateLimiter_1.authRateLimiter, (0, validate_1.validate)(auth_validator_1.resetPasswordSchema), async (req, res, next) => {
    try {
        const { token, newPassword } = req.body;
        // Atomically find and mark the reset token as used in a single query
        // to prevent race conditions with concurrent reset requests
        const tokenResult = await (0, db_1.query)(`UPDATE password_reset_tokens
       SET used = TRUE
       WHERE token = $1 AND expires_at > NOW() AND used = FALSE
       RETURNING user_id`, [token]);
        if (tokenResult.rows.length === 0) {
            throw new errorHandler_1.AppError('Invalid or expired reset token', 400);
        }
        const userId = tokenResult.rows[0].user_id;
        // Hash new password
        const passwordHash = await bcryptjs_1.default.hash(newPassword, 12);
        // Update password
        await (0, db_1.query)(`UPDATE users SET password_hash = $1 WHERE id = $2`, [passwordHash, userId]);
        // Invalidate all refresh tokens
        await (0, db_1.query)(`DELETE FROM refresh_tokens WHERE user_id = $1`, [userId]);
        // Audit log: password reset completed
        await audit_service_1.AuditService.logAuth({
            action: 'auth.password_reset_complete',
            userId,
            ipAddress: getIpAddress(req),
            userAgent: req.get('user-agent'),
            success: true,
        });
        res.json({ message: 'Password has been reset successfully' });
    }
    catch (error) {
        next(error);
    }
});
// Verify email
router.post('/verify-email', (0, validate_1.validate)(auth_validator_1.verifyEmailSchema), async (req, res, next) => {
    try {
        const { token } = req.body;
        // Atomically consume the verification token and get user_id
        const tokenResult = await (0, db_1.query)(`DELETE FROM email_verification_tokens
       WHERE token = $1 AND expires_at > NOW()
       RETURNING user_id`, [token]);
        if (tokenResult.rows.length === 0) {
            throw new errorHandler_1.AppError('Invalid or expired verification token', 400);
        }
        const userId = tokenResult.rows[0].user_id;
        // Mark email as verified and clean up any remaining tokens for this user
        await Promise.all([
            (0, db_1.query)(`UPDATE users SET email_verified = TRUE WHERE id = $1`, [userId]),
            (0, db_1.query)(`DELETE FROM email_verification_tokens WHERE user_id = $1`, [userId]),
        ]);
        // Audit log: email verified
        await audit_service_1.AuditService.logAuth({
            action: 'auth.email_verify',
            userId,
            ipAddress: getIpAddress(req),
            userAgent: req.get('user-agent'),
            success: true,
        });
        res.json({ message: 'Email verified successfully' });
    }
    catch (error) {
        next(error);
    }
});
// Google OAuth — accept ID token from mobile, verify, create/find user, return JWT
router.post('/google', rateLimiter_1.authRateLimiter, async (req, res, next) => {
    try {
        if (!config_1.config.google?.clientId) {
            throw new errorHandler_1.AppError('Google OAuth is not configured', 501);
        }
        const { idToken, referralCode } = req.body;
        if (!idToken || typeof idToken !== 'string') {
            throw new errorHandler_1.AppError('Google ID token is required', 400);
        }
        // Verify the Google ID token
        const { OAuth2Client } = await Promise.resolve().then(() => __importStar(require('google-auth-library')));
        const client = new OAuth2Client(config_1.config.google?.clientId);
        const ticket = await client.verifyIdToken({
            idToken,
            audience: config_1.config.google?.clientId,
        });
        const payload = ticket.getPayload();
        if (!payload || !payload.email) {
            throw new errorHandler_1.AppError('Invalid Google token', 401);
        }
        const email = payload.email.toLowerCase();
        const fullName = payload.name || 'User';
        const avatarUrl = payload.picture || null;
        // Find or create user
        let userResult = await (0, db_1.query)(`SELECT id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
              referred_by, referral_code, is_admin, created_at, updated_at,
              (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = users.id AND p.is_active = TRUE)) as is_partner
       FROM users WHERE email = $1`, [email]);
        let user;
        let isNewUser = false;
        if (userResult.rows.length === 0) {
            const referredBy = await resolveReferredBy(referralCode);
            const userReferralCode = await (0, referral_code_1.generateUniqueReferralCode)();
            // Create new user (no password for OAuth users)
            const createResult = await (0, db_1.query)(`INSERT INTO users (email, full_name, avatar_url, auth_provider, email_verified, referral_code, referred_by)
         VALUES ($1, $2, $3, 'google', TRUE, $4, $5)
         RETURNING id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
                   referred_by, referral_code, is_admin, created_at, updated_at`, [email, fullName, avatarUrl, userReferralCode, referredBy]);
            user = createResult.rows[0];
            isNewUser = true;
            // Create default home
            await (0, db_1.query)(`INSERT INTO homes (user_id, name) VALUES ($1, $2)`, [user.id, 'My Home']);
        }
        else {
            user = userResult.rows[0];
        }
        // Generate tokens
        const accessToken = jsonwebtoken_1.default.sign({ userId: user.id, email: user.email }, config_1.config.jwt.secret, { expiresIn: config_1.config.jwt.expiresIn });
        const refreshToken = jsonwebtoken_1.default.sign({ userId: user.id }, config_1.config.jwt.refreshSecret, { expiresIn: config_1.config.jwt.refreshExpiresIn });
        const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
        await (0, db_1.query)(`INSERT INTO refresh_tokens (user_id, token, expires_at)
       VALUES ($1, $2, $3)`, [user.id, refreshToken, expiresAt]);
        // Audit log: OAuth login
        await audit_service_1.AuditService.logAuth({
            action: 'auth.oauth_login',
            userId: user.id,
            email: user.email,
            ipAddress: getIpAddress(req),
            userAgent: req.get('user-agent'),
            success: true,
            metadata: {
                provider: 'google',
                new_user: isNewUser,
            },
        });
        res.json({
            user: {
                id: user.id,
                email: user.email,
                full_name: user.full_name,
                avatar_url: user.avatar_url || null,
                auth_provider: user.auth_provider || 'google',
                plan: user.plan,
                plan_expires_at: user.plan_expires_at || null,
                referred_by: user.referred_by || null,
                referral_code: user.referral_code || null,
                is_admin: user.is_admin,
                is_partner: user.is_partner ?? false,
                created_at: user.created_at,
                updated_at: user.updated_at,
            },
            accessToken,
            refreshToken,
        });
    }
    catch (error) {
        next(error);
    }
});
// Apple OAuth — accept ID token from mobile, verify, create/find user, return JWT
router.post('/apple', rateLimiter_1.authRateLimiter, async (req, res, next) => {
    try {
        if (!config_1.config.apple?.bundleId) {
            throw new errorHandler_1.AppError('Apple Sign-In is not configured', 501);
        }
        const { idToken, fullName: appleFullName, referralCode } = req.body;
        if (!idToken || typeof idToken !== 'string') {
            throw new errorHandler_1.AppError('Apple ID token is required', 400);
        }
        // Verify Apple ID token against Apple's public keys (JWKS)
        const jwksClient = await Promise.resolve().then(() => __importStar(require('jwks-rsa')));
        const appleJwksClient = jwksClient.default({
            jwksUri: 'https://appleid.apple.com/auth/keys',
            cache: true,
            cacheMaxAge: 86400000, // 24 hours
        });
        // Decode header to get the key ID
        const decodedHeader = jsonwebtoken_1.default.decode(idToken, { complete: true });
        if (!decodedHeader || !decodedHeader.header.kid) {
            throw new errorHandler_1.AppError('Invalid Apple token format', 401);
        }
        // Fetch the signing key from Apple's JWKS
        const signingKey = await appleJwksClient.getSigningKey(decodedHeader.header.kid);
        const publicKey = signingKey.getPublicKey();
        // Verify the token signature and claims
        const decoded = jsonwebtoken_1.default.verify(idToken, publicKey, {
            algorithms: ['RS256'],
            issuer: 'https://appleid.apple.com',
        });
        if (!decoded || !decoded.sub) {
            throw new errorHandler_1.AppError('Invalid Apple token', 401);
        }
        const appleUserId = decoded.sub;
        let email = decoded.email?.toLowerCase();
        // Find or create user — first try by email, then by apple_user_id
        let userResult;
        if (email) {
            userResult = await (0, db_1.query)(`SELECT id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
                referred_by, referral_code, is_admin, created_at, updated_at,
                (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = users.id AND p.is_active = TRUE)) as is_partner
         FROM users WHERE email = $1`, [email]);
        }
        // On subsequent sign-ins, Apple may not provide email.
        // Fall back to lookup by apple_user_id stored from first sign-in.
        if ((!email || !userResult || userResult.rows.length === 0)) {
            const appleIdResult = await (0, db_1.query)(`SELECT id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
                referred_by, referral_code, is_admin, created_at, updated_at,
                (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = users.id AND p.is_active = TRUE)) as is_partner
         FROM users WHERE apple_user_id = $1`, [appleUserId]);
            if (appleIdResult.rows.length > 0) {
                userResult = appleIdResult;
                email = appleIdResult.rows[0].email;
            }
        }
        if (!email) {
            throw new errorHandler_1.AppError('Email not provided by Apple. Please grant email permission.', 401);
        }
        if (!userResult) {
            userResult = { rows: [] };
        }
        let user;
        let isNewUser = false;
        if (userResult.rows.length === 0) {
            const fullName = appleFullName || 'User';
            const referredBy = await resolveReferredBy(referralCode);
            const userReferralCode = await (0, referral_code_1.generateUniqueReferralCode)();
            const createResult = await (0, db_1.query)(`INSERT INTO users (email, full_name, auth_provider, email_verified, apple_user_id, referral_code, referred_by)
         VALUES ($1, $2, 'apple', TRUE, $3, $4, $5)
         RETURNING id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
                   referred_by, referral_code, is_admin, created_at, updated_at`, [email, fullName, appleUserId, userReferralCode, referredBy]);
            user = createResult.rows[0];
            isNewUser = true;
            // Create default home
            await (0, db_1.query)(`INSERT INTO homes (user_id, name) VALUES ($1, $2)`, [user.id, 'My Home']);
        }
        else {
            user = userResult.rows[0];
            // Ensure apple_user_id is stored for future lookups
            await (0, db_1.query)(`UPDATE users SET apple_user_id = $1 WHERE id = $2 AND apple_user_id IS NULL`, [appleUserId, user.id]);
        }
        // Generate tokens
        const accessToken = jsonwebtoken_1.default.sign({ userId: user.id, email: user.email }, config_1.config.jwt.secret, { expiresIn: config_1.config.jwt.expiresIn });
        const refreshToken = jsonwebtoken_1.default.sign({ userId: user.id }, config_1.config.jwt.refreshSecret, { expiresIn: config_1.config.jwt.refreshExpiresIn });
        const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
        await (0, db_1.query)(`INSERT INTO refresh_tokens (user_id, token, expires_at)
       VALUES ($1, $2, $3)`, [user.id, refreshToken, expiresAt]);
        // Audit log: OAuth login
        await audit_service_1.AuditService.logAuth({
            action: 'auth.oauth_login',
            userId: user.id,
            email: user.email,
            ipAddress: getIpAddress(req),
            userAgent: req.get('user-agent'),
            success: true,
            metadata: {
                provider: 'apple',
                new_user: isNewUser,
            },
        });
        res.json({
            user: {
                id: user.id,
                email: user.email,
                full_name: user.full_name,
                avatar_url: user.avatar_url || null,
                auth_provider: user.auth_provider || 'apple',
                plan: user.plan,
                plan_expires_at: user.plan_expires_at || null,
                referred_by: user.referred_by || null,
                referral_code: user.referral_code || null,
                is_admin: user.is_admin,
                is_partner: user.is_partner ?? false,
                created_at: user.created_at,
                updated_at: user.updated_at,
            },
            accessToken,
            refreshToken,
        });
    }
    catch (error) {
        next(error);
    }
});
exports.default = router;
//# sourceMappingURL=auth.js.map