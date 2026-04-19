"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const stripe_1 = __importDefault(require("stripe"));
const db_1 = require("../db");
const config_1 = require("../config");
const auth_1 = require("../middleware/auth");
const validate_1 = require("../middleware/validate");
const partners_service_1 = require("../services/partners.service");
const partners_validator_1 = require("../validators/partners.validator");
const validators_1 = require("../validators");
const async_handler_1 = require("../utils/async-handler");
const rateLimiter_1 = require("../middleware/rateLimiter");
const audit_service_1 = require("../services/audit.service");
const errors_1 = require("../utils/errors");
const response_1 = require("../utils/response");
const stripe = new stripe_1.default(config_1.config.stripe.secretKey, {
    apiVersion: '2023-10-16',
});
function requirePartner(req, res, next) {
    if (!req.user?.isPartner) {
        return next(new errors_1.AppError('Partner access required', 403));
    }
    next();
}
const router = (0, express_1.Router)();
// ========== PUBLIC ROUTES (no authentication required) ==========
/**
 * @route   GET /api/v1/partners/gifts/:id/public
 * @desc    Get public gift details (for preview before activation)
 * @access  Public
 */
router.get('/gifts/:id/public', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const gift = await partners_service_1.PartnersService.getPublicGiftDetails(req.params.id);
    (0, response_1.sendSuccess)(res, gift);
}));
/**
 * @route   POST /api/v1/partners/gifts/verify-code
 * @desc    Verify activation code and get gift ID
 * @access  Public
 */
router.post('/gifts/verify-code', rateLimiter_1.activationCodeRateLimiter, (0, async_handler_1.asyncHandler)(async (req, res) => {
    const { activation_code } = req.body;
    if (!activation_code || typeof activation_code !== 'string') {
        return res.status(400).json({
            success: false,
            message: 'Activation code is required',
        });
    }
    // Validate activation code format (alphanumeric, reasonable length)
    if (activation_code.length < 6 || activation_code.length > 64 || !/^[A-Za-z0-9_-]+$/.test(activation_code)) {
        return res.status(400).json({
            success: false,
            message: 'Invalid activation code format',
        });
    }
    const result = await partners_service_1.PartnersService.verifyActivationCode(activation_code);
    (0, response_1.sendSuccess)(res, result);
}));
/**
 * @route   GET /api/v1/partners/gifts/:id/track/email-open
 * @desc    Track email open (called via 1x1 tracking pixel in gift email)
 * @access  Public
 */
router.get('/gifts/:id/track/email-open', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const result = await db_1.pool.query(`UPDATE partner_gifts
       SET email_opened_at = COALESCE(email_opened_at, NOW())
       WHERE id = $1
       RETURNING id`, [req.params.id]);
    if (result.rows.length === 0) {
        res.status(404).end();
        return;
    }
    // Return a 1x1 transparent GIF
    const pixel = Buffer.from('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7', 'base64');
    res.setHeader('Content-Type', 'image/gif');
    res.setHeader('Cache-Control', 'no-store');
    res.end(pixel);
}));
/**
 * @route   POST /api/v1/partners/gifts/:id/track/app-download
 * @desc    Track when homebuyer downloads the app (called on first app launch)
 * @access  Public
 */
router.post('/gifts/:id/track/app-download', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const result = await db_1.pool.query(`UPDATE partner_gifts
       SET app_download_at = COALESCE(app_download_at, NOW())
       WHERE id = $1
       RETURNING id`, [req.params.id]);
    if (result.rows.length === 0) {
        throw new errors_1.AppError('Gift not found', 404);
    }
    (0, response_1.sendMessage)(res, 'App download tracked');
}));
// ========== PROTECTED ROUTES (authentication required) ==========
router.use(auth_1.authenticate);
/**
 * @route   POST /api/v1/partners/referral-code
 * @desc    Generate or fetch partner referral code
 * @access  Private (Partner only)
 */
router.post('/referral-code', requirePartner, (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const referralCode = await partners_service_1.PartnersService.getOrCreateReferralCode(userId);
    (0, response_1.sendSuccess)(res, { referral_code: referralCode });
}));
/**
 * @route   GET /api/v1/partners/referrals
 * @desc    Get users who signed up using this partner's referral code
 * @access  Private (Partner only)
 */
router.get('/referrals', requirePartner, (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(50, Math.max(1, parseInt(req.query.limit, 10) || 20));
    const { referrals, total } = await partners_service_1.PartnersService.getReferrals(userId, { page, limit });
    (0, response_1.sendSuccess)(res, referrals, {
        pagination: {
            page,
            limit,
            total,
            total_pages: Math.ceil(total / limit),
        },
    });
}));
/**
 * @route   POST /api/v1/partners/register
 * @desc    Register as a partner (realtor/builder)
 * @access  Private
 */
router.post('/register', rateLimiter_1.writeRateLimiter, (0, validate_1.validate)(partners_validator_1.registerPartnerSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const partner = await partners_service_1.PartnersService.registerPartner(userId, req.body);
    (0, response_1.sendSuccess)(res, partner, { status: 201, message: 'Partner registration successful' });
}));
/**
 * @route   GET /api/v1/partners/me
 * @desc    Get partner profile
 * @access  Private
 */
router.get('/me', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const partner = await partners_service_1.PartnersService.getPartner(userId);
    (0, response_1.sendSuccess)(res, partner);
}));
/**
 * @route   PUT /api/v1/partners/me
 * @desc    Update partner profile
 * @access  Private
 */
router.put('/me', rateLimiter_1.writeRateLimiter, (0, validate_1.validate)(partners_validator_1.updatePartnerSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const partner = await partners_service_1.PartnersService.updatePartner(userId, req.body);
    (0, response_1.sendSuccess)(res, partner, { message: 'Partner profile updated' });
}));
/**
 * @route   POST /api/v1/partners/gifts
 * @desc    Create a closing gift for homebuyer
 * @access  Private (Partner only)
 */
router.post('/gifts', requirePartner, (0, validate_1.validate)(partners_validator_1.createGiftSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const gift = await partners_service_1.PartnersService.createGift(userId, req.body);
    await audit_service_1.AuditService.logFromRequest(req, 'partner.gift_create', {
        resourceType: 'partner_gift',
        resourceId: gift.id,
        description: `Created gift for ${gift.homebuyer_email}`,
        metadata: {
            premium_months: gift.premium_months,
            amount_charged: gift.amount_charged,
        },
    });
    (0, response_1.sendSuccess)(res, gift, { status: 201, message: 'Gift created successfully. Homebuyer will receive an email.' });
}));
/**
 * @route   GET /api/v1/partners/gifts
 * @desc    Get partner's gifts
 * @access  Private (Partner only)
 */
router.get('/gifts', requirePartner, (0, validate_1.validate)(partners_validator_1.getGiftsQuerySchema, 'query'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const { status } = req.query;
    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 50));
    const offset = (page - 1) * limit;
    const result = await partners_service_1.PartnersService.getPartnerGifts(userId, {
        limit,
        offset,
        status: status,
    });
    (0, response_1.sendSuccess)(res, result.gifts, {
        pagination: {
            page,
            limit,
            total: result.total,
            total_pages: Math.ceil(result.total / limit),
        },
    });
}));
/**
 * @route   GET /api/v1/partners/gifts/:id
 * @desc    Get gift details
 * @access  Private (Partner only)
 */
router.get('/gifts/:id', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), requirePartner, (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const gift = await partners_service_1.PartnersService.getGift(req.params.id, userId);
    (0, response_1.sendSuccess)(res, gift);
}));
/**
 * @route   POST /api/v1/partners/gifts/:id/resend
 * @desc    Resend gift activation email
 * @access  Private (Partner only)
 */
router.post('/gifts/:id/resend', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), rateLimiter_1.giftResendRateLimiter, requirePartner, (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    await partners_service_1.PartnersService.resendGiftEmail(req.params.id, userId);
    await audit_service_1.AuditService.logFromRequest(req, 'partner.gift_update', {
        resourceType: 'partner_gift',
        resourceId: req.params.id,
        description: 'Resent gift activation email',
    });
    (0, response_1.sendMessage)(res, 'Gift email resent successfully');
}));
/**
 * @route   GET /api/v1/partners/analytics
 * @desc    Get partner analytics with optional date range filtering
 * @access  Private (Partner only)
 */
router.get('/analytics', requirePartner, (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const startDate = req.query.startDate;
    const endDate = req.query.endDate;
    // Validate date format if provided (YYYY-MM-DD)
    const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
    if (startDate && !dateRegex.test(startDate)) {
        throw new errors_1.AppError('Invalid startDate format. Use YYYY-MM-DD.', 400);
    }
    if (endDate && !dateRegex.test(endDate)) {
        throw new errors_1.AppError('Invalid endDate format. Use YYYY-MM-DD.', 400);
    }
    const analytics = await partners_service_1.PartnersService.getPartnerAnalytics(userId, { startDate, endDate });
    (0, response_1.sendSuccess)(res, analytics);
}));
/**
 * @route   GET /api/v1/partners/earnings-history
 * @desc    Get monthly earnings over the last 12 months
 * @access  Private (Partner only)
 */
router.get('/earnings-history', requirePartner, (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    // Look up partner ID from user ID
    const partnerResult = await db_1.pool.query('SELECT id FROM partners WHERE user_id = $1', [userId]);
    if (partnerResult.rows.length === 0) {
        throw new errors_1.AppError('Partner not found', 404);
    }
    const earningsHistory = await partners_service_1.PartnersService.getEarningsHistory(partnerResult.rows[0].id);
    (0, response_1.sendSuccess)(res, earningsHistory);
}));
/**
 * @route   GET /api/v1/partners/commissions
 * @desc    Get partner commissions
 * @access  Private (Partner only)
 */
router.get('/commissions', requirePartner, (0, validate_1.validate)(partners_validator_1.getCommissionsQuerySchema, 'query'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 50));
    const offset = (page - 1) * limit;
    const result = await partners_service_1.PartnersService.getCommissions(userId, {
        limit,
        offset,
    });
    (0, response_1.sendSuccess)(res, result.commissions, {
        pagination: {
            page,
            limit,
            total: result.total,
            total_pages: Math.ceil(result.total / limit),
        },
    });
}));
/**
 * @route   POST /api/v1/partners/gifts/:id/track/first-item
 * @desc    Track when homebuyer adds their first item (called by items service)
 * @access  Private (authenticated user)
 */
router.post('/gifts/:id/track/first-item', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const result = await db_1.pool.query(`UPDATE partner_gifts
       SET first_item_added_at = COALESCE(first_item_added_at, NOW())
       WHERE id = $1 AND activated_user_id = $2
       RETURNING id`, [req.params.id, req.user.id]);
    if (result.rows.length === 0) {
        throw new errors_1.AppError('Gift not found', 404);
    }
    (0, response_1.sendMessage)(res, 'First item tracked');
}));
/**
 * @route   POST /api/v1/partners/gifts/:id/activate
 * @desc    Activate gift (called when homebuyer signs up via gift link)
 * @access  Private (requires authentication)
 */
router.post('/gifts/:id/activate', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const userEmail = req.user.email;
    const gift = await partners_service_1.PartnersService.activateGift(req.params.id, userId, userEmail);
    await audit_service_1.AuditService.logFromRequest(req, 'partner.gift_activate', {
        resourceType: 'partner_gift',
        resourceId: gift.id,
        description: 'Activated gift',
        metadata: {
            premium_months: gift.premium_months,
        },
    });
    (0, response_1.sendSuccess)(res, gift, { message: `Premium activated! You have ${gift.premium_months} months of HavenKeep Premium.` });
}));
// ========== PARTNER TIERS ==========
const PARTNER_TIERS = [
    {
        id: 'basic',
        name: 'Basic',
        price_monthly: 0,
        max_gifts_per_month: 10,
        commission_rate: 0.10,
        features: ['10 gifts/month', '10% commission'],
    },
    {
        id: 'premium',
        name: 'Premium',
        price_monthly: 49,
        max_gifts_per_month: 50,
        commission_rate: 0.15,
        features: ['50 gifts/month', '15% commission', 'Priority support'],
    },
    {
        id: 'platinum',
        name: 'Platinum',
        price_monthly: 149,
        max_gifts_per_month: -1,
        commission_rate: 0.20,
        features: ['Unlimited gifts', '20% commission', 'Dedicated account manager', 'Custom branding'],
    },
];
/**
 * @route   GET /api/v1/partners/tiers
 * @desc    Get available partner tiers
 * @access  Public
 */
router.get('/tiers', (0, async_handler_1.asyncHandler)(async (_req, res) => {
    (0, response_1.sendSuccess)(res, PARTNER_TIERS);
}));
// ========== STRIPE CONNECT ==========
/**
 * @route   POST /api/v1/partners/stripe-connect/onboard
 * @desc    Create a Stripe Connect Express account and return onboarding URL
 * @access  Private (Partner only)
 */
router.post('/stripe-connect/onboard', requirePartner, (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const partner = await partners_service_1.PartnersService.getPartner(userId);
    let stripeAccountId = partner.stripe_account_id;
    // Create a new Stripe Connect Express account if the partner doesn't have one yet
    if (!stripeAccountId) {
        const account = await stripe.accounts.create({
            type: 'express',
            email: partner.email,
            metadata: { partner_id: partner.id },
        });
        stripeAccountId = account.id;
        // Store the stripe_account_id on the partner record
        await db_1.pool.query(`UPDATE partners SET stripe_account_id = $1, updated_at = NOW() WHERE id = $2`, [stripeAccountId, partner.id]);
    }
    // Create an onboarding link
    const accountLink = await stripe.accountLinks.create({
        account: stripeAccountId,
        refresh_url: `${config_1.config.app.dashboardUrl}/dashboard/settings?stripe=refresh`,
        return_url: `${config_1.config.app.dashboardUrl}/dashboard/settings?stripe=success`,
        type: 'account_onboarding',
    });
    (0, response_1.sendSuccess)(res, { url: accountLink.url });
}));
/**
 * @route   GET /api/v1/partners/stripe-connect/status
 * @desc    Check Stripe Connect account status
 * @access  Private (Partner only)
 */
router.get('/stripe-connect/status', requirePartner, (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const partner = await partners_service_1.PartnersService.getPartner(userId);
    if (!partner.stripe_account_id) {
        return (0, response_1.sendSuccess)(res, {
            connected: false,
            charges_enabled: false,
            payouts_enabled: false,
            onboarded: false,
        });
    }
    // Retrieve the account details from Stripe
    const account = await stripe.accounts.retrieve(partner.stripe_account_id);
    const chargesEnabled = account.charges_enabled ?? false;
    const payoutsEnabled = account.payouts_enabled ?? false;
    // If both capabilities are enabled and partner isn't marked as onboarded yet, update DB
    if (chargesEnabled && payoutsEnabled && !partner.stripe_onboarded) {
        await db_1.pool.query(`UPDATE partners SET stripe_onboarded = TRUE, updated_at = NOW() WHERE id = $1`, [partner.id]);
    }
    (0, response_1.sendSuccess)(res, {
        connected: true,
        charges_enabled: chargesEnabled,
        payouts_enabled: payoutsEnabled,
        onboarded: (chargesEnabled && payoutsEnabled) || partner.stripe_onboarded,
    });
}));
// ========== ADMIN ROUTES (admin access required) ==========
/**
 * @route   PUT /api/v1/partners/admin/commissions/:id/approve
 * @desc    Approve a pending commission
 * @access  Private (Admin only)
 */
router.put('/admin/commissions/:id/approve', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), auth_1.requireAdmin, (0, async_handler_1.asyncHandler)(async (req, res) => {
    const { id } = req.params;
    const current = await db_1.pool.query(`SELECT id, status FROM partner_commissions WHERE id = $1`, [id]);
    if (current.rows.length === 0) {
        throw new errors_1.AppError('Commission not found', 404);
    }
    if (current.rows[0].status !== 'pending') {
        throw new errors_1.AppError(`Cannot approve commission with status '${current.rows[0].status}'. Only 'pending' commissions can be approved.`, 400);
    }
    const result = await db_1.pool.query(`UPDATE partner_commissions
       SET status = 'approved', updated_at = NOW()
       WHERE id = $1
       RETURNING *`, [id]);
    (0, response_1.sendSuccess)(res, result.rows[0], { message: 'Commission approved' });
}));
/**
 * @route   PUT /api/v1/partners/admin/commissions/:id/pay
 * @desc    Mark an approved commission as paid
 * @access  Private (Admin only)
 */
router.put('/admin/commissions/:id/pay', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), auth_1.requireAdmin, (0, async_handler_1.asyncHandler)(async (req, res) => {
    const { id } = req.params;
    const current = await db_1.pool.query(`SELECT id, status FROM partner_commissions WHERE id = $1`, [id]);
    if (current.rows.length === 0) {
        throw new errors_1.AppError('Commission not found', 404);
    }
    if (current.rows[0].status !== 'approved') {
        throw new errors_1.AppError(`Cannot pay commission with status '${current.rows[0].status}'. Only 'approved' commissions can be paid.`, 400);
    }
    const result = await db_1.pool.query(`UPDATE partner_commissions
       SET status = 'paid', paid_at = NOW(), updated_at = NOW()
       WHERE id = $1
       RETURNING *`, [id]);
    (0, response_1.sendSuccess)(res, result.rows[0], { message: 'Commission marked as paid' });
}));
/**
 * @route   PUT /api/v1/partners/admin/commissions/:id/cancel
 * @desc    Cancel a pending commission
 * @access  Private (Admin only)
 */
router.put('/admin/commissions/:id/cancel', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), auth_1.requireAdmin, (0, async_handler_1.asyncHandler)(async (req, res) => {
    const { id } = req.params;
    const current = await db_1.pool.query(`SELECT id, status FROM partner_commissions WHERE id = $1`, [id]);
    if (current.rows.length === 0) {
        throw new errors_1.AppError('Commission not found', 404);
    }
    if (current.rows[0].status !== 'pending') {
        throw new errors_1.AppError(`Cannot cancel commission with status '${current.rows[0].status}'. Only 'pending' commissions can be cancelled.`, 400);
    }
    const result = await db_1.pool.query(`UPDATE partner_commissions
       SET status = 'cancelled', updated_at = NOW()
       WHERE id = $1
       RETURNING *`, [id]);
    (0, response_1.sendSuccess)(res, result.rows[0], { message: 'Commission cancelled' });
}));
exports.default = router;
//# sourceMappingURL=partners.js.map