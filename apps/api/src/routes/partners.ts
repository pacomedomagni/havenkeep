import { Router } from 'express';
import { pool } from '../db';
import { config } from '../config';
import { createStripeClient } from '../utils/stripe-client';
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
import { uuidParamSchema } from '../validators';
import { asyncHandler } from '../utils/async-handler';
import { activationCodeRateLimiter, writeRateLimiter, giftResendRateLimiter } from '../middleware/rateLimiter';
import { AuditService } from '../services/audit.service';
import { AppError } from '../utils/errors';
import { sendSuccess, sendMessage } from '../utils/response';
import { verifyPartnerEmailPixelHmac } from '../services/email.service';
import { getRedisClient } from '../utils/redis';
import { logger } from '../utils/logger';

const CODE_MAX_ATTEMPTS = 10;
const CODE_LOCK_SEC = 15 * 60;
const CODE_WINDOW_SEC = 60 * 60;

async function assertCodeNotLocked(code: string): Promise<void> {
  try {
    const redis = await getRedisClient();
    const ttl = await redis.ttl(`gift:code:lock:${code}`);
    if (ttl > 0) {
      throw new AppError(
        `This activation code is temporarily locked. Try again in ${Math.ceil(ttl / 60)} minute(s).`,
        429,
      );
    }
  } catch (err) {
    if (err instanceof AppError) throw err;
    logger.error({ err, code }, 'Code lockout check failed; allowing through');
  }
}

async function recordCodeAttempt(code: string): Promise<void> {
  try {
    const redis = await getRedisClient();
    const n = await redis.incr(`gift:code:attempts:${code}`);
    if (n === 1) await redis.expire(`gift:code:attempts:${code}`, CODE_WINDOW_SEC);
    if (n >= CODE_MAX_ATTEMPTS) {
      await redis.set(`gift:code:lock:${code}`, '1', { EX: CODE_LOCK_SEC });
      logger.warn({ code, n }, 'Activation code locked due to too many failed attempts');
    }
  } catch (err) {
    logger.error({ err, code }, 'Failed to record activation-code attempt');
  }
}

async function clearCodeAttempts(code: string): Promise<void> {
  try {
    const redis = await getRedisClient();
    await redis.del([`gift:code:attempts:${code}`, `gift:code:lock:${code}`]);
  } catch {
    /* ignore */
  }
}

const stripe = createStripeClient();

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
  validate(uuidParamSchema, 'params'),
  asyncHandler(async (req, res) => {
    const gift = await PartnersService.getPublicGiftDetails(req.params.id);

    sendSuccess(res, gift);
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
    const { activation_code, homebuyer_email } = req.body;

    if (!activation_code || typeof activation_code !== 'string') {
      return res.status(400).json({
        success: false,
        message: 'Activation code is required',
      });
    }

    if (!homebuyer_email || typeof homebuyer_email !== 'string') {
      // Email is the second factor that closes the enumeration oracle.
      return res.status(400).json({
        success: false,
        message: 'homebuyer_email is required',
      });
    }

    // Validate activation code format (16 hex with optional dashes — older
    // 8-char codes are still accepted for the pre-rotation cohort).
    if (activation_code.length < 6 || activation_code.length > 32 || !/^[A-Za-z0-9_-]+$/.test(activation_code)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid activation code format',
      });
    }

    const normalized = activation_code.replace(/-/g, '').toUpperCase();
    await assertCodeNotLocked(normalized);

    try {
      const result = await PartnersService.verifyActivationCode(activation_code, homebuyer_email);
      await clearCodeAttempts(normalized);
      sendSuccess(res, result);
    } catch (err) {
      // 404 => invalid code or wrong email; both count as a failed attempt
      // for the per-code lockout (the route doesn't distinguish them).
      if (err instanceof AppError && err.statusCode === 404) {
        await recordCodeAttempt(normalized);
      }
      throw err;
    }
  })
);

/**
 * @route   GET /api/v1/partners/gifts/:id/track/email-open
 * @desc    Track email open (called via 1x1 tracking pixel in gift email)
 * @access  Public
 */
router.get(
  '/gifts/:id/track/email-open',
  validate(uuidParamSchema, 'params'),
  asyncHandler(async (req, res) => {
    // Constant-200: don't reveal whether the gift exists. The UPDATE happens
    // best-effort; whether or not it matched a row, we still ship the pixel
    // (Ch03-F029). A scraper hitting this endpoint with a UUID guess gets
    // an indistinguishable response.
    await pool.query(
      `UPDATE partner_gifts
       SET email_opened_at = COALESCE(email_opened_at, NOW())
       WHERE id = $1`,
      [req.params.id]
    );
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
  validate(uuidParamSchema, 'params'),
  asyncHandler(async (req, res) => {
    // Constant-200 to close the enumeration oracle (Ch03-F029).
    await pool.query(
      `UPDATE partner_gifts
       SET app_download_at = COALESCE(app_download_at, NOW())
       WHERE id = $1`,
      [req.params.id]
    );
    sendMessage(res, 'App download tracked');
  })
);

/**
 * @route   GET /api/v1/partners/:id/track/welcome-open
 * @desc    1x1 tracking pixel embedded in the partner welcome email.
 * @access  Public (HMAC-verified via `?t=` query param — Ch03-F083/F084)
 */
router.get(
  '/:id/track/welcome-open',
  validate(uuidParamSchema, 'params'),
  asyncHandler(async (req, res) => {
    const token = (req.query.t as string | undefined) ?? '';
    const partnerId = req.params.id;
    const validHmac = token.length > 0 && verifyPartnerEmailPixelHmac(partnerId, 'welcome', token);
    // Constant-200 + 1x1 pixel regardless of validity so a probe can't
    // distinguish "good token" from "wrong token" by status code (matches
    // the gift-pixel pattern in this file).
    if (validHmac) {
      await pool.query(
        `UPDATE partners
         SET welcome_email_opened_at = COALESCE(welcome_email_opened_at, NOW())
         WHERE id = $1`,
        [partnerId],
      );
    }
    const pixel = Buffer.from(
      'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
      'base64',
    );
    res.setHeader('Content-Type', 'image/gif');
    res.setHeader('Cache-Control', 'no-store');
    res.end(pixel);
  }),
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

    sendSuccess(res, { referral_code: referralCode });
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

    sendSuccess(res, referrals, {
      pagination: {
        page,
        limit,
        total,
        total_pages: Math.ceil(total / limit),
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
  writeRateLimiter,
  validate(registerPartnerSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const partner = await PartnersService.registerPartner(userId, req.body);

    sendSuccess(res, partner, { status: 201, message: 'Partner registration successful' });
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

    sendSuccess(res, partner);
  })
);

/**
 * @route   PUT /api/v1/partners/me
 * @desc    Update partner profile
 * @access  Private
 */
router.put(
  '/me',
  writeRateLimiter,
  validate(updatePartnerSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const partner = await PartnersService.updatePartner(userId, req.body);

    sendSuccess(res, partner, { message: 'Partner profile updated' });
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

    sendSuccess(res, gift, { status: 201, message: 'Gift created successfully. Homebuyer will receive an email.' });
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
    const { status } = req.query;

    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit as string, 10) || 50));
    const offset = (page - 1) * limit;

    const result = await PartnersService.getPartnerGifts(userId, {
      limit,
      offset,
      status: status as string,
    });

    sendSuccess(res, result.gifts, {
      pagination: {
        page,
        limit,
        total: result.total,
        total_pages: Math.ceil(result.total / limit),
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
  validate(uuidParamSchema, 'params'),
  requirePartner,
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const gift = await PartnersService.getGift(req.params.id, userId);

    sendSuccess(res, gift);
  })
);

/**
 * @route   POST /api/v1/partners/gifts/:id/resend
 * @desc    Resend gift activation email
 * @access  Private (Partner only)
 */
router.post(
  '/gifts/:id/resend',
  validate(uuidParamSchema, 'params'),
  giftResendRateLimiter,
  requirePartner,
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    await PartnersService.resendGiftEmail(req.params.id, userId);

    await AuditService.logFromRequest(req, 'partner.gift_update', {
      resourceType: 'partner_gift',
      resourceId: req.params.id,
      description: 'Resent gift activation email',
    });

    sendMessage(res, 'Gift email resent successfully');
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
    let startDate = req.query.startDate as string | undefined;
    let endDate = req.query.endDate as string | undefined;

    // Validate date format if provided (YYYY-MM-DD)
    const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
    if (startDate && !dateRegex.test(startDate)) {
      throw new AppError('Invalid startDate format. Use YYYY-MM-DD.', 400);
    }
    if (endDate && !dateRegex.test(endDate)) {
      throw new AppError('Invalid endDate format. Use YYYY-MM-DD.', 400);
    }

    // S3-G: bound the window. Partner analytics scans a per-row commission
    // ledger; an unbounded range (or a 130-year window) produces an
    // unnecessarily large query and can pin a worker. Cap the window at
    // 365 days, default to last 90 days when omitted.
    const MAX_RANGE_DAYS = 365;
    const DEFAULT_RANGE_DAYS = 90;
    const todayUtc = new Date().toISOString().slice(0, 10);
    if (!endDate) endDate = todayUtc;
    if (!startDate) {
      const start = new Date(endDate + 'T00:00:00Z');
      start.setUTCDate(start.getUTCDate() - DEFAULT_RANGE_DAYS);
      startDate = start.toISOString().slice(0, 10);
    }
    const startMs = Date.parse(startDate + 'T00:00:00Z');
    const endMs = Date.parse(endDate + 'T00:00:00Z');
    if (!Number.isFinite(startMs) || !Number.isFinite(endMs) || startMs > endMs) {
      throw new AppError('Invalid date range', 400);
    }
    const spanDays = Math.floor((endMs - startMs) / (24 * 60 * 60 * 1000));
    if (spanDays > MAX_RANGE_DAYS) {
      throw new AppError(
        `Date range cannot exceed ${MAX_RANGE_DAYS} days`,
        400,
      );
    }

    const analytics = await PartnersService.getPartnerAnalytics(userId, { startDate, endDate });

    sendSuccess(res, analytics);
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

    sendSuccess(res, earningsHistory);
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

    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit as string, 10) || 50));
    const offset = (page - 1) * limit;

    const result = await PartnersService.getCommissions(userId, {
      limit,
      offset,
    });

    sendSuccess(res, result.commissions, {
      pagination: {
        page,
        limit,
        total: result.total,
        total_pages: Math.ceil(result.total / limit),
      },
    });
  })
);

/**
 * @route   POST /api/v1/partners/gifts/:id/track/first-item
 * @desc    Track when homebuyer adds their first item (called by items service)
 * @access  Private (authenticated user)
 */
router.post(
  '/gifts/:id/track/first-item',
  validate(uuidParamSchema, 'params'),
  asyncHandler(async (req, res) => {
    // Constant-200 (Ch03-F030). The UPDATE only matches when activated_user_id
    // matches the caller — if the caller is wrong, we silently no-op rather
    // than 404'ing, which would distinguish "gift exists but belongs to
    // someone else" from "gift doesn't exist".
    await pool.query(
      `UPDATE partner_gifts
       SET first_item_added_at = COALESCE(first_item_added_at, NOW())
       WHERE id = $1 AND activated_user_id = $2`,
      [req.params.id, req.user!.id]
    );
    sendMessage(res, 'First item tracked');
  })
);

/**
 * @route   POST /api/v1/partners/gifts/:id/activate
 * @desc    Activate gift (called when homebuyer signs up via gift link)
 * @access  Private (requires authentication)
 */
router.post(
  '/gifts/:id/activate',
  validate(uuidParamSchema, 'params'),
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

    sendSuccess(res, gift, { message: `Premium activated! You have ${gift.premium_months} months of HavenKeep Premium.` });
  })
);

// ========== PARTNER TIERS ==========

// H-P4 (audit): the actual revenue model is per-gift, not subscription.
// price_monthly was misleading — the dashboard advertised a recurring
// fee that doesn't exist (no Stripe Subscription is created at signup;
// no dunning). Every tier's price_per_gift now mirrors the canonical
// TIER_PRICE_PER_GIFT_USD from partners.service.ts so the two values
// can't drift. price_monthly stays at 0 to make the no-subscription
// truth explicit; the field is retained for the dashboard which
// already renders it.
import { TIER_PRICE_PER_GIFT_USD } from '../services/partners.service';

const PARTNER_TIERS = [
  {
    id: 'basic',
    name: 'Basic',
    price_monthly: 0,
    price_per_gift: TIER_PRICE_PER_GIFT_USD.basic,
    max_gifts_per_month: 10,
    commission_rate: 0.10,
    features: [
      `$${TIER_PRICE_PER_GIFT_USD.basic} per gift`,
      '10 gifts/month',
      '10% commission',
    ],
  },
  {
    id: 'premium',
    name: 'Premium',
    price_monthly: 0,
    price_per_gift: TIER_PRICE_PER_GIFT_USD.premium,
    max_gifts_per_month: 50,
    commission_rate: 0.15,
    features: [
      `$${TIER_PRICE_PER_GIFT_USD.premium} per gift`,
      '50 gifts/month',
      '15% commission',
      'Priority support',
    ],
  },
  {
    id: 'platinum',
    name: 'Platinum',
    price_monthly: 0,
    price_per_gift: TIER_PRICE_PER_GIFT_USD.platinum,
    max_gifts_per_month: -1,
    commission_rate: 0.20,
    features: [
      `$${TIER_PRICE_PER_GIFT_USD.platinum} per gift`,
      'Unlimited gifts',
      '20% commission',
      'Dedicated account manager',
      'Custom branding',
    ],
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
    sendSuccess(res, PARTNER_TIERS);
  })
);

// ========== STRIPE CONNECT ==========

/**
 * @route   POST /api/v1/partners/stripe-connect/onboard
 * @desc    Create a Stripe Connect Express account and return onboarding URL
 * @access  Private (Partner only)
 *
 * Hardening (Ch03-F063..F066, F113):
 * - Email comes from the typed `users` row, not `(partner as any).email`.
 * - `stripe.accounts.create` is idempotent on the partner id so retries
 *   don't spawn duplicate connected accounts.
 * - Already-onboarded (status='enabled') partners get a refresh-only link
 *   instead of an onboarding link they don't need.
 * - `stripe_account_status` (set by webhook) is the source of truth; the
 *   sticky `stripe_onboarded` flag is only updated alongside it.
 */
router.post(
  '/stripe-connect/onboard',
  requirePartner,
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const partner = await PartnersService.getPartner(userId);

    // Resolve the partner's email via the typed users row.
    const userResult = await pool.query<{ email: string }>(
      'SELECT email FROM users WHERE id = $1',
      [userId],
    );
    if (userResult.rows.length === 0) {
      throw new AppError('User not found', 404);
    }
    const partnerEmail = userResult.rows[0].email;

    let stripeAccountId = partner.stripe_account_id;

    if (!stripeAccountId) {
      const account = await stripe.accounts.create(
        {
          type: 'express',
          email: partnerEmail,
          metadata: { partner_id: partner.id, hk_user_id: userId },
        },
        { idempotencyKey: `partner-connect-${partner.id}` },
      );

      stripeAccountId = account.id;

      await pool.query(
        `UPDATE partners
            SET stripe_account_id = $1,
                stripe_account_status = 'pending',
                stripe_account_status_at = NOW(),
                updated_at = NOW()
          WHERE id = $2`,
        [stripeAccountId, partner.id],
      );
    }

    // If the partner is already enabled, hand them a refresh-only link.
    const linkType =
      partner.stripe_account_status === 'enabled'
        ? 'account_update'
        : 'account_onboarding';

    const accountLink = await stripe.accountLinks.create({
      account: stripeAccountId,
      refresh_url: `${config.app.dashboardUrl}/dashboard/settings?stripe=refresh`,
      return_url: `${config.app.dashboardUrl}/dashboard/settings?stripe=success`,
      type: linkType,
    });

    sendSuccess(res, { url: accountLink.url });
  })
);

/**
 * @route   GET /api/v1/partners/stripe-connect/status
 * @desc    Check Stripe Connect account status (live read from Stripe).
 * @access  Private (Partner only)
 *
 * The DB tracks `stripe_account_status` driven by `account.updated` /
 * `account.application.deauthorized` webhooks (Ch03-F066, F113). This
 * endpoint also pings Stripe live so a UI hit shows up-to-the-second state,
 * and the result is reflected back into the DB. We do NOT keep
 * `stripe_onboarded` sticky in the deactivation case — it tracks the
 * derived `enabled` state.
 */
router.get(
  '/stripe-connect/status',
  requirePartner,
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const partner = await PartnersService.getPartner(userId);

    if (!partner.stripe_account_id) {
      return sendSuccess(res, {
        connected: false,
        charges_enabled: false,
        payouts_enabled: false,
        onboarded: false,
        status: 'unknown',
      });
    }

    const account = await stripe.accounts.retrieve(partner.stripe_account_id);

    const chargesEnabled = account.charges_enabled ?? false;
    const payoutsEnabled = account.payouts_enabled ?? false;
    const requirementsDisabled = account.requirements?.disabled_reason;

    let derived: 'unknown' | 'pending' | 'enabled' | 'restricted' | 'disabled' | 'rejected';
    if (
      requirementsDisabled === 'rejected.fraud' ||
      requirementsDisabled === 'rejected.terms_of_service' ||
      requirementsDisabled === 'rejected.listed' ||
      requirementsDisabled === 'rejected.other'
    ) {
      derived = 'rejected';
    } else if (requirementsDisabled) {
      derived = 'restricted';
    } else if (chargesEnabled && payoutsEnabled) {
      derived = 'enabled';
    } else if (chargesEnabled || payoutsEnabled) {
      derived = 'restricted';
    } else {
      derived = 'pending';
    }

    if (derived !== partner.stripe_account_status) {
      await pool.query(
        `UPDATE partners
            SET stripe_account_status = $2,
                stripe_account_status_at = NOW(),
                stripe_onboarded = ($2 = 'enabled'),
                updated_at = NOW()
          WHERE id = $1`,
        [partner.id, derived],
      );
    }

    sendSuccess(res, {
      connected: true,
      charges_enabled: chargesEnabled,
      payouts_enabled: payoutsEnabled,
      onboarded: derived === 'enabled',
      status: derived,
    });
  })
);

// ========== PARTNER PAYOUTS (self-service) ==========

/**
 * @route   GET /api/v1/partners/me/payouts/summary
 * @desc    Earnings totals for the authenticated partner: pending (within
 *          the 30-day refund-clawback window), approved (eligible for
 *          payout), paid lifetime + paid year-to-date. Drives the
 *          dashboard's Payouts page header cards.
 * @access  Private (Partner only)
 */
router.get(
  '/me/payouts/summary',
  requirePartner,
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const partner = await PartnersService.getPartner(userId);

    // One round-trip aggregation. Casting to NUMERIC keeps cents-precision
    // through SUM (commissions live as DECIMAL).
    const result = await pool.query<{
      pending_amount: string;
      approved_amount: string;
      paid_lifetime: string;
      paid_ytd: string;
    }>(
      `SELECT
         COALESCE(SUM(amount) FILTER (WHERE status = 'pending'), 0)::numeric AS pending_amount,
         COALESCE(SUM(amount) FILTER (WHERE status = 'approved'), 0)::numeric AS approved_amount,
         COALESCE(SUM(amount) FILTER (WHERE status = 'paid'), 0)::numeric AS paid_lifetime,
         COALESCE(SUM(amount) FILTER (
           WHERE status = 'paid' AND paid_at >= date_trunc('year', NOW())
         ), 0)::numeric AS paid_ytd
       FROM partner_commissions
       WHERE partner_id = $1`,
      [partner.id],
    );
    const row = result.rows[0];

    sendSuccess(res, {
      pending_amount: Number(row.pending_amount),
      approved_amount: Number(row.approved_amount),
      paid_lifetime: Number(row.paid_lifetime),
      paid_ytd: Number(row.paid_ytd),
      stripe_account_status: partner.stripe_account_status,
      stripe_payouts_enabled: partner.stripe_account_status === 'enabled',
      last_payout_requested_at: (partner as any).last_payout_requested_at ?? null,
    });
  }),
);

/**
 * @route   POST /api/v1/partners/me/payouts
 * @desc    On-demand payout: sweep every 'approved' commission for the
 *          authenticated partner, fire one Stripe transfer per row, mark
 *          them paid. Idempotency keys are derived from each commission
 *          id so a retried request is safe.
 * @access  Private (Partner only)
 *
 * Payment model: each approved commission becomes its own Stripe transfer.
 * Per-row transfers (rather than one aggregated transfer) preserve the
 * commission_id ↔ transfer_id mapping the admin payout endpoint already
 * relies on, keep the chk_partner_commissions_paid_has_transfer constraint
 * satisfied row-by-row, and let a webhook payout.failed handler narrow
 * blame to a specific commission. Stripe absorbs no per-transfer fee on
 * the platform side; partners pay the standard Stripe Connect bank-receive
 * fee on their connected account.
 *
 * Partial-failure semantics: each row's UPDATE is atomic and post-transfer.
 * If transfer #3 of 5 fails, transfers #1+2 stay paid, #3 stays approved
 * with no transfer id, #4+5 never run. The response surfaces both
 * `paid_count` and `failed_count` so the dashboard can render a
 * non-binary success state.
 */
router.post(
  '/me/payouts',
  requirePartner,
  writeRateLimiter,
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const partner = await PartnersService.getPartner(userId);

    // Ch03-F113: only `enabled` accounts can receive transfers. The
    // signup → onboarding → KYC chain must be complete before a partner
    // can withdraw.
    if (!partner.stripe_account_id || partner.stripe_account_status !== 'enabled') {
      throw new AppError(
        `Stripe Connect onboarding is not complete (current status: '${partner.stripe_account_status}'). Finish setup in Settings before requesting a payout.`,
        409,
      );
    }

    const eligible = await pool.query<{
      id: string;
      amount: string;
    }>(
      `SELECT id, amount
         FROM partner_commissions
        WHERE partner_id = $1
          AND status = 'approved'
        ORDER BY created_at ASC`,
      [partner.id],
    );

    // Stamp the request timestamp regardless of whether anything was
    // eligible. The dashboard reads this to render "you requested a payout
    // X minutes ago — nothing was eligible" so a zero-row sweep doesn't
    // look like a silent failure.
    await pool.query(
      `UPDATE partners SET last_payout_requested_at = NOW(), updated_at = NOW() WHERE id = $1`,
      [partner.id],
    );

    if (eligible.rows.length === 0) {
      return sendSuccess(res, {
        paid_count: 0,
        failed_count: 0,
        paid_total: 0,
        transfers: [],
      });
    }

    let paidCount = 0;
    let failedCount = 0;
    let paidTotal = 0;
    const transfers: Array<{ commission_id: string; transfer_id: string; amount: number }> = [];

    for (const row of eligible.rows) {
      const amountCents = Math.round(Number(row.amount) * 100);
      if (!Number.isFinite(amountCents) || amountCents <= 0) {
        failedCount += 1;
        logger.warn({ commissionId: row.id, amount: row.amount }, 'Skipping commission with non-positive amount');
        continue;
      }

      try {
        const transfer = await stripe.transfers.create(
          {
            amount: amountCents,
            currency: 'usd',
            destination: partner.stripe_account_id,
            metadata: {
              commission_id: row.id,
              partner_id: partner.id,
              source: 'self_service_payout',
            },
          },
          { idempotencyKey: `commission-pay-${row.id}` },
        );

        const updated = await pool.query(
          `UPDATE partner_commissions
              SET status = 'paid',
                  paid_at = NOW(),
                  updated_at = NOW(),
                  stripe_transfer_id = $2
            WHERE id = $1 AND status = 'approved'
            RETURNING id`,
          [row.id, transfer.id],
        );

        if (updated.rowCount === 0) {
          // Concurrent admin pay or another self-service request beat us
          // to this row. Stripe transfer succeeded with the same idempotency
          // key the prior caller used, so no double-spend — but we don't
          // count this as a fresh payout from this request.
          logger.warn(
            { commissionId: row.id, transferId: transfer.id },
            'Commission state changed mid-payout; transfer succeeded idempotently',
          );
          continue;
        }

        paidCount += 1;
        paidTotal += Number(row.amount);
        transfers.push({
          commission_id: row.id,
          transfer_id: transfer.id,
          amount: Number(row.amount),
        });
      } catch (err) {
        failedCount += 1;
        logger.error(
          { err, commissionId: row.id, partnerId: partner.id },
          'Stripe transfer failed during self-service payout',
        );
      }
    }

    await AuditService.logFromRequest(req, 'partner.payout_request', {
      resourceType: 'partner',
      resourceId: partner.id,
      description: `Self-service payout: ${paidCount} paid, ${failedCount} failed, $${paidTotal.toFixed(2)} total`,
      metadata: {
        paid_count: paidCount,
        failed_count: failedCount,
        paid_total: paidTotal,
        eligible_count: eligible.rows.length,
      },
    });

    sendSuccess(res, {
      paid_count: paidCount,
      failed_count: failedCount,
      paid_total: paidTotal,
      transfers,
    });
  }),
);

/**
 * @route   POST /api/v1/partners/me/tax-form-link
 * @desc    Mint a one-time login link to the partner's Stripe Express
 *          dashboard. The Express dashboard is where Stripe surfaces
 *          1099-NEC tax forms (and the partner's payout history). We
 *          delegate tax-form delivery to Stripe Connect rather than
 *          generating our own 1099s — Stripe Tax Reporting issues the
 *          forms and files them with the IRS.
 * @access  Private (Partner only)
 *
 * Stripe `accounts.createLoginLink` returns a short-lived URL. We do NOT
 * persist it; the link is single-use and gates on Stripe's session.
 */
router.post(
  '/me/tax-form-link',
  requirePartner,
  writeRateLimiter,
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const partner = await PartnersService.getPartner(userId);

    if (!partner.stripe_account_id) {
      throw new AppError(
        'Stripe Connect onboarding has not started yet. Finish setup in Settings to access tax documents.',
        409,
      );
    }

    const loginLink = await stripe.accounts.createLoginLink(partner.stripe_account_id);
    sendSuccess(res, { url: loginLink.url });
  }),
);

// ========== ADMIN ROUTES (admin access required) ==========

/**
 * @route   PUT /api/v1/partners/admin/commissions/:id/approve
 * @desc    Approve a pending commission
 * @access  Private (Admin only)
 */
router.put(
  '/admin/commissions/:id/approve',
  validate(uuidParamSchema, 'params'),
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

    sendSuccess(res, result.rows[0], { message: 'Commission approved' });
  })
);

/**
 * @route   PUT /api/v1/partners/admin/commissions/:id/pay
 * @desc    Mark an approved commission as paid
 * @access  Private (Admin only)
 */
router.put(
  '/admin/commissions/:id/pay',
  validate(uuidParamSchema, 'params'),
  requireAdmin,
  asyncHandler(async (req, res) => {
    const { id } = req.params;

    // Fetch commission + partner connect-account in one round trip.
    const current = await pool.query(
      `SELECT pc.id, pc.status, pc.amount, pc.partner_id,
              p.stripe_account_id, p.stripe_account_status
         FROM partner_commissions pc
         JOIN partners p ON p.id = pc.partner_id
        WHERE pc.id = $1`,
      [id],
    );

    if (current.rows.length === 0) {
      throw new AppError('Commission not found', 404);
    }
    const commission = current.rows[0];

    if (commission.status !== 'approved') {
      throw new AppError(
        `Cannot pay commission with status '${commission.status}'. Only 'approved' commissions can be paid.`,
        400,
      );
    }

    // Only `enabled` accounts can receive transfers. `restricted`, `pending`,
    // `disabled`, `rejected`, `unknown` all block payouts so a deauthorized
    // partner doesn't keep getting paid (Ch03-F113).
    if (!commission.stripe_account_id || commission.stripe_account_status !== 'enabled') {
      throw new AppError(
        `Partner Stripe Connect account is not in 'enabled' state (current: '${commission.stripe_account_status}'). Payouts are blocked until the partner re-onboards.`,
        409,
      );
    }

    const amountCents = Math.round(Number(commission.amount) * 100);
    if (!Number.isFinite(amountCents) || amountCents <= 0) {
      throw new AppError('Commission amount is invalid', 400);
    }

    // Fire the Stripe transfer with an idempotency key derived from the
    // commission id. If retried (network blip, admin double-click) Stripe
    // returns the same transfer instead of duplicating the payout.
    const transfer = await stripe.transfers.create(
      {
        amount: amountCents,
        currency: 'usd',
        destination: commission.stripe_account_id,
        metadata: {
          commission_id: commission.id,
          partner_id: commission.partner_id,
        },
      },
      { idempotencyKey: `commission-pay-${commission.id}` },
    );

    // Atomic state transition: only succeed if the row is still 'approved'.
    // A concurrent pay attempt that already flipped it to 'paid' will see 0
    // rows here and we'll return 409 instead of double-paying (audit F013).
    const result = await pool.query(
      `UPDATE partner_commissions
          SET status = 'paid',
              paid_at = NOW(),
              updated_at = NOW(),
              stripe_transfer_id = $2
        WHERE id = $1 AND status = 'approved'
        RETURNING *`,
      [commission.id, transfer.id],
    );

    if (result.rows.length === 0) {
      // The DB UPDATE didn't happen but the transfer did. Surface the
      // transfer id so an operator can reconcile manually.
      throw new AppError(
        `Commission state changed concurrently — Stripe transfer ${transfer.id} succeeded; reconcile manually`,
        409,
      );
    }

    sendSuccess(res, result.rows[0], { message: 'Commission paid via Stripe transfer' });
  })
);

/**
 * @route   PUT /api/v1/partners/admin/commissions/:id/cancel
 * @desc    Cancel a pending commission
 * @access  Private (Admin only)
 */
router.put(
  '/admin/commissions/:id/cancel',
  validate(uuidParamSchema, 'params'),
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

    sendSuccess(res, result.rows[0], { message: 'Commission cancelled' });
  })
);

export default router;
