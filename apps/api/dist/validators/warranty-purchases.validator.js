"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getExpiringQuerySchema = exports.getPurchasesQuerySchema = exports.cancelWarrantyPurchaseSchema = exports.createWarrantyPurchaseSchema = void 0;
const joi_1 = __importDefault(require("joi"));
exports.createWarrantyPurchaseSchema = joi_1.default.object({
    item_id: joi_1.default.string().uuid().required(),
    provider: joi_1.default.string().max(100).required(),
    plan_name: joi_1.default.string().max(255).required(),
    external_policy_id: joi_1.default.string().max(255).optional(),
    duration_months: joi_1.default.number().integer().min(1).max(120).required(),
    starts_at: joi_1.default.date().iso().required(),
    coverage_details: joi_1.default.object().optional(),
    price: joi_1.default.number().min(0).max(1000000).required(),
    deductible: joi_1.default.number().min(0).max(1000000).optional().default(0),
    claim_limit: joi_1.default.number().min(0).max(1000000).optional(),
    commission_amount: joi_1.default.number().min(0).optional(),
    commission_rate: joi_1.default.number().min(0).max(1).optional(),
    stripe_payment_intent_id: joi_1.default.string().max(255).optional(),
});
exports.cancelWarrantyPurchaseSchema = joi_1.default.object({
    reason: joi_1.default.string().max(2000).optional(),
});
exports.getPurchasesQuerySchema = joi_1.default.object({
    limit: joi_1.default.number().integer().min(1).max(100).optional().default(50),
    offset: joi_1.default.number().integer().min(0).optional().default(0),
    item_id: joi_1.default.string().uuid().optional(),
    status: joi_1.default.string().valid('active', 'expired', 'cancelled', 'pending').optional(),
});
exports.getExpiringQuerySchema = joi_1.default.object({
    days: joi_1.default.number().integer().min(1).max(365).optional().default(30),
});
//# sourceMappingURL=warranty-purchases.validator.js.map