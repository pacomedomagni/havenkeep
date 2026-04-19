"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getExpiringQuerySchema = exports.getPurchasesQuerySchema = exports.cancelWarrantyPurchaseSchema = exports.createWarrantyPurchaseSchema = void 0;
const joi_1 = __importDefault(require("joi"));
exports.createWarrantyPurchaseSchema = joi_1.default.object({
    itemId: joi_1.default.string().uuid().required(),
    provider: joi_1.default.string().max(100).required(),
    planName: joi_1.default.string().max(255).required(),
    externalPolicyId: joi_1.default.string().max(255).optional(),
    durationMonths: joi_1.default.number().integer().min(1).max(240).required(),
    startsAt: joi_1.default.date().iso().required(),
    coverageDetails: joi_1.default.object().optional(),
    price: joi_1.default.number().min(0).max(1000000).required(),
    deductible: joi_1.default.number().min(0).max(1000000).optional().default(0),
    claimLimit: joi_1.default.number().min(0).max(1000000).optional(),
    commissionAmount: joi_1.default.number().min(0).optional(),
    commissionRate: joi_1.default.number().min(0).max(1).optional(),
    stripePaymentIntentId: joi_1.default.string().max(255).optional(),
})
    // Accept snake_case from mobile clients
    .rename('item_id', 'itemId', { ignoreUndefined: true, override: false })
    .rename('plan_name', 'planName', { ignoreUndefined: true, override: false })
    .rename('external_policy_id', 'externalPolicyId', { ignoreUndefined: true, override: false })
    .rename('duration_months', 'durationMonths', { ignoreUndefined: true, override: false })
    .rename('starts_at', 'startsAt', { ignoreUndefined: true, override: false })
    .rename('coverage_details', 'coverageDetails', { ignoreUndefined: true, override: false })
    .rename('claim_limit', 'claimLimit', { ignoreUndefined: true, override: false })
    .rename('commission_amount', 'commissionAmount', { ignoreUndefined: true, override: false })
    .rename('commission_rate', 'commissionRate', { ignoreUndefined: true, override: false })
    .rename('stripe_payment_intent_id', 'stripePaymentIntentId', { ignoreUndefined: true, override: false });
exports.cancelWarrantyPurchaseSchema = joi_1.default.object({
    reason: joi_1.default.string().max(2000).optional(),
});
exports.getPurchasesQuerySchema = joi_1.default.object({
    limit: joi_1.default.number().integer().min(1).max(100).optional().default(50),
    offset: joi_1.default.number().integer().min(0).optional().default(0),
    itemId: joi_1.default.string().uuid().optional(),
    status: joi_1.default.string().valid('active', 'expired', 'cancelled', 'pending', 'claimed').optional(),
})
    .rename('item_id', 'itemId', { ignoreUndefined: true, override: false });
exports.getExpiringQuerySchema = joi_1.default.object({
    days: joi_1.default.number().integer().min(1).max(365).optional().default(30),
});
//# sourceMappingURL=warranty-purchases.validator.js.map