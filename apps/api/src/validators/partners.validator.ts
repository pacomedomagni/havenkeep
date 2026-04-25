import Joi from 'joi';

export const registerPartnerSchema = Joi.object({
  partnerType: Joi.string()
    .valid('realtor', 'builder', 'contractor', 'property_manager', 'other')
    .required(),
  companyName: Joi.string().max(255).optional(),
  phone: Joi.string().max(50).optional(),
  website: Joi.string().uri().max(255).optional(),
  brandColor: Joi.string().pattern(/^#[0-9A-F]{6}$/i).optional(),
  logoUrl: Joi.string().uri().optional(),
  defaultMessage: Joi.string().max(1000).optional(),
  serviceAreas: Joi.array().items(Joi.string().max(100)).optional(),
  licenseNumber: Joi.string().max(100).allow(null, ''),
})
  // Accept snake_case from clients
  .rename('partner_type', 'partnerType', { ignoreUndefined: true, override: false })
  .rename('company_name', 'companyName', { ignoreUndefined: true, override: false })
  .rename('brand_color', 'brandColor', { ignoreUndefined: true, override: false })
  .rename('logo_url', 'logoUrl', { ignoreUndefined: true, override: false })
  .rename('default_message', 'defaultMessage', { ignoreUndefined: true, override: false })
  .rename('service_areas', 'serviceAreas', { ignoreUndefined: true, override: false })
  .rename('license_number', 'licenseNumber', { ignoreUndefined: true, override: false });

// `partnerType` is intentionally NOT in the update schema (Ch03-F015):
// reclassifying a partner after registration changes commission tier rules
// and audit trail. The DB also enforces this via a trigger added in
// migration 050; the validator-level rejection is the user-facing message.
export const updatePartnerSchema = Joi.object({
  companyName: Joi.string().max(255).optional(),
  phone: Joi.string().max(50).optional(),
  website: Joi.string().uri().max(255).optional(),
  brandColor: Joi.string().pattern(/^#[0-9A-F]{6}$/i).optional(),
  logoUrl: Joi.string().uri().optional(),
  defaultMessage: Joi.string().max(1000).optional(),
  defaultPremiumMonths: Joi.number().integer().min(1).max(12).optional(),
  serviceAreas: Joi.array().items(Joi.string().max(100)).optional(),
  licenseNumber: Joi.string().max(100).allow(null, ''),
}).min(1)
  // Accept snake_case from clients
  .rename('company_name', 'companyName', { ignoreUndefined: true, override: false })
  .rename('brand_color', 'brandColor', { ignoreUndefined: true, override: false })
  .rename('logo_url', 'logoUrl', { ignoreUndefined: true, override: false })
  .rename('default_message', 'defaultMessage', { ignoreUndefined: true, override: false })
  .rename('default_premium_months', 'defaultPremiumMonths', { ignoreUndefined: true, override: false })
  .rename('service_areas', 'serviceAreas', { ignoreUndefined: true, override: false })
  .rename('license_number', 'licenseNumber', { ignoreUndefined: true, override: false })
  // Reject `partnerType` / `partner_type` at validation time so the API never
  // attempts to persist a change that the DB trigger would refuse.
  .messages({ 'object.unknown': 'partner_type is immutable after registration' });

export const createGiftSchema = Joi.object({
  homebuyerEmail: Joi.string().email().required(),
  homebuyerName: Joi.string().max(255).required(),
  homebuyerPhone: Joi.string().max(50).optional(),
  homeAddress: Joi.string().max(500).optional(),
  closingDate: Joi.date().iso().optional(),
  premiumMonths: Joi.number().integer().min(1).max(12).optional(),
  customMessage: Joi.string().max(1000).optional(),
})
  // Accept snake_case from clients
  .rename('homebuyer_email', 'homebuyerEmail', { ignoreUndefined: true, override: false })
  .rename('homebuyer_name', 'homebuyerName', { ignoreUndefined: true, override: false })
  .rename('homebuyer_phone', 'homebuyerPhone', { ignoreUndefined: true, override: false })
  .rename('home_address', 'homeAddress', { ignoreUndefined: true, override: false })
  .rename('closing_date', 'closingDate', { ignoreUndefined: true, override: false })
  .rename('premium_months', 'premiumMonths', { ignoreUndefined: true, override: false })
  .rename('custom_message', 'customMessage', { ignoreUndefined: true, override: false });

// Audit Ch08-PartnerGift-D064: status query was missing 'payment_failed',
// so an admin filtering for failed Stripe charges silently got an empty
// list. List every value the gift_status enum can take.
export const getGiftsQuerySchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).optional().default(50),
  offset: Joi.number().integer().min(0).optional().default(0),
  status: Joi.string()
    .valid(
      'created',
      'sent',
      'activated',
      'expired',
      'pending_payment',
      'payment_failed',
    )
    .optional(),
});

export const getCommissionsQuerySchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).optional().default(50),
  offset: Joi.number().integer().min(0).optional().default(0),
});
