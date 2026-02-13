"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const validate_1 = require("../middleware/validate");
const partners_service_1 = require("../services/partners.service");
const partners_validator_1 = require("../validators/partners.validator");
const async_handler_1 = require("../utils/async-handler");
const rateLimiter_1 = require("../middleware/rateLimiter");
const audit_service_1 = require("../services/audit.service");
const router = (0, express_1.Router)();
// ========== PUBLIC ROUTES (no authentication required) ==========
/**
 * @route   GET /api/v1/partners/gifts/:id/public
 * @desc    Get public gift details (for preview before activation)
 * @access  Public
 */
router.get('/gifts/:id/public', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const gift = await partners_service_1.PartnersService.getPublicGiftDetails(req.params.id);
    res.json({
        success: true,
        data: gift,
    });
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
    res.json({
        success: true,
        data: result,
    });
}));
// ========== PROTECTED ROUTES (authentication required) ==========
router.use(auth_1.authenticate);
/**
 * @route   POST /api/v1/partners/referral-code
 * @desc    Generate or fetch partner referral code
 * @access  Private (Partner only)
 */
router.post('/referral-code', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const referralCode = await partners_service_1.PartnersService.getOrCreateReferralCode(userId);
    res.json({
        success: true,
        data: { referral_code: referralCode },
    });
}));
/**
 * @route   POST /api/v1/partners/register
 * @desc    Register as a partner (realtor/builder)
 * @access  Private
 */
router.post('/register', (0, validate_1.validate)(partners_validator_1.registerPartnerSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const partner = await partners_service_1.PartnersService.registerPartner(userId, req.body);
    res.status(201).json({
        success: true,
        data: partner,
        message: 'Partner registration successful',
    });
}));
/**
 * @route   GET /api/v1/partners/me
 * @desc    Get partner profile
 * @access  Private
 */
router.get('/me', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const partner = await partners_service_1.PartnersService.getPartner(userId);
    res.json({
        success: true,
        data: partner,
    });
}));
/**
 * @route   PUT /api/v1/partners/me
 * @desc    Update partner profile
 * @access  Private
 */
router.put('/me', (0, validate_1.validate)(partners_validator_1.updatePartnerSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const partner = await partners_service_1.PartnersService.updatePartner(userId, req.body);
    res.json({
        success: true,
        data: partner,
        message: 'Partner profile updated',
    });
}));
/**
 * @route   POST /api/v1/partners/gifts
 * @desc    Create a closing gift for homebuyer
 * @access  Private (Partner only)
 */
router.post('/gifts', (0, validate_1.validate)(partners_validator_1.createGiftSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
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
    res.status(201).json({
        success: true,
        data: gift,
        message: 'Gift created successfully. Homebuyer will receive an email.',
    });
}));
/**
 * @route   GET /api/v1/partners/gifts
 * @desc    Get partner's gifts
 * @access  Private (Partner only)
 */
router.get('/gifts', (0, validate_1.validate)(partners_validator_1.getGiftsQuerySchema, 'query'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const { limit, offset, status } = req.query;
    const result = await partners_service_1.PartnersService.getPartnerGifts(userId, {
        limit: Number(limit),
        offset: Number(offset),
        status: status,
    });
    res.json({
        success: true,
        data: result.gifts,
        pagination: {
            total: result.total,
            limit: Number(limit),
            offset: Number(offset),
            has_more: result.total > Number(offset) + result.gifts.length,
        },
    });
}));
/**
 * @route   GET /api/v1/partners/gifts/:id
 * @desc    Get gift details
 * @access  Private (Partner only)
 */
router.get('/gifts/:id', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const gift = await partners_service_1.PartnersService.getGift(req.params.id, userId);
    res.json({
        success: true,
        data: gift,
    });
}));
/**
 * @route   POST /api/v1/partners/gifts/:id/resend
 * @desc    Resend gift activation email
 * @access  Private (Partner only)
 */
router.post('/gifts/:id/resend', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    await partners_service_1.PartnersService.resendGiftEmail(req.params.id, userId);
    await audit_service_1.AuditService.logFromRequest(req, 'partner.gift_update', {
        resourceType: 'partner_gift',
        resourceId: req.params.id,
        description: 'Resent gift activation email',
    });
    res.json({
        success: true,
        message: 'Gift email resent successfully',
    });
}));
/**
 * @route   GET /api/v1/partners/analytics
 * @desc    Get partner analytics
 * @access  Private (Partner only)
 */
router.get('/analytics', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const analytics = await partners_service_1.PartnersService.getPartnerAnalytics(userId);
    res.json({
        success: true,
        data: analytics,
    });
}));
/**
 * @route   GET /api/v1/partners/commissions
 * @desc    Get partner commissions
 * @access  Private (Partner only)
 */
router.get('/commissions', (0, validate_1.validate)(partners_validator_1.getCommissionsQuerySchema, 'query'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const { limit, offset } = req.query;
    const result = await partners_service_1.PartnersService.getCommissions(userId, {
        limit: Number(limit),
        offset: Number(offset),
    });
    res.json({
        success: true,
        data: result.commissions,
        pagination: {
            total: result.total,
            limit: Number(limit),
            offset: Number(offset),
            has_more: result.total > Number(offset) + result.commissions.length,
        },
    });
}));
/**
 * @route   POST /api/v1/partners/gifts/:id/activate
 * @desc    Activate gift (called when homebuyer signs up via gift link)
 * @access  Private (requires authentication)
 */
router.post('/gifts/:id/activate', (0, async_handler_1.asyncHandler)(async (req, res) => {
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
    res.json({
        success: true,
        data: gift,
        message: `Premium activated! You have ${gift.premium_months} months of HavenKeep Premium.`,
    });
}));
exports.default = router;
//# sourceMappingURL=partners.js.map