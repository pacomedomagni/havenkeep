"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const validate_1 = require("../middleware/validate");
const warranty_purchases_service_1 = require("../services/warranty-purchases.service");
const warranty_purchases_validator_1 = require("../validators/warranty-purchases.validator");
const async_handler_1 = require("../utils/async-handler");
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
    const { limit, offset, item_id, status } = req.query;
    const result = await warranty_purchases_service_1.WarrantyPurchasesService.getUserPurchases(userId, {
        limit: Number(limit),
        offset: Number(offset),
        itemId: item_id,
        status: status,
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
}));
/**
 * @route   GET /api/v1/warranty-purchases/active
 * @desc    Get active warranty coverage summary grouped by item
 * @access  Private
 */
router.get('/active', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const coverage = await warranty_purchases_service_1.WarrantyPurchasesService.getActiveCoverage(userId);
    res.json({
        success: true,
        data: coverage,
    });
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
    res.json({
        success: true,
        data: warranties,
    });
}));
/**
 * @route   GET /api/v1/warranty-purchases/:id
 * @desc    Get a single warranty purchase by ID
 * @access  Private
 */
router.get('/:id', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const purchase = await warranty_purchases_service_1.WarrantyPurchasesService.getPurchaseById(req.params.id, userId);
    res.json({
        success: true,
        data: purchase,
    });
}));
/**
 * @route   POST /api/v1/warranty-purchases
 * @desc    Create a new warranty purchase
 * @access  Private
 */
router.post('/', (0, validate_1.validate)(warranty_purchases_validator_1.createWarrantyPurchaseSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const purchase = await warranty_purchases_service_1.WarrantyPurchasesService.createPurchase(userId, req.body);
    res.status(201).json({
        success: true,
        data: purchase,
        message: 'Warranty purchase created successfully',
    });
}));
/**
 * @route   POST /api/v1/warranty-purchases/:id/cancel
 * @desc    Cancel a warranty purchase
 * @access  Private
 */
router.post('/:id/cancel', (0, validate_1.validate)(warranty_purchases_validator_1.cancelWarrantyPurchaseSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const purchase = await warranty_purchases_service_1.WarrantyPurchasesService.cancelPurchase(req.params.id, userId, req.body.reason);
    res.json({
        success: true,
        data: purchase,
        message: 'Warranty purchase cancelled successfully',
    });
}));
exports.default = router;
//# sourceMappingURL=warranty-purchases.js.map