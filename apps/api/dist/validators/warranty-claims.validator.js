"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getClaimsQuerySchema = exports.updateWarrantyClaimSchema = exports.createWarrantyClaimSchema = void 0;
const joi_1 = __importDefault(require("joi"));
exports.createWarrantyClaimSchema = joi_1.default.object({
    item_id: joi_1.default.string().uuid().required(),
    claim_date: joi_1.default.date().iso().optional().max('now'),
    issue_description: joi_1.default.string().max(2000).optional(),
    repair_description: joi_1.default.string().max(2000).optional(),
    repair_cost: joi_1.default.number().min(0).max(1000000).required(),
    amount_saved: joi_1.default.number().min(0).max(1000000).required(),
    out_of_pocket: joi_1.default.number().min(0).max(1000000).optional(),
    status: joi_1.default.string().valid('pending', 'in_progress', 'completed', 'denied').optional(),
    filed_with: joi_1.default.string().max(100).optional(),
    claim_number: joi_1.default.string().max(100).optional(),
    notes: joi_1.default.string().max(5000).optional(),
});
exports.updateWarrantyClaimSchema = joi_1.default.object({
    claim_date: joi_1.default.date().iso().optional(),
    issue_description: joi_1.default.string().max(2000).optional().allow(null),
    repair_description: joi_1.default.string().max(2000).optional().allow(null),
    repair_cost: joi_1.default.number().min(0).max(1000000).optional(),
    amount_saved: joi_1.default.number().min(0).max(1000000).optional(),
    out_of_pocket: joi_1.default.number().min(0).max(1000000).optional().allow(null),
    status: joi_1.default.string().valid('pending', 'in_progress', 'completed', 'denied').optional(),
    filed_with: joi_1.default.string().max(100).optional().allow(null),
    claim_number: joi_1.default.string().max(100).optional().allow(null),
    notes: joi_1.default.string().max(5000).optional().allow(null),
}).min(1);
exports.getClaimsQuerySchema = joi_1.default.object({
    limit: joi_1.default.number().integer().min(1).max(100).optional().default(50),
    offset: joi_1.default.number().integer().min(0).optional().default(0),
    item_id: joi_1.default.string().uuid().optional(),
});
//# sourceMappingURL=warranty-claims.validator.js.map