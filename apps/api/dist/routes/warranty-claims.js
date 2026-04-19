"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const validate_1 = require("../middleware/validate");
const validators_1 = require("../validators");
const warranty_claims_service_1 = require("../services/warranty-claims.service");
const warranty_claims_validator_1 = require("../validators/warranty-claims.validator");
const async_handler_1 = require("../utils/async-handler");
const rateLimiter_1 = require("../middleware/rateLimiter");
const response_1 = require("../utils/response");
const router = (0, express_1.Router)();
// All routes require authentication
router.use(auth_1.authenticate);
/**
 * @route   POST /api/v1/warranty-claims
 * @desc    Create a new warranty claim
 * @access  Private
 */
router.post('/', rateLimiter_1.writeRateLimiter, (0, validate_1.validate)(warranty_claims_validator_1.createWarrantyClaimSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const claim = await warranty_claims_service_1.WarrantyClaimsService.createClaim(userId, req.body);
    (0, response_1.sendSuccess)(res, claim, { status: 201, message: 'Warranty claim created successfully' });
}));
/**
 * @route   GET /api/v1/warranty-claims
 * @desc    Get all warranty claims for authenticated user
 * @access  Private
 */
router.get('/', (0, validate_1.validate)(warranty_claims_validator_1.getClaimsQuerySchema, 'query'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const { itemId } = req.query;
    // BE-1/2/3: Explicitly convert and clamp pagination params to safe integers
    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 50));
    const offset = (page - 1) * limit;
    const result = await warranty_claims_service_1.WarrantyClaimsService.getUserClaims(userId, {
        limit,
        offset,
        itemId: itemId,
    });
    (0, response_1.sendSuccess)(res, result.claims, {
        pagination: {
            page,
            limit,
            total: result.total,
            total_pages: Math.ceil(result.total / limit),
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
    (0, response_1.sendSuccess)(res, savings);
}));
/**
 * @route   GET /api/v1/warranty-claims/feed
 * @desc    Get public savings feed (social proof)
 * @access  Private
 */
router.get('/feed', (0, async_handler_1.asyncHandler)(async (req, res) => {
    const limit = Math.min(Number(req.query.limit) || 20, 50);
    const feed = await warranty_claims_service_1.WarrantyClaimsService.getSavingsFeed(limit);
    (0, response_1.sendSuccess)(res, feed);
}));
/**
 * @route   GET /api/v1/warranty-claims/:id
 * @desc    Get warranty claim by ID
 * @access  Private
 */
router.get('/:id', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const claim = await warranty_claims_service_1.WarrantyClaimsService.getClaimById(req.params.id, userId);
    (0, response_1.sendSuccess)(res, claim);
}));
/**
 * @route   PUT /api/v1/warranty-claims/:id
 * @desc    Update warranty claim
 * @access  Private
 */
router.put('/:id', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), rateLimiter_1.writeRateLimiter, (0, validate_1.validate)(warranty_claims_validator_1.updateWarrantyClaimSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    const claim = await warranty_claims_service_1.WarrantyClaimsService.updateClaim(req.params.id, userId, req.body);
    (0, response_1.sendSuccess)(res, claim, { message: 'Warranty claim updated successfully' });
}));
/**
 * @route   DELETE /api/v1/warranty-claims/:id
 * @desc    Delete warranty claim
 * @access  Private
 */
router.delete('/:id', (0, validate_1.validate)(validators_1.uuidParamSchema, 'params'), rateLimiter_1.writeRateLimiter, (0, async_handler_1.asyncHandler)(async (req, res) => {
    const userId = req.user.id;
    await warranty_claims_service_1.WarrantyClaimsService.deleteClaim(req.params.id, userId);
    (0, response_1.sendMessage)(res, 'Warranty claim deleted successfully');
}));
exports.default = router;
//# sourceMappingURL=warranty-claims.js.map