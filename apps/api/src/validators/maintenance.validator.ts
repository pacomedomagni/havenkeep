import Joi from 'joi';

const validCategories = [
  'refrigerator', 'dishwasher', 'washer', 'dryer',
  'oven_range', 'microwave', 'garbage_disposal', 'range_hood',
  'hvac', 'water_heater', 'furnace', 'water_softener', 'sump_pump',
  'tv', 'computer', 'smart_home',
  'roofing', 'windows', 'doors', 'flooring',
  'plumbing', 'electrical',
  'furniture', 'other',
];

export const getCategoryParamsSchema = Joi.object({
  category: Joi.string().valid(...validCategories).required(),
});

export const getItemDueParamsSchema = Joi.object({
  itemId: Joi.string().uuid().required(),
});

export const logMaintenanceSchema = Joi.object({
  item_id: Joi.string().uuid().required(),
  schedule_id: Joi.string().uuid().optional().allow(null),
  task_name: Joi.string().max(255).required(),
  completed_date: Joi.date().iso().optional().max('now'),
  notes: Joi.string().max(5000).optional().allow(null),
  duration_minutes: Joi.number().integer().min(0).max(10000).optional().allow(null),
  cost: Joi.number().min(0).max(1000000).optional(),
});

export const getHistoryQuerySchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).optional().default(50),
  offset: Joi.number().integer().min(0).optional().default(0),
  item_id: Joi.string().uuid().optional(),
});
