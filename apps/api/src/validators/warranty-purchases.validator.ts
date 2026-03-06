import Joi from 'joi';

export const createWarrantyPurchaseSchema = Joi.object({
  itemId: Joi.string().uuid().required(),
  provider: Joi.string().max(100).required(),
  planName: Joi.string().max(255).required(),
  externalPolicyId: Joi.string().max(255).optional(),
  durationMonths: Joi.number().integer().min(1).max(240).required(),
  startsAt: Joi.date().iso().required(),
  coverageDetails: Joi.object().optional(),
  price: Joi.number().min(0).max(1000000).required(),
  deductible: Joi.number().min(0).max(1000000).optional().default(0),
  claimLimit: Joi.number().min(0).max(1000000).optional(),
  commissionAmount: Joi.number().min(0).optional(),
  commissionRate: Joi.number().min(0).max(1).optional(),
  stripePaymentIntentId: Joi.string().max(255).optional(),
})
  // Accept snake_case from mobile clients
  .rename('item_id', 'itemId', { ignoreUndefined: true, override: false })
  .rename('plan_name', 'planName', { ignoreUndefined: true, override: false })
  .rename('external_policy_id', 'externalPolicyId', { ignoreUndefined: true, override: false })
  .rename('duration_months', 'durationMonths', { ignoreUndefined: true, override: false })
  .rename('starts_at', 'startsAt', { ignoreUndefined: true, override: false })
  .rename('coverage_details', 'coverageDetails', { ignoreUndefined: true, override: false })
  .rename('claim_limit', 'claimLimit', { ignoreUndefined: true, override: false })
  .rename('commission_amount', 'commissionAmount', { ignoreUndefined: true, override: false })
  .rename('commission_rate', 'commissionRate', { ignoreUndefined: true, override: false })
  .rename('stripe_payment_intent_id', 'stripePaymentIntentId', { ignoreUndefined: true, override: false });

export const cancelWarrantyPurchaseSchema = Joi.object({
  reason: Joi.string().max(2000).optional(),
});

export const getPurchasesQuerySchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).optional().default(50),
  offset: Joi.number().integer().min(0).optional().default(0),
  itemId: Joi.string().uuid().optional(),
  status: Joi.string().valid('active', 'expired', 'cancelled', 'pending', 'claimed').optional(),
})
  .rename('item_id', 'itemId', { ignoreUndefined: true, override: false });

export const getExpiringQuerySchema = Joi.object({
  days: Joi.number().integer().min(1).max(365).optional().default(30),
});
