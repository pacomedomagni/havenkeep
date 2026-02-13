"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const validate_1 = require("../middleware/validate");
const warranty_claims_service_1 = require("../services/warranty-claims.service");
const warranty_claims_validator_1 = require("../validators/warranty-claims.validator");
const async_handler_1 = require("../utils/async-handler");
const router = (0, express_1.Router)();
// All routes require authentication
router.use(auth_1.authenticate);
/**
 * @route   POST /api/v1/warranty-claims
 * @desc    Create a new warranty claim
 * @access  Private
 */
router.post('/', (0, validate_1.validate)(warranty_claims_validator_1.createWarrantyClaimSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const claim = await warranty_claims_service_1.WarrantyClaimsService.createClaim(userId, req.body);
    res.status(201).json({
        success: true,
        data: claim,
        message: 'Warranty claim created successfully',
    });
}));
/**
 * @route   GET /api/v1/warranty-claims
 * @desc    Get all warranty claims for authenticated user
 * @access  Private
 */
router.get('/', (0, validate_1.validate)(warranty_claims_validator_1.getClaimsQuerySchema, 'query'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const { limit, offset, item_id } = req.query;
    const result = await warranty_claims_service_1.WarrantyClaimsService.getUserClaims(userId, {
        limit: Number(limit),
        offset: Number(offset),
        itemId: item_id,
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
}));
/**
 * @route   GET /api/v1/warranty-claims/savings
 * @desc    Get total savings for user
 * @access  Private
 */
router.get('/savings', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const savings = await warranty_claims_service_1.WarrantyClaimsService.getTotalSavings(userId);
    res.json({
        success: true,
        data: savings,
    });
}));
/**
 * @route   GET /api/v1/warranty-claims/feed
 * @desc    Get public savings feed (social proof)
 * @access  Private
 */
router.get('/feed', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const limit = Math.min(Number(req.query.limit) || 20, 50);
    const feed = await warranty_claims_service_1.WarrantyClaimsService.getSavingsFeed(limit);
    res.json({
        success: true,
        data: feed,
    });
}));
/**
 * @route   GET /api/v1/warranty-claims/:id
 * @desc    Get warranty claim by ID
 * @access  Private
 */
router.get('/:id', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const claim = await warranty_claims_service_1.WarrantyClaimsService.getClaimById(req.params.id, userId);
    res.json({
        success: true,
        data: claim,
    });
}));
/**
 * @route   PUT /api/v1/warranty-claims/:id
 * @desc    Update warranty claim
 * @access  Private
 */
router.put('/:id', (0, validate_1.validate)(warranty_claims_validator_1.updateWarrantyClaimSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const claim = await warranty_claims_service_1.WarrantyClaimsService.updateClaim(req.params.id, userId, req.body);
    res.json({
        success: true,
        data: claim,
        message: 'Warranty claim updated successfully',
    });
}));
/**
 * @route   DELETE /api/v1/warranty-claims/:id
 * @desc    Delete warranty claim
 * @access  Private
 */
router.delete('/:id', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    await warranty_claims_service_1.WarrantyClaimsService.deleteClaim(req.params.id, userId);
    res.json({
        success: true,
        message: 'Warranty claim deleted successfully',
    });
}));
exports.default = router;
//# sourceMappingURL=warranty-claims.js.map