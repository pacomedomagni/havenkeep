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
    'furniture',
    'air_purifier', 'vacuum', 'ceiling_fan', 'smoke_detector',
    'security_system', 'garage_door_opener', 'power_tools', 'lawn_mower',
    'pool_equipment', 'grill', 'coffee_maker', 'home_theater',
    'printer', 'networking', 'camera', 'lighting',
    'dehumidifier', 'freezer', 'wine_cooler', 'trash_compactor',
    'other',
];
exports.getCategoryParamsSchema = joi_1.default.object({
    category: joi_1.default.string().valid(...validCategories).required(),
});
exports.getItemDueParamsSchema = joi_1.default.object({
    itemId: joi_1.default.string().uuid().required(),
})
    .rename('item_id', 'itemId', { ignoreUndefined: true, override: false });
exports.logMaintenanceSchema = joi_1.default.object({
    itemId: joi_1.default.string().uuid().required(),
    scheduleId: joi_1.default.string().uuid().optional().allow(null),
    taskName: joi_1.default.string().max(255).required(),
    completedDate: joi_1.default.date().iso().optional().max('now'),
    notes: joi_1.default.string().max(5000).optional().allow(null),
    durationMinutes: joi_1.default.number().integer().min(0).max(10000).optional().allow(null),
    cost: joi_1.default.number().min(0).max(1000000).optional(),
})
    // Accept snake_case from mobile clients
    .rename('item_id', 'itemId', { ignoreUndefined: true, override: false })
    .rename('schedule_id', 'scheduleId', { ignoreUndefined: true, override: false })
    .rename('task_name', 'taskName', { ignoreUndefined: true, override: false })
    .rename('completed_date', 'completedDate', { ignoreUndefined: true, override: false })
    .rename('duration_minutes', 'durationMinutes', { ignoreUndefined: true, override: false });
exports.getHistoryQuerySchema = joi_1.default.object({
    limit: joi_1.default.number().integer().min(1).max(100).optional().default(50),
    offset: joi_1.default.number().integer().min(0).optional().default(0),
    itemId: joi_1.default.string().uuid().optional(),
})
    .rename('item_id', 'itemId', { ignoreUndefined: true, override: false });
//# sourceMappingURL=maintenance.validator.js.map