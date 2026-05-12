import { Router } from 'express';
import { pool } from '../db';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { PartnersService } from '../services/partners.service';
import {
  registerPartnerSchema,
  updatePartnerSchema,
  createGiftSchema,
  getGiftsQuerySchema,
} from '../validators/partners.validator';
import { uuidParamSchema } from '../validators';
import { asyncHandler } from '../utils/async-handler';
import {
  activationCodeRateLimiter,
  writeRateLimiter,
  giftResendRateLimiter,
} from '../middleware/rateLimiter';
import { idempotency } from '../middleware/idempotency';
import { AuditService } from '../services/audit.service';
import { AppError } from '../utils/errors';
import { sendSuccess, sendMessage } from '../utils/response';
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
  }),
);

/**
 * @route   POST /api/v1/partners/gifts/verify-code
 * @desc    Verify activation code + email and return gift id
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

    // 16 hex chars with optional dashes; legacy 8-char codes still pass.
    if (
      activation_code.length < 6 ||
      activation_code.length > 32 ||
      !/^[A-Za-z0-9_-]+$/.test(activation_code)
    ) {
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
  }),
);

/**
 * @route   GET /api/v1/partners/gifts/:id/track/email-open
 * @desc    1x1 tracking pixel embedded in the gift activation email.
 * @access  Public (constant-200 — no enumeration oracle)
 */
router.get(
  '/gifts/:id/track/email-open',
  validate(uuidParamSchema, 'params'),
  asyncHandler(async (req, res) => {
    await pool.query(
      `UPDATE partner_gifts
       SET email_opened_at = COALESCE(email_opened_at, NOW())
       WHERE id = $1`,
      [req.params.id],
    );
    const pixel = Buffer.from(
      'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
      'base64',
    );
    res.setHeader('Content-Type', 'image/gif');
    res.setHeader('Cache-Control', 'no-store');
    res.end(pixel);
  }),
);

/**
 * @route   POST /api/v1/partners/gifts/:id/track/app-download
 * @desc    Track when homebuyer downloads the app (first launch).
 * @access  Public (constant-200)
 */
router.post(
  '/gifts/:id/track/app-download',
  validate(uuidParamSchema, 'params'),
  asyncHandler(async (req, res) => {
    await pool.query(
      `UPDATE partner_gifts
       SET app_download_at = COALESCE(app_download_at, NOW())
       WHERE id = $1`,
      [req.params.id],
    );
    sendMessage(res, 'App download tracked');
  }),
);

// ========== PROTECTED ROUTES (authentication required) ==========
router.use(authenticate);

/**
 * @route   POST /api/v1/partners/register
 * @desc    Register the current user as a partner
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
  }),
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
  }),
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
  }),
);

/**
 * @route   POST /api/v1/partners/gifts
 * @desc    Create a closing gift (6 months of premium, free for the homebuyer)
 * @access  Private (Partner only)
 */
router.post(
  '/gifts',
  requirePartner,
  // Required Idempotency-Key (C0-6): a transport-level retry of POST /gifts
  // must not mint two gift rows for one user intent.
  writeRateLimiter,
  idempotency('partners:gift_create', { required: true }),
  validate(createGiftSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const gift = await PartnersService.createGift(userId, req.body);

    await AuditService.logFromRequest(req, 'partner.gift_create', {
      resourceType: 'partner_gift',
      resourceId: gift.id,
      description: `Created gift for ${gift.homebuyer_email}`,
      metadata: { premium_months: gift.premium_months },
    });

    sendSuccess(res, gift, {
      status: 201,
      message: 'Gift created successfully. Homebuyer will receive an email.',
    });
  }),
);

/**
 * @route   GET /api/v1/partners/gifts
 * @desc    List the partner's gifts (paginated, filterable by status)
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
  }),
);

/**
 * @route   GET /api/v1/partners/gifts/:id
 * @desc    Get a single gift (must belong to the partner)
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
  }),
);

/**
 * @route   POST /api/v1/partners/gifts/:id/resend
 * @desc    Resend the activation email (rate-limited to 3/hour)
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
  }),
);

/**
 * @route   GET /api/v1/partners/analytics
 * @desc    Summary stats for the partner dashboard
 * @access  Private (Partner only)
 */
router.get(
  '/analytics',
  requirePartner,
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const analytics = await PartnersService.getPartnerAnalytics(userId);
    sendSuccess(res, analytics);
  }),
);

/**
 * @route   POST /api/v1/partners/gifts/:id/track/first-item
 * @desc    Track when the homebuyer adds their first item.
 * @access  Private (the activated user only — constant-200 if anyone else)
 */
router.post(
  '/gifts/:id/track/first-item',
  validate(uuidParamSchema, 'params'),
  asyncHandler(async (req, res) => {
    await pool.query(
      `UPDATE partner_gifts
       SET first_item_added_at = COALESCE(first_item_added_at, NOW())
       WHERE id = $1 AND activated_user_id = $2`,
      [req.params.id, req.user!.id],
    );
    sendMessage(res, 'First item tracked');
  }),
);

/**
 * @route   POST /api/v1/partners/gifts/:id/activate
 * @desc    Activate a gift — grants premium months to the redeeming user.
 * @access  Private (any authenticated user; redemption rule lives in the service)
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
      metadata: { premium_months: gift.premium_months },
    });

    sendSuccess(res, gift, {
      message: `Premium activated! You have ${gift.premium_months} months of HavenKeep Premium.`,
    });
  }),
);

export default router;
