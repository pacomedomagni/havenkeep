import Joi from 'joi';

// Auth Validators
export const registerSchema = Joi.object({
  email: Joi.string().email().required().max(255),
  password: Joi.string()
    .min(8)
    .max(128)
    .pattern(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]/)
    .required()
    .messages({
      'string.pattern.base': 'Password must contain at least one uppercase letter, one lowercase letter, one number, and one special character',
      'string.min': 'Password must be at least 8 characters long',
    }),
  fullName: Joi.string().min(1).max(255).required(),
});

export const loginSchema = Joi.object({
  email: Joi.string().email().required(),
  password: Joi.string().required(),
});

export const refreshTokenSchema = Joi.object({
  refreshToken: Joi.string().required(),
});

// Item Validators
export const createItemSchema = Joi.object({
  homeId: Joi.string().uuid().required(),
  name: Joi.string().min(1).max(255).required(),
  brand: Joi.string().max(100).allow(null, ''),
  modelNumber: Joi.string().max(100).allow(null, ''),
  serialNumber: Joi.string().max(100).allow(null, ''),
  category: Joi.string().valid(
    'refrigerator', 'dishwasher', 'washer', 'dryer',
    'oven_range', 'microwave', 'garbage_disposal', 'range_hood',
    'hvac', 'water_heater', 'furnace', 'water_softener', 'sump_pump',
    'tv', 'computer', 'smart_home',
    'roofing', 'windows', 'doors', 'flooring',
    'plumbing', 'electrical',
    'furniture', 'other'
  ).default('other'),
  room: Joi.string().valid(
    'kitchen', 'bathroom', 'master_bedroom', 'bedroom',
    'living_room', 'dining_room', 'laundry',
    'garage', 'basement', 'attic',
    'outdoor', 'hvac_utility', 'office', 'other'
  ).allow(null),
  purchaseDate: Joi.date().max('now').required(),
  store: Joi.string().max(100).allow(null, ''),
  price: Joi.number().min(0).max(999999.99).allow(null),
  warrantyMonths: Joi.number().integer().min(0).max(600).default(12),
  warrantyType: Joi.string().valid('manufacturer', 'extended', 'store', 'home_warranty').default('manufacturer'),
  warrantyProvider: Joi.string().max(100).allow(null, ''),
  notes: Joi.string().max(5000).allow(null, ''),
  productImageUrl: Joi.string().uri().max(500).allow(null, ''),
  barcode: Joi.string().max(100).allow(null, ''),
});

export const updateItemSchema = Joi.object({
  name: Joi.string().min(1).max(255),
  brand: Joi.string().max(100).allow(null, ''),
  modelNumber: Joi.string().max(100).allow(null, ''),
  serialNumber: Joi.string().max(100).allow(null, ''),
  category: Joi.string().valid(
    'refrigerator', 'dishwasher', 'washer', 'dryer',
    'oven_range', 'microwave', 'garbage_disposal', 'range_hood',
    'hvac', 'water_heater', 'furnace', 'water_softener', 'sump_pump',
    'tv', 'computer', 'smart_home',
    'roofing', 'windows', 'doors', 'flooring',
    'plumbing', 'electrical',
    'furniture', 'other'
  ),
  room: Joi.string().valid(
    'kitchen', 'bathroom', 'master_bedroom', 'bedroom',
    'living_room', 'dining_room', 'laundry',
    'garage', 'basement', 'attic',
    'outdoor', 'hvac_utility', 'office', 'other'
  ).allow(null),
  purchaseDate: Joi.date().max('now'),
  store: Joi.string().max(100).allow(null, ''),
  price: Joi.number().min(0).max(999999.99).allow(null),
  warrantyMonths: Joi.number().integer().min(0).max(600),
  warrantyType: Joi.string().valid('manufacturer', 'extended', 'store', 'home_warranty'),
  warrantyProvider: Joi.string().max(100).allow(null, ''),
  notes: Joi.string().max(5000).allow(null, ''),
  isArchived: Joi.boolean(),
  productImageUrl: Joi.string().uri().max(500).allow(null, ''),
  barcode: Joi.string().max(100).allow(null, ''),
}).min(1); // At least one field must be provided

// Home Validators
export const createHomeSchema = Joi.object({
  name: Joi.string().min(1).max(255).required(),
  address: Joi.string().max(500).allow(null, ''),
  city: Joi.string().max(100).allow(null, ''),
  state: Joi.string().max(50).allow(null, ''),
  zip: Joi.string().max(20).allow(null, ''),
  homeType: Joi.string().valid('house', 'condo', 'apartment', 'townhouse', 'other').default('house'),
  moveInDate: Joi.date().max('now').allow(null),
});

export const updateHomeSchema = Joi.object({
  name: Joi.string().min(1).max(255),
  address: Joi.string().max(500).allow(null, ''),
  city: Joi.string().max(100).allow(null, ''),
  state: Joi.string().max(50).allow(null, ''),
  zip: Joi.string().max(20).allow(null, ''),
  homeType: Joi.string().valid('house', 'condo', 'apartment', 'townhouse', 'other'),
  moveInDate: Joi.date().max('now').allow(null),
}).min(1);

// User Validators
export const updateUserSchema = Joi.object({
  fullName: Joi.string().min(1).max(255),
  avatarUrl: Joi.string().uri().max(500).allow(null, ''),
}).min(1);

// Document Validators
export const uploadDocumentSchema = Joi.object({
  itemId: Joi.string().uuid().required(),
  type: Joi.string().valid('receipt', 'warranty_card', 'manual', 'invoice', 'other').default('other'),
});

// Query Validators
export const paginationSchema = Joi.object({
  page: Joi.number().integer().min(1).default(1),
  limit: Joi.number().integer().min(1).max(100).default(20),
  homeId: Joi.string().uuid(),
  archived: Joi.string().valid('true', 'false'),
});

export const uuidParamSchema = Joi.object({
  id: Joi.string().uuid().required(),
});
