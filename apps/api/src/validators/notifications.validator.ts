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
  page: Joi.number().integer().min(1).optional(),
  type: Joi.string().valid(...notificationTypes).optional(),
  unread: Joi.boolean().optional(),
  homeId: Joi.string().uuid().optional(),
})
  .rename('home_id', 'homeId', { ignoreUndefined: true, override: false });

export const recordActionSchema = Joi.object({
  action: Joi.string().max(100).required(),
});

export const notificationParamsSchema = Joi.object({
  id: Joi.string().uuid().required(),
});

export const updatePreferencesSchema = Joi.object({
  remindersEnabled: Joi.boolean(),
  firstReminderDays: Joi.number().integer().min(1).max(365),
  reminderTime: Joi.string().pattern(/^\d{2}:\d{2}$/).custom((value, helpers) => {
    const [hours, minutes] = value.split(':').map(Number);
    if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
      return helpers.error('any.invalid');
    }
    return value;
  }, 'valid time'),
  warrantyOffersEnabled: Joi.boolean(),
  tipsEnabled: Joi.boolean(),
  pushEnabled: Joi.boolean(),
  emailEnabled: Joi.boolean(),
}).min(1)
  // Accept snake_case from mobile clients
  .rename('reminders_enabled', 'remindersEnabled', { ignoreUndefined: true, override: false })
  .rename('first_reminder_days', 'firstReminderDays', { ignoreUndefined: true, override: false })
  .rename('reminder_time', 'reminderTime', { ignoreUndefined: true, override: false })
  .rename('warranty_offers_enabled', 'warrantyOffersEnabled', { ignoreUndefined: true, override: false })
  .rename('tips_enabled', 'tipsEnabled', { ignoreUndefined: true, override: false })
  .rename('push_enabled', 'pushEnabled', { ignoreUndefined: true, override: false })
  .rename('email_enabled', 'emailEnabled', { ignoreUndefined: true, override: false });
