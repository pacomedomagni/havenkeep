import { Router } from 'express';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { WarrantyPurchasesService } from '../services/warranty-purchases.service';
import {
  createWarrantyPurchaseSchema,
  cancelWarrantyPurchaseSchema,
  getPurchasesQuerySchema,
  getExpiringQuerySchema,
} from '../validators/warranty-purchases.validator';
import { asyncHandler } from '../utils/async-handler';

const router = Router();

// All routes require authentication
router.use(authenticate);

/**
 * @route   GET /api/v1/warranty-purchases
 * @desc    Get user's warranty purchases with pagination and optional filters
 * @access  Private
 */
router.get(
  '/',
  validate(getPurchasesQuerySchema, 'query'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const { limit, offset, item_id, status } = req.query;

    const result = await WarrantyPurchasesService.getUserPurchases(userId, {
      limit: Number(limit),
      offset: Number(offset),
      itemId: item_id as string,
      status: status as string,
    });

    res.json({
      success: true,
      data: result.purchases,
      pagination: {
        total: result.total,
        limit: Number(limit),
        offset: Number(offset),
        has_more: result.total > Number(offset) + result.purchases.length,
      },
    });
  })
);

/**
 * @route   GET /api/v1/warranty-purchases/active
 * @desc    Get active warranty coverage summary grouped by item
 * @access  Private
 */
router.get(
  '/active',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const coverage = await WarrantyPurchasesService.getActiveCoverage(userId);

    res.json({
      success: true,
      data: coverage,
    });
  })
);

/**
 * @route   GET /api/v1/warranty-purchases/expiring
 * @desc    Get warranties expiring within N days
 * @access  Private
 */
router.get(
  '/expiring',
  validate(getExpiringQuerySchema, 'query'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const days = Number(req.query.days) || 30;
    const warranties = await WarrantyPurchasesService.getExpiringWarranties(userId, days);

    res.json({
      success: true,
      data: warranties,
    });
  })
);

/**
 * @route   GET /api/v1/warranty-purchases/:id
 * @desc    Get a single warranty purchase by ID
 * @access  Private
 */
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const purchase = await WarrantyPurchasesService.getPurchaseById(req.params.id, userId);

    res.json({
      success: true,
      data: purchase,
    });
  })
);

/**
 * @route   POST /api/v1/warranty-purchases
 * @desc    Create a new warranty purchase
 * @access  Private
 */
router.post(
  '/',
  validate(createWarrantyPurchaseSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const purchase = await WarrantyPurchasesService.createPurchase(userId, req.body);

    res.status(201).json({
      success: true,
      data: purchase,
      message: 'Warranty purchase created successfully',
    });
  })
);

/**
 * @route   POST /api/v1/warranty-purchases/:id/cancel
 * @desc    Cancel a warranty purchase
 * @access  Private
 */
router.post(
  '/:id/cancel',
  validate(cancelWarrantyPurchaseSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const purchase = await WarrantyPurchasesService.cancelPurchase(
      req.params.id,
      userId,
      req.body.reason
    );

    res.json({
      success: true,
      data: purchase,
      message: 'Warranty purchase cancelled successfully',
    });
  })
);

export default router;
