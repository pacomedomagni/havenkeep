import { Router } from 'express';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { uuidParamSchema } from '../validators';
import { WarrantyClaimsService } from '../services/warranty-claims.service';
import {
  createWarrantyClaimSchema,
  updateWarrantyClaimSchema,
  getClaimsQuerySchema,
} from '../validators/warranty-claims.validator';
import { asyncHandler } from '../utils/async-handler';
import { writeRateLimiter } from '../middleware/rateLimiter';
import { sendSuccess, sendMessage } from '../utils/response';

const router = Router();

// All routes require authentication
router.use(authenticate);

/**
 * @route   POST /api/v1/warranty-claims
 * @desc    Create a new warranty claim
 * @access  Private
 */
router.post(
  '/',
  writeRateLimiter,
  validate(createWarrantyClaimSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const claim = await WarrantyClaimsService.createClaim(userId, req.body);

    sendSuccess(res, claim, { status: 201, message: 'Warranty claim created successfully' });
  })
);

/**
 * @route   GET /api/v1/warranty-claims
 * @desc    Get all warranty claims for authenticated user
 * @access  Private
 */
router.get(
  '/',
  validate(getClaimsQuerySchema, 'query'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const { itemId } = req.query;

    // BE-1/2/3: Explicitly convert and clamp pagination params to safe integers
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit as string, 10) || 50));
    const offset = (page - 1) * limit;

    const result = await WarrantyClaimsService.getUserClaims(userId, {
      limit,
      offset,
      itemId: itemId as string,
    });

    sendSuccess(res, result.claims, {
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
 * @route   GET /api/v1/warranty-claims/savings
 * @desc    Get total savings for user
 * @access  Private
 */
router.get(
  '/savings',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const savings = await WarrantyClaimsService.getTotalSavings(userId);

    sendSuccess(res, savings);
  })
);

/**
 * @route   GET /api/v1/warranty-claims/feed
 * @desc    Get public savings feed (social proof)
 * @access  Private
 */
router.get(
  '/feed',
  asyncHandler(async (req, res) => {
    const limit = Math.min(Number(req.query.limit) || 20, 50);
    const feed = await WarrantyClaimsService.getSavingsFeed(limit);

    sendSuccess(res, feed);
  })
);

/**
 * @route   GET /api/v1/warranty-claims/:id
 * @desc    Get warranty claim by ID
 * @access  Private
 */
router.get(
  '/:id',
  validate(uuidParamSchema, 'params'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const claim = await WarrantyClaimsService.getClaimById(req.params.id, userId);

    sendSuccess(res, claim);
  })
);

/**
 * @route   PUT /api/v1/warranty-claims/:id
 * @desc    Update warranty claim
 * @access  Private
 */
router.put(
  '/:id',
  validate(uuidParamSchema, 'params'),
  writeRateLimiter,
  validate(updateWarrantyClaimSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const claim = await WarrantyClaimsService.updateClaim(
      req.params.id,
      userId,
      req.body
    );

    sendSuccess(res, claim, { message: 'Warranty claim updated successfully' });
  })
);

/**
 * @route   DELETE /api/v1/warranty-claims/:id
 * @desc    Delete warranty claim
 * @access  Private
 */
router.delete(
  '/:id',
  validate(uuidParamSchema, 'params'),
  writeRateLimiter,
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    await WarrantyClaimsService.deleteClaim(req.params.id, userId);

    sendMessage(res, 'Warranty claim deleted successfully');
  })
);

export default router;
