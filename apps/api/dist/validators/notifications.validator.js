"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.updatePreferencesSchema = exports.notificationParamsSchema = exports.recordActionSchema = exports.getNotificationsQuerySchema = void 0;
const joi_1 = __importDefault(require("joi"));
const notificationTypes = [
    'warranty_expiring',
    'warranty_expired',
    'item_added',
    'warranty_extended',
    'maintenance_due',
    'claim_update',
    'claim_opportunity',
    'health_score_update',
    'gift_received',
    'gift_activated',
    'partner_commission',
    'promotional',
    'tip',
    'system',
];
exports.getNotificationsQuerySchema = joi_1.default.object({
    limit: joi_1.default.number().integer().min(1).max(100).optional().default(50),
    offset: joi_1.default.number().integer().min(0).optional().default(0),
    type: joi_1.default.string().valid(...notificationTypes).optional(),
    unread: joi_1.default.boolean().optional(),
});
exports.recordActionSchema = joi_1.default.object({
    action: joi_1.default.string().max(100).required(),
});
exports.notificationParamsSchema = joi_1.default.object({
    id: joi_1.default.string().uuid().required(),
});
exports.updatePreferencesSchema = joi_1.default.object({
    reminders_enabled: joi_1.default.boolean(),
    first_reminder_days: joi_1.default.number().integer().min(1).max(365),
    reminder_time: joi_1.default.string().pattern(/^\d{2}:\d{2}$/).custom((value, helpers) => {
        const [hours, minutes] = value.split(':').map(Number);
        if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
            return helpers.error('any.invalid');
        }
        return value;
    }, 'valid time'),
    warranty_offers_enabled: joi_1.default.boolean(),
    tips_enabled: joi_1.default.boolean(),
    push_enabled: joi_1.default.boolean(),
    email_enabled: joi_1.default.boolean(),
}).min(1);
//# sourceMappingURL=notifications.validator.js.map