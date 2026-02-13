"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getHistoryQuerySchema = exports.logMaintenanceSchema = exports.getItemDueParamsSchema = exports.getCategoryParamsSchema = void 0;
const joi_1 = __importDefault(require("joi"));
const validCategories = [
    'refrigerator', 'dishwasher', 'washer', 'dryer',
    'oven_range', 'microwave', 'garbage_disposal', 'range_hood',
    'hvac', 'water_heater', 'furnace', 'water_softener', 'sump_pump',
    'tv', 'computer', 'smart_home',
    'roofing', 'windows', 'doors', 'flooring',
    'plumbing', 'electrical',
    'furniture', 'other',
];
exports.getCategoryParamsSchema = joi_1.default.object({
    category: joi_1.default.string().valid(...validCategories).required(),
});
exports.getItemDueParamsSchema = joi_1.default.object({
    itemId: joi_1.default.string().uuid().required(),
});
exports.logMaintenanceSchema = joi_1.default.object({
    item_id: joi_1.default.string().uuid().required(),
    schedule_id: joi_1.default.string().uuid().optional().allow(null),
    task_name: joi_1.default.string().max(255).required(),
    completed_date: joi_1.default.date().iso().optional().max('now'),
    notes: joi_1.default.string().max(5000).optional().allow(null),
    duration_minutes: joi_1.default.number().integer().min(0).max(10000).optional().allow(null),
    cost: joi_1.default.number().min(0).max(1000000).optional(),
});
exports.getHistoryQuerySchema = joi_1.default.object({
    limit: joi_1.default.number().integer().min(1).max(100).optional().default(50),
    offset: joi_1.default.number().integer().min(0).optional().default(0),
    item_id: joi_1.default.string().uuid().optional(),
});
//# sourceMappingURL=maintenance.validator.js.map