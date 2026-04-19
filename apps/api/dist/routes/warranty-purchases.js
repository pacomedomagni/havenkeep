"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const validate_1 = require("../middleware/validate");
const validators_1 = require("../validators");
const warranty_purchases_service_1 = require("../services/warranty-purchases.service");
const warranty_purchases_validator_1 = require("../validators/warranty-purchases.validator");
const async_handler_1 = require("../utils/async-handler");
const db_1 = require("../db");
const errors_1 = require("../utils/errors");
const rateLimiter_1 = require("../middleware/rateLimiter");
const response_1 = require("../utils/response");
const router = (0, express_1.Router)();
// All routes require authentication
router.use(auth_1.authenticate);
/**
 * @route   GET /api/v1/warranty-purchases
 * @desc    Get user's warranty purchases with pagination and optional filters
 * @access  Private
 */
router.get('/', (0, validate_1.validate)(warranty_purchases_validator_1.getPurchasesQuerySchema, 'query'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const { itemId, status } = req.query;
    // BE-1/2/3: Explicitly convert and clamp pagination params to safe integers
    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 50));
    const offset = (page - 1) * limit;
    const result = await warranty_purchases_service_1.WarrantyPurchasesService.getUserPurchases(userId, {
        limit,
        offset,
        itemId: itemId,
        status: status,
    });
    (0, response_1.sendSuccess)(res, result.purchases, {
        pagination: {
            page,
            limit,
            total: result.total,
            total_pages: Math.ceil(result.total / limit),
        },
    });
}));
/**
 * @route   GET /api/v1/warranty-purchases/active
 * @desc    Get active warranty coverage summary grouped by item
 * @access  Private
 */
router.get('/active', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const coverage = await warranty_purchases_service_1.WarrantyPurchasesService.getActiveCoverage(userId);
    (0, response_1.sendSuccess)(res, coverage);
}));
/**
 * @route   GET /api/v1/warranty-purchases/expiring
 * @desc    Get warranties expiring within N days
 * @access  Private
 */
router.get('/expiring', (0, validate_1.validate)(warranty_purchases_validator_1.getExpiringQuerySchema, 'query'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const days = Number(req.query.days) || 30;
    const warranties = await warranty_purchases_service_1.WarrantyPurchasesService.getExpiringWarranties(userId, days);
    (0, response_1.sendSuccess)(res, warranties);
}));
/**
 * @route   GET /api/v1/warranty-purchases/quotes
 * @desc    Get extended warranty quotes for an item
 * @access  Private
 */
router.get('/quotes', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const itemId = req.query.item_id;
    if (!itemId) {
        throw new errors_1.AppError('item_id query parameter is required', 400);
    }
    // Validate UUID format
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(itemId)) {
        throw new errors_1.AppError('item_id must be a valid UUID', 400);
    }
    // Look up the item with ownership check
    const result = await (0, db_1.query)(`SELECT id, name, category, price, purchase_date FROM items WHERE id = $1 AND user_id = $2`, [itemId, userId]);
    if (result.rows.length === 0) {
        throw new errors_1.AppError('Item not found', 404);
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
    (0, response_1.sendSuccess)(res, {
        quotes: plans,
        item: {
            id: item.id,
            name: item.name,
            category: item.category,
            price: itemPrice,
        },
    });
}));
/**
 * @route   GET /api/v1/warranty-purchases/:id
 * @desc    Get a single warranty purchase by ID
 * @access  Private
 */
router.get('/:id', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const purchase = await warranty_purchases_service_1.WarrantyPurchasesService.getPurchaseById(req.params.id, userId);
    (0, response_1.sendSuccess)(res, purchase);
}));
/**
 * @route   POST /api/v1/warranty-purchases
 * @desc    Create a new warranty purchase
 * @access  Private
 */
router.post('/', rateLimiter_1.writeRateLimiter, (0, validate_1.validate)(warranty_purchases_validator_1.createWarrantyPurchaseSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const purchase = await warranty_purchases_service_1.WarrantyPurchasesService.createPurchase(userId, req.body);
    (0, response_1.sendSuccess)(res, purchase, { status: 201, message: 'Warranty purchase created successfully' });
}));
/**
 * @route   POST /api/v1/warranty-purchases/:id/cancel
 * @desc    Cancel a warranty purchase
 * @access  Private
 */
router.post('/:id/cancel', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), rateLimiter_1.writeRateLimiter, (0, validate_1.validate)(warranty_purchases_validator_1.cancelWarrantyPurchaseSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const purchase = await warranty_purchases_service_1.WarrantyPurchasesService.cancelPurchase(req.params.id, userId, req.body.reason);
    (0, response_1.sendSuccess)(res, purchase, { message: 'Warranty purchase cancelled successfully' });
}));
exports.default = router;
//# sourceMappingURL=warranty-purchases.js.map