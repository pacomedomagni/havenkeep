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
    remindersEnabled: joi_1.default.boolean(),
    firstReminderDays: joi_1.default.number().integer().min(1).max(365),
    reminderTime: joi_1.default.string().pattern(/^\d{2}:\d{2}$/).custom((value, helpers) => {
        const [hours, minutes] = value.split(':').map(Number);
        if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
            return helpers.error('any.invalid');
        }
        return value;
    }, 'valid time'),
    warrantyOffersEnabled: joi_1.default.boolean(),
    tipsEnabled: joi_1.default.boolean(),
    pushEnabled: joi_1.default.boolean(),
    emailEnabled: joi_1.default.boolean(),
}).min(1)
    // Accept snake_case from mobile clients
    .rename('reminders_enabled', 'remindersEnabled', { ignoreUndefined: true, override: false })
    .rename('first_reminder_days', 'firstReminderDays', { ignoreUndefined: true, override: false })
    .rename('reminder_time', 'reminderTime', { ignoreUndefined: true, override: false })
    .rename('warranty_offers_enabled', 'warrantyOffersEnabled', { ignoreUndefined: true, override: false })
    .rename('tips_enabled', 'tipsEnabled', { ignoreUndefined: true, override: false })
    .rename('push_enabled', 'pushEnabled', { ignoreUndefined: true, override: false })
    .rename('email_enabled', 'emailEnabled', { ignoreUndefined: true, override: false });
//# sourceMappingURL=notifications.validator.js.map