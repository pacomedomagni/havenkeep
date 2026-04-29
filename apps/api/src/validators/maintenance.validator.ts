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
  // Ch08-MaintenanceLog-D030: completed_date is required on the Dart side
  // so make Joi match. The DB column has DEFAULT CURRENT_DATE but every
  // history entry should carry an explicit completion timestamp from the
  // client so audit logs reflect "when the user said it was done", not
  // "when the row landed in Postgres".
  completedDate: Joi.date().iso().max('now').required(),
  notes: Joi.string().max(5000).optional().allow(null),
  durationMinutes: Joi.number().integer().min(0).max(10000).optional().allow(null),
  // F032: align with items.price ceiling so a maintenance cost can't exceed
  // the most expensive item we accept ($999,999.99). The previous $1M flat
  // ceiling was implausible for a single repair.
  // Ch08-MaintenanceLog-D031: tri-state cost (null = unknown, 0 = explicit
  // zero, >0 = real cost). `.allow(null)` keeps "unknown" first-class.
  cost: Joi.number().min(0).max(999999.99).optional().allow(null),
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
  homeId: Joi.string().uuid().optional(),
  page: Joi.number().integer().min(1).optional(),
})
  .rename('item_id', 'itemId', { ignoreUndefined: true, override: false })
  .rename('home_id', 'homeId', { ignoreUndefined: true, override: false });

// 2.13: GET /due accepts an optional home_id query so the dashboard
// summary scopes to the user's currently-selected home.
export const getDueQuerySchema = Joi.object({
  homeId: Joi.string().uuid().optional(),
})
  .rename('home_id', 'homeId', { ignoreUndefined: true, override: false });
