import { Router } from 'express';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { PartnersService } from '../services/partners.service';
import {
  registerPartnerSchema,
  updatePartnerSchema,
  createGiftSchema,
  getGiftsQuerySchema,
  getCommissionsQuerySchema,
} from '../validators/partners.validator';
import { asyncHandler } from '../utils/async-handler';
import { activationCodeRateLimiter } from '../middleware/rateLimiter';

const router = Router();

// ========== PUBLIC ROUTES (no authentication required) ==========

/**
 * @route   GET /api/v1/partners/gifts/:id/public
 * @desc    Get public gift details (for preview before activation)
 * @access  Public
 */
router.get(
  '/gifts/:id/public',
  asyncHandler(async (req, res) => {
    const gift = await PartnersService.getPublicGiftDetails(req.params.id);

    res.json({
      success: true,
      data: gift,
    });
  })
);

/**
 * @route   POST /api/v1/partners/gifts/verify-code
 * @desc    Verify activation code and get gift ID
 * @access  Public
 */
router.post(
  '/gifts/verify-code',
  activationCodeRateLimiter,
  asyncHandler(async (req, res) => {
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

    const result = await PartnersService.verifyActivationCode(activation_code);

    res.json({
      success: true,
      data: result,
    });
  })
);

// ========== PROTECTED ROUTES (authentication required) ==========
router.use(authenticate);

/**
 * @route   POST /api/v1/partners/referral-code
 * @desc    Generate or fetch partner referral code
 * @access  Private (Partner only)
 */
router.post(
  '/referral-code',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const referralCode = await PartnersService.getOrCreateReferralCode(userId);

    res.json({
      success: true,
      data: { referral_code: referralCode },
    });
  })
);

/**
 * @route   POST /api/v1/partners/register
 * @desc    Register as a partner (realtor/builder)
 * @access  Private
 */
router.post(
  '/register',
  validate(registerPartnerSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const partner = await PartnersService.registerPartner(userId, req.body);

    res.status(201).json({
      success: true,
      data: partner,
      message: 'Partner registration successful',
    });
  })
);

/**
 * @route   GET /api/v1/partners/me
 * @desc    Get partner profile
 * @access  Private
 */
router.get(
  '/me',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const partner = await PartnersService.getPartner(userId);

    res.json({
      success: true,
      data: partner,
    });
  })
);

/**
 * @route   PUT /api/v1/partners/me
 * @desc    Update partner profile
 * @access  Private
 */
router.put(
  '/me',
  validate(updatePartnerSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const partner = await PartnersService.updatePartner(userId, req.body);

    res.json({
      success: true,
      data: partner,
      message: 'Partner profile updated',
    });
  })
);

/**
 * @route   POST /api/v1/partners/gifts
 * @desc    Create a closing gift for homebuyer
 * @access  Private (Partner only)
 */
router.post(
  '/gifts',
  validate(createGiftSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const gift = await PartnersService.createGift(userId, req.body);

    res.status(201).json({
      success: true,
      data: gift,
      message: 'Gift created successfully. Homebuyer will receive an email.',
    });
  })
);

/**
 * @route   GET /api/v1/partners/gifts
 * @desc    Get partner's gifts
 * @access  Private (Partner only)
 */
router.get(
  '/gifts',
  validate(getGiftsQuerySchema, 'query'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const { limit, offset, status } = req.query;

    const result = await PartnersService.getPartnerGifts(userId, {
      limit: Number(limit),
      offset: Number(offset),
      status: status as string,
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
  })
);

/**
 * @route   GET /api/v1/partners/gifts/:id
 * @desc    Get gift details
 * @access  Private (Partner only)
 */
router.get(
  '/gifts/:id',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const gift = await PartnersService.getGift(req.params.id, userId);

    res.json({
      success: true,
      data: gift,
    });
  })
);

/**
 * @route   POST /api/v1/partners/gifts/:id/resend
 * @desc    Resend gift activation email
 * @access  Private (Partner only)
 */
router.post(
  '/gifts/:id/resend',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    await PartnersService.resendGiftEmail(req.params.id, userId);

    res.json({
      success: true,
      message: 'Gift email resent successfully',
    });
  })
);

/**
 * @route   GET /api/v1/partners/analytics
 * @desc    Get partner analytics
 * @access  Private (Partner only)
 */
router.get(
  '/analytics',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const analytics = await PartnersService.getPartnerAnalytics(userId);

    res.json({
      success: true,
      data: analytics,
    });
  })
);

/**
 * @route   GET /api/v1/partners/commissions
 * @desc    Get partner commissions
 * @access  Private (Partner only)
 */
router.get(
  '/commissions',
  validate(getCommissionsQuerySchema, 'query'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const { limit, offset } = req.query;

    const result = await PartnersService.getCommissions(userId, {
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
  })
);

/**
 * @route   POST /api/v1/partners/gifts/:id/activate
 * @desc    Activate gift (called when homebuyer signs up via gift link)
 * @access  Private (requires authentication)
 */
router.post(
  '/gifts/:id/activate',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const userEmail = req.user!.email;
    const gift = await PartnersService.activateGift(req.params.id, userId, userEmail);

    res.json({
      success: true,
      data: gift,
      message: `Premium activated! You have ${gift.premium_months} months of HavenKeep Premium.`,
    });
  })
);

export default router;
