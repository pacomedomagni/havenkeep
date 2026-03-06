import Joi from 'joi';

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

export const getCategoryParamsSchema = Joi.object({
  category: Joi.string().valid(...validCategories).required(),
});

export const getItemDueParamsSchema = Joi.object({
  itemId: Joi.string().uuid().required(),
})
  .rename('item_id', 'itemId', { ignoreUndefined: true, override: false });

export const logMaintenanceSchema = Joi.object({
  itemId: Joi.string().uuid().required(),
  scheduleId: Joi.string().uuid().optional().allow(null),
  taskName: Joi.string().max(255).required(),
  completedDate: Joi.date().iso().optional().max('now'),
  notes: Joi.string().max(5000).optional().allow(null),
  durationMinutes: Joi.number().integer().min(0).max(10000).optional().allow(null),
  cost: Joi.number().min(0).max(1000000).optional(),
})
  // Accept snake_case from mobile clients
  .rename('item_id', 'itemId', { ignoreUndefined: true, override: false })
  .rename('schedule_id', 'scheduleId', { ignoreUndefined: true, override: false })
  .rename('task_name', 'taskName', { ignoreUndefined: true, override: false })
  .rename('completed_date', 'completedDate', { ignoreUndefined: true, override: false })
  .rename('duration_minutes', 'durationMinutes', { ignoreUndefined: true, override: false });

export const getHistoryQuerySchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).optional().default(50),
  offset: Joi.number().integer().min(0).optional().default(0),
  itemId: Joi.string().uuid().optional(),
})
  .rename('item_id', 'itemId', { ignoreUndefined: true, override: false });
