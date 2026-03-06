import { Router } from 'express';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { uuidParamSchema } from '../validators';
import { WarrantyPurchasesService } from '../services/warranty-purchases.service';
import {
  createWarrantyPurchaseSchema,
  cancelWarrantyPurchaseSchema,
  getPurchasesQuerySchema,
  getExpiringQuerySchema,
} from '../validators/warranty-purchases.validator';
import { asyncHandler } from '../utils/async-handler';
import { query } from '../db';
import { AppError } from '../utils/errors';
import { writeRateLimiter } from '../middleware/rateLimiter';
import { sendSuccess, sendMessage } from '../utils/response';

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
    const { item_id, status } = req.query;

    // BE-1/2/3: Explicitly convert and clamp pagination params to safe integers
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit as string, 10) || 50));
    const offset = (page - 1) * limit;

    const result = await WarrantyPurchasesService.getUserPurchases(userId, {
      limit,
      offset,
      itemId: item_id as string,
      status: status as string,
    });

    sendSuccess(res, result.purchases, {
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
 * @route   GET /api/v1/warranty-purchases/active
 * @desc    Get active warranty coverage summary grouped by item
 * @access  Private
 */
router.get(
  '/active',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const coverage = await WarrantyPurchasesService.getActiveCoverage(userId);

    sendSuccess(res, coverage);
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

    sendSuccess(res, warranties);
  })
);

/**
 * @route   GET /api/v1/warranty-purchases/quotes
 * @desc    Get extended warranty quotes for an item
 * @access  Private
 */
router.get(
  '/quotes',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const itemId = req.query.item_id as string;

    if (!itemId) {
      throw new AppError('item_id query parameter is required', 400);
    }

    // Validate UUID format
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(itemId)) {
      throw new AppError('item_id must be a valid UUID', 400);
    }

    // Look up the item with ownership check
    const result = await query(
      `SELECT id, name, category, price, purchase_date FROM items WHERE id = $1 AND user_id = $2`,
      [itemId, userId]
    );

    if (result.rows.length === 0) {
      throw new AppError('Item not found', 404);
    }

    const item = result.rows[0];
    const itemPrice = Number(item.price) || 0;

    // Calculate item age in years
    const purchaseDate = new Date(item.purchase_date);
    const now = new Date();
    const ageInYears = (now.getTime() - purchaseDate.getTime()) / (1000 * 60 * 60 * 24 * 365.25);

    // Generate warranty plans based on item price
    let plans = [
      { provider: 'HavenShield Basic', plan_name: '1 Year Protection', duration_months: 12, price: Math.round(itemPrice * 0.05 * 100) / 100, deductible: 75 },
      { provider: 'HavenShield Plus', plan_name: '2 Year Protection', duration_months: 24, price: Math.round(itemPrice * 0.08 * 100) / 100, deductible: 50 },
      { provider: 'HavenShield Premium', plan_name: '3 Year Protection', duration_months: 36, price: Math.round(itemPrice * 0.12 * 100) / 100, deductible: 0 },
    ];

    // Filter out longer plans if item is older than 5 years
    if (ageInYears > 5) {
      plans = plans.filter((p) => p.duration_months === 12);
    }

    sendSuccess(res, {
      quotes: plans,
      item: {
        id: item.id,
        name: item.name,
        category: item.category,
        price: itemPrice,
      },
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
  validate(uuidParamSchema, 'params'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const purchase = await WarrantyPurchasesService.getPurchaseById(req.params.id, userId);

    sendSuccess(res, purchase);
  })
);

/**
 * @route   POST /api/v1/warranty-purchases
 * @desc    Create a new warranty purchase
 * @access  Private
 */
router.post(
  '/',
  writeRateLimiter,
  validate(createWarrantyPurchaseSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const purchase = await WarrantyPurchasesService.createPurchase(userId, req.body);

    sendSuccess(res, purchase, { status: 201, message: 'Warranty purchase created successfully' });
  })
);

/**
 * @route   POST /api/v1/warranty-purchases/:id/cancel
 * @desc    Cancel a warranty purchase
 * @access  Private
 */
router.post(
  '/:id/cancel',
  validate(uuidParamSchema, 'params'),
  writeRateLimiter,
  validate(cancelWarrantyPurchaseSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const purchase = await WarrantyPurchasesService.cancelPurchase(
      req.params.id,
      userId,
      req.body.reason
    );

    sendSuccess(res, purchase, { message: 'Warranty purchase cancelled successfully' });
  })
);

export default router;
