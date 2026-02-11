import { Router } from 'express';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validator';
import { WarrantyClaimsService } from '../services/warranty-claims.service';
import {
  createWarrantyClaimSchema,
  updateWarrantyClaimSchema,
  getClaimsQuerySchema,
} from '../validators/warranty-claims.validator';
import { asyncHandler } from '../utils/async-handler';

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
  validate(createWarrantyClaimSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const claim = await WarrantyClaimsService.createClaim(userId, req.body);

    res.status(201).json({
      success: true,
      data: claim,
      message: 'Warranty claim created successfully',
    });
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
    const { limit, offset, item_id } = req.query;

    const result = await WarrantyClaimsService.getUserClaims(userId, {
      limit: Number(limit),
      offset: Number(offset),
      itemId: item_id as string,
    });

    res.json({
      success: true,
      data: result.claims,
      pagination: {
        total: result.total,
        limit: Number(limit),
        offset: Number(offset),
        has_more: result.total > Number(offset) + result.claims.length,
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

    res.json({
      success: true,
      data: savings,
    });
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

    res.json({
      success: true,
      data: feed,
    });
  })
);

/**
 * @route   GET /api/v1/warranty-claims/:id
 * @desc    Get warranty claim by ID
 * @access  Private
 */
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const claim = await WarrantyClaimsService.getClaimById(req.params.id, userId);

    res.json({
      success: true,
      data: claim,
    });
  })
);

/**
 * @route   PUT /api/v1/warranty-claims/:id
 * @desc    Update warranty claim
 * @access  Private
 */
router.put(
  '/:id',
  validate(updateWarrantyClaimSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const claim = await WarrantyClaimsService.updateClaim(
      req.params.id,
      userId,
      req.body
    );

    res.json({
      success: true,
      data: claim,
      message: 'Warranty claim updated successfully',
    });
  })
);

/**
 * @route   DELETE /api/v1/warranty-claims/:id
 * @desc    Delete warranty claim
 * @access  Private
 */
router.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    await WarrantyClaimsService.deleteClaim(req.params.id, userId);

    res.json({
      success: true,
      message: 'Warranty claim deleted successfully',
    });
  })
);

export default router;
