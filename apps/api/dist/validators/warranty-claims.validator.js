"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getClaimsQuerySchema = exports.updateWarrantyClaimSchema = exports.createWarrantyClaimSchema = void 0;
const joi_1 = __importDefault(require("joi"));
exports.createWarrantyClaimSchema = joi_1.default.object({
    itemId: joi_1.default.string().uuid().required(),
    claimDate: joi_1.default.date().iso().optional().max('now'),
    issueDescription: joi_1.default.string().max(2000).optional(),
    repairDescription: joi_1.default.string().max(2000).optional(),
    repairCost: joi_1.default.number().min(0).max(1000000).required(),
    amountSaved: joi_1.default.number().min(0).max(1000000).required(),
    outOfPocket: joi_1.default.number().min(0).max(1000000).optional(),
    status: joi_1.default.string().valid('pending', 'in_review', 'completed', 'denied', 'submitted', 'approved', 'cancelled').optional(),
    filedWith: joi_1.default.string().max(100).optional(),
    claimNumber: joi_1.default.string().max(100).optional(),
    notes: joi_1.default.string().max(5000).optional(),
})
    // Accept snake_case from mobile clients
    .rename('item_id', 'itemId', { ignoreUndefined: true, override: false })
    .rename('claim_date', 'claimDate', { ignoreUndefined: true, override: false })
    .rename('issue_description', 'issueDescription', { ignoreUndefined: true, override: false })
    .rename('repair_description', 'repairDescription', { ignoreUndefined: true, override: false })
    .rename('repair_cost', 'repairCost', { ignoreUndefined: true, override: false })
    .rename('amount_saved', 'amountSaved', { ignoreUndefined: true, override: false })
    .rename('out_of_pocket', 'outOfPocket', { ignoreUndefined: true, override: false })
    .rename('filed_with', 'filedWith', { ignoreUndefined: true, override: false })
    .rename('claim_number', 'claimNumber', { ignoreUndefined: true, override: false });
exports.updateWarrantyClaimSchema = joi_1.default.object({
    claimDate: joi_1.default.date().iso().optional(),
    issueDescription: joi_1.default.string().max(2000).optional().allow(null),
    repairDescription: joi_1.default.string().max(2000).optional().allow(null),
    repairCost: joi_1.default.number().min(0).max(1000000).optional(),
    amountSaved: joi_1.default.number().min(0).max(1000000).optional(),
    outOfPocket: joi_1.default.number().min(0).max(1000000).optional().allow(null),
    status: joi_1.default.string().valid('pending', 'in_review', 'completed', 'denied', 'submitted', 'approved', 'cancelled').optional(),
    filedWith: joi_1.default.string().max(100).optional().allow(null),
    claimNumber: joi_1.default.string().max(100).optional().allow(null),
    notes: joi_1.default.string().max(5000).optional().allow(null),
}).min(1)
    // Accept snake_case from mobile clients
    .rename('claim_date', 'claimDate', { ignoreUndefined: true, override: false })
    .rename('issue_description', 'issueDescription', { ignoreUndefined: true, override: false })
    .rename('repair_description', 'repairDescription', { ignoreUndefined: true, override: false })
    .rename('repair_cost', 'repairCost', { ignoreUndefined: true, override: false })
    .rename('amount_saved', 'amountSaved', { ignoreUndefined: true, override: false })
    .rename('out_of_pocket', 'outOfPocket', { ignoreUndefined: true, override: false })
    .rename('filed_with', 'filedWith', { ignoreUndefined: true, override: false })
    .rename('claim_number', 'claimNumber', { ignoreUndefined: true, override: false });
exports.getClaimsQuerySchema = joi_1.default.object({
    limit: joi_1.default.number().integer().min(1).max(100).optional().default(50),
    offset: joi_1.default.number().integer().min(0).optional().default(0),
    itemId: joi_1.default.string().uuid().optional(),
})
    .rename('item_id', 'itemId', { ignoreUndefined: true, override: false });
//# sourceMappingURL=warranty-claims.validator.js.map