import Joi from 'joi';

const notificationTypes = [
  'warranty_expiring',
  'maintenance_due',
  'claim_update',
  'gift_received',
  'gift_activated',
  'system',
  'promotional',
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
