import Joi from 'joi';

export const registerPartnerSchema = Joi.object({
  partner_type: Joi.string().valid('realtor', 'builder', 'property_manager', 'other').required(),
  company_name: Joi.string().max(255).optional(),
  phone: Joi.string().max(50).optional(),
  website: Joi.string().uri().max(255).optional(),
  brand_color: Joi.string().pattern(/^#[0-9A-F]{6}$/i).optional(),
  logo_url: Joi.string().uri().optional(),
  default_message: Joi.string().max(1000).optional(),
  service_areas: Joi.array().items(Joi.string().max(100)).optional(),
})
  // Accept camelCase from dashboard clients
  .rename('partnerType', 'partner_type', { ignoreUndefined: true, override: false })
  .rename('companyName', 'company_name', { ignoreUndefined: true, override: false })
  .rename('brandColor', 'brand_color', { ignoreUndefined: true, override: false })
  .rename('logoUrl', 'logo_url', { ignoreUndefined: true, override: false })
  .rename('defaultMessage', 'default_message', { ignoreUndefined: true, override: false })
  .rename('serviceAreas', 'service_areas', { ignoreUndefined: true, override: false });

export const updatePartnerSchema = Joi.object({
  company_name: Joi.string().max(255).optional(),
  phone: Joi.string().max(50).optional(),
  website: Joi.string().uri().max(255).optional(),
  brand_color: Joi.string().pattern(/^#[0-9A-F]{6}$/i).optional(),
  logo_url: Joi.string().uri().optional(),
  default_message: Joi.string().max(1000).optional(),
  default_premium_months: Joi.number().integer().min(1).max(12).optional(),
  service_areas: Joi.array().items(Joi.string().max(100)).optional(),
}).min(1)
  // Accept camelCase from dashboard clients
  .rename('companyName', 'company_name', { ignoreUndefined: true, override: false })
  .rename('brandColor', 'brand_color', { ignoreUndefined: true, override: false })
  .rename('logoUrl', 'logo_url', { ignoreUndefined: true, override: false })
  .rename('defaultMessage', 'default_message', { ignoreUndefined: true, override: false })
  .rename('defaultPremiumMonths', 'default_premium_months', { ignoreUndefined: true, override: false })
  .rename('serviceAreas', 'service_areas', { ignoreUndefined: true, override: false });

export const createGiftSchema = Joi.object({
  homebuyer_email: Joi.string().email().required(),
  homebuyer_name: Joi.string().max(255).required(),
  homebuyer_phone: Joi.string().max(50).optional(),
  home_address: Joi.string().max(500).optional(),
  closing_date: Joi.date().iso().optional(),
  premium_months: Joi.number().integer().min(1).max(12).optional(),
  custom_message: Joi.string().max(1000).optional(),
})
  // Accept camelCase from dashboard clients
  .rename('homebuyerEmail', 'homebuyer_email', { ignoreUndefined: true, override: false })
  .rename('homebuyerName', 'homebuyer_name', { ignoreUndefined: true, override: false })
  .rename('homebuyerPhone', 'homebuyer_phone', { ignoreUndefined: true, override: false })
  .rename('homeAddress', 'home_address', { ignoreUndefined: true, override: false })
  .rename('closingDate', 'closing_date', { ignoreUndefined: true, override: false })
  .rename('premiumMonths', 'premium_months', { ignoreUndefined: true, override: false })
  .rename('customMessage', 'custom_message', { ignoreUndefined: true, override: false });

export const getGiftsQuerySchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).optional().default(50),
  offset: Joi.number().integer().min(0).optional().default(0),
  status: Joi.string().valid('created', 'sent', 'activated', 'expired').optional(),
});

export const getCommissionsQuerySchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).optional().default(50),
  offset: Joi.number().integer().min(0).optional().default(0),
});
