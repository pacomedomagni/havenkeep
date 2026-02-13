import Joi from 'joi';

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

export const getNotificationsQuerySchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).optional().default(50),
  offset: Joi.number().integer().min(0).optional().default(0),
  type: Joi.string().valid(...notificationTypes).optional(),
  unread: Joi.boolean().optional(),
});

export const recordActionSchema = Joi.object({
  action: Joi.string().max(100).required(),
});

export const notificationParamsSchema = Joi.object({
  id: Joi.string().uuid().required(),
});

export const updatePreferencesSchema = Joi.object({
  reminders_enabled: Joi.boolean(),
  first_reminder_days: Joi.number().integer().min(1).max(365),
  reminder_time: Joi.string().pattern(/^\d{2}:\d{2}$/).custom((value, helpers) => {
    const [hours, minutes] = value.split(':').map(Number);
    if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
      return helpers.error('any.invalid');
    }
    return value;
  }, 'valid time'),
  warranty_offers_enabled: Joi.boolean(),
  tips_enabled: Joi.boolean(),
  push_enabled: Joi.boolean(),
  email_enabled: Joi.boolean(),
}).min(1);
