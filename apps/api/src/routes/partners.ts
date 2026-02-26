import { Router } from 'express';
import Stripe from 'stripe';
import { pool } from '../db';
import { config } from '../config';
import { authenticate, requireAdmin } from '../middleware/auth';
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
import { AuditService } from '../services/audit.service';
import { AppError } from '../middleware/errorHandler';

const stripe = new Stripe(config.stripe.secretKey, {
  apiVersion: '2023-10-16',
});

function requirePartner(req: any, res: any, next: any) {
  if (!req.user?.isPartner) {
    return next(new AppError('Partner access required', 403));
  }
  next();
}

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
  requirePartner,
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
 * @route   GET /api/v1/partners/referrals
 * @desc    Get users who signed up using this partner's referral code
 * @access  Private (Partner only)
 */
router.get(
  '/referrals',
  requirePartner,
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const limit = Math.min(50, Math.max(1, parseInt(req.query.limit as string, 10) || 20));
    const { referrals, total } = await PartnersService.getReferrals(userId, { page, limit });

    res.json({
      success: true,
      data: referrals,
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
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
  requirePartner,
  validate(createGiftSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const gift = await PartnersService.createGift(userId, req.body);

    await AuditService.logFromRequest(req, 'partner.gift_create', {
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
  })
);

/**
 * @route   GET /api/v1/partners/gifts
 * @desc    Get partner's gifts
 * @access  Private (Partner only)
 */
router.get(
  '/gifts',
  requirePartner,
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
  requirePartner,
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
  requirePartner,
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    await PartnersService.resendGiftEmail(req.params.id, userId);

    await AuditService.logFromRequest(req, 'partner.gift_update', {
      resourceType: 'partner_gift',
      resourceId: req.params.id,
      description: 'Resent gift activation email',
    });

    res.json({
      success: true,
      message: 'Gift email resent successfully',
    });
  })
);

/**
 * @route   GET /api/v1/partners/analytics
 * @desc    Get partner analytics with optional date range filtering
 * @access  Private (Partner only)
 */
router.get(
  '/analytics',
  requirePartner,
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const startDate = req.query.startDate as string | undefined;
    const endDate = req.query.endDate as string | undefined;

    // Validate date format if provided (YYYY-MM-DD)
    const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
    if (startDate && !dateRegex.test(startDate)) {
      throw new AppError('Invalid startDate format. Use YYYY-MM-DD.', 400);
    }
    if (endDate && !dateRegex.test(endDate)) {
      throw new AppError('Invalid endDate format. Use YYYY-MM-DD.', 400);
    }

    const analytics = await PartnersService.getPartnerAnalytics(userId, { startDate, endDate });

    res.json({
      success: true,
      data: analytics,
    });
  })
);

/**
 * @route   GET /api/v1/partners/earnings-history
 * @desc    Get monthly earnings over the last 12 months
 * @access  Private (Partner only)
 */
router.get(
  '/earnings-history',
  requirePartner,
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;

    // Look up partner ID from user ID
    const partnerResult = await pool.query('SELECT id FROM partners WHERE user_id = $1', [userId]);
    if (partnerResult.rows.length === 0) {
      throw new AppError('Partner not found', 404);
    }

    const earningsHistory = await PartnersService.getEarningsHistory(partnerResult.rows[0].id);

    res.json({
      success: true,
      data: earningsHistory,
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
  requirePartner,
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
 * @route   GET /api/v1/partners/gifts/:id/track/email-open
 * @desc    Track email open (called via 1x1 tracking pixel in gift email)
 * @access  Public
 */
router.get(
  '/gifts/:id/track/email-open',
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      `UPDATE partner_gifts
       SET email_opened_at = COALESCE(email_opened_at, NOW())
       WHERE id = $1
       RETURNING id`,
      [req.params.id]
    );
    if (result.rows.length === 0) {
      res.status(404).end();
      return;
    }
    // Return a 1x1 transparent GIF
    const pixel = Buffer.from(
      'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
      'base64'
    );
    res.setHeader('Content-Type', 'image/gif');
    res.setHeader('Cache-Control', 'no-store');
    res.end(pixel);
  })
);

/**
 * @route   POST /api/v1/partners/gifts/:id/track/app-download
 * @desc    Track when homebuyer downloads the app (called on first app launch)
 * @access  Public
 */
router.post(
  '/gifts/:id/track/app-download',
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      `UPDATE partner_gifts
       SET app_download_at = COALESCE(app_download_at, NOW())
       WHERE id = $1
       RETURNING id`,
      [req.params.id]
    );
    if (result.rows.length === 0) {
      throw new AppError('Gift not found', 404);
    }
    res.json({ success: true });
  })
);

/**
 * @route   POST /api/v1/partners/gifts/:id/track/first-item
 * @desc    Track when homebuyer adds their first item (called by items service)
 * @access  Private (authenticated user)
 */
router.post(
  '/gifts/:id/track/first-item',
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      `UPDATE partner_gifts
       SET first_item_added_at = COALESCE(first_item_added_at, NOW())
       WHERE id = $1
       RETURNING id`,
      [req.params.id]
    );
    if (result.rows.length === 0) {
      throw new AppError('Gift not found', 404);
    }
    res.json({ success: true });
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

    await AuditService.logFromRequest(req, 'partner.gift_activate', {
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
  })
);

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
    id: 'professional',
    name: 'Professional',
    price_monthly: 49,
    max_gifts_per_month: 50,
    commission_rate: 0.15,
    features: ['50 gifts/month', '15% commission', 'Priority support'],
  },
  {
    id: 'enterprise',
    name: 'Enterprise',
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
router.get(
  '/tiers',
  asyncHandler(async (_req, res) => {
    res.json({
      success: true,
      data: PARTNER_TIERS,
    });
  })
);

// ========== STRIPE CONNECT ==========

/**
 * @route   POST /api/v1/partners/stripe-connect/onboard
 * @desc    Create a Stripe Connect Express account and return onboarding URL
 * @access  Private (Partner only)
 */
router.post(
  '/stripe-connect/onboard',
  requirePartner,
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const partner = await PartnersService.getPartner(userId);

    let stripeAccountId = partner.stripe_account_id;

    // Create a new Stripe Connect Express account if the partner doesn't have one yet
    if (!stripeAccountId) {
      const account = await stripe.accounts.create({
        type: 'express',
        email: (partner as any).email,
        metadata: { partner_id: partner.id },
      });

      stripeAccountId = account.id;

      // Store the stripe_account_id on the partner record
      await pool.query(
        `UPDATE partners SET stripe_account_id = $1, updated_at = NOW() WHERE id = $2`,
        [stripeAccountId, partner.id]
      );
    }

    // Create an onboarding link
    const accountLink = await stripe.accountLinks.create({
      account: stripeAccountId,
      refresh_url: `${config.app.dashboardUrl}/dashboard/settings?stripe=refresh`,
      return_url: `${config.app.dashboardUrl}/dashboard/settings?stripe=success`,
      type: 'account_onboarding',
    });

    res.json({
      success: true,
      data: { url: accountLink.url },
    });
  })
);

/**
 * @route   GET /api/v1/partners/stripe-connect/status
 * @desc    Check Stripe Connect account status
 * @access  Private (Partner only)
 */
router.get(
  '/stripe-connect/status',
  requirePartner,
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const partner = await PartnersService.getPartner(userId);

    if (!partner.stripe_account_id) {
      return res.json({
        success: true,
        data: {
          connected: false,
          charges_enabled: false,
          payouts_enabled: false,
          onboarded: false,
        },
      });
    }

    // Retrieve the account details from Stripe
    const account = await stripe.accounts.retrieve(partner.stripe_account_id);

    const chargesEnabled = account.charges_enabled ?? false;
    const payoutsEnabled = account.payouts_enabled ?? false;

    // If both capabilities are enabled and partner isn't marked as onboarded yet, update DB
    if (chargesEnabled && payoutsEnabled && !partner.stripe_onboarded) {
      await pool.query(
        `UPDATE partners SET stripe_onboarded = TRUE, updated_at = NOW() WHERE id = $1`,
        [partner.id]
      );
    }

    res.json({
      success: true,
      data: {
        connected: true,
        charges_enabled: chargesEnabled,
        payouts_enabled: payoutsEnabled,
        onboarded: (chargesEnabled && payoutsEnabled) || partner.stripe_onboarded,
      },
    });
  })
);

// ========== ADMIN ROUTES (admin access required) ==========

/**
 * @route   PUT /api/v1/partners/admin/commissions/:id/approve
 * @desc    Approve a pending commission
 * @access  Private (Admin only)
 */
router.put(
  '/admin/commissions/:id/approve',
  requireAdmin,
  asyncHandler(async (req, res) => {
    const { id } = req.params;

    const current = await pool.query(
      `SELECT id, status FROM partner_commissions WHERE id = $1`,
      [id]
    );

    if (current.rows.length === 0) {
      throw new AppError('Commission not found', 404);
    }

    if (current.rows[0].status !== 'pending') {
      throw new AppError(
        `Cannot approve commission with status '${current.rows[0].status}'. Only 'pending' commissions can be approved.`,
        400
      );
    }

    const result = await pool.query(
      `UPDATE partner_commissions
       SET status = 'approved', updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [id]
    );

    res.json({
      success: true,
      data: result.rows[0],
      message: 'Commission approved',
    });
  })
);

/**
 * @route   PUT /api/v1/partners/admin/commissions/:id/pay
 * @desc    Mark an approved commission as paid
 * @access  Private (Admin only)
 */
router.put(
  '/admin/commissions/:id/pay',
  requireAdmin,
  asyncHandler(async (req, res) => {
    const { id } = req.params;

    const current = await pool.query(
      `SELECT id, status FROM partner_commissions WHERE id = $1`,
      [id]
    );

    if (current.rows.length === 0) {
      throw new AppError('Commission not found', 404);
    }

    if (current.rows[0].status !== 'approved') {
      throw new AppError(
        `Cannot pay commission with status '${current.rows[0].status}'. Only 'approved' commissions can be paid.`,
        400
      );
    }

    const result = await pool.query(
      `UPDATE partner_commissions
       SET status = 'paid', paid_at = NOW(), updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [id]
    );

    res.json({
      success: true,
      data: result.rows[0],
      message: 'Commission marked as paid',
    });
  })
);

/**
 * @route   PUT /api/v1/partners/admin/commissions/:id/cancel
 * @desc    Cancel a pending commission
 * @access  Private (Admin only)
 */
router.put(
  '/admin/commissions/:id/cancel',
  requireAdmin,
  asyncHandler(async (req, res) => {
    const { id } = req.params;

    const current = await pool.query(
      `SELECT id, status FROM partner_commissions WHERE id = $1`,
      [id]
    );

    if (current.rows.length === 0) {
      throw new AppError('Commission not found', 404);
    }

    if (current.rows[0].status !== 'pending') {
      throw new AppError(
        `Cannot cancel commission with status '${current.rows[0].status}'. Only 'pending' commissions can be cancelled.`,
        400
      );
    }

    const result = await pool.query(
      `UPDATE partner_commissions
       SET status = 'cancelled', updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [id]
    );

    res.json({
      success: true,
      data: result.rows[0],
      message: 'Commission cancelled',
    });
  })
);

export default router;
