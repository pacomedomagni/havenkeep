import Joi from 'joi';

export const registerPartnerSchema = Joi.object({
  partner_type: Joi.string().valid('realtor', 'builder', 'property_manager', 'other').required(),
  company_name: Joi.string().max(255).optional(),
  phone: Joi.string().max(50).optional(),
  website: Joi.string().uri().max(255).optional(),
  brand_color: Joi.string().pattern(/^#[0-9A-F]{6}$/i).optional(),
  logo_url: Joi.string().uri().optional(),
  default_message: Joi.string().max(1000).optional(),
});

export const updatePartnerSchema = Joi.object({
  company_name: Joi.string().max(255).optional(),
  phone: Joi.string().max(50).optional(),
  website: Joi.string().uri().max(255).optional(),
  brand_color: Joi.string().pattern(/^#[0-9A-F]{6}$/i).optional(),
  logo_url: Joi.string().uri().optional(),
  default_message: Joi.string().max(1000).optional(),
  default_premium_months: Joi.number().integer().min(1).max(12).optional(),
}).min(1);

export const createGiftSchema = Joi.object({
  homebuyer_email: Joi.string().email().required(),
  homebuyer_name: Joi.string().max(255).required(),
  homebuyer_phone: Joi.string().max(50).optional(),
  home_address: Joi.string().max(500).optional(),
  closing_date: Joi.date().iso().optional(),
  premium_months: Joi.number().integer().min(1).max(12).optional(),
  custom_message: Joi.string().max(1000).optional(),
});

export const getGiftsQuerySchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).optional().default(50),
  offset: Joi.number().integer().min(0).optional().default(0),
  status: Joi.string().valid('created', 'sent', 'activated', 'expired').optional(),
});

export const getCommissionsQuerySchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).optional().default(50),
  offset: Joi.number().integer().min(0).optional().default(0),
});
