import Joi from 'joi';

export const createWarrantyPurchaseSchema = Joi.object({
  item_id: Joi.string().uuid().required(),
  provider: Joi.string().max(100).required(),
  plan_name: Joi.string().max(255).required(),
  external_policy_id: Joi.string().max(255).optional(),
  duration_months: Joi.number().integer().min(1).max(120).required(),
  starts_at: Joi.date().iso().required(),
  coverage_details: Joi.object().optional(),
  price: Joi.number().min(0).max(1000000).required(),
  deductible: Joi.number().min(0).max(1000000).optional().default(0),
  claim_limit: Joi.number().min(0).max(1000000).optional(),
  commission_amount: Joi.number().min(0).optional(),
  commission_rate: Joi.number().min(0).max(1).optional(),
  stripe_payment_intent_id: Joi.string().max(255).optional(),
});

export const cancelWarrantyPurchaseSchema = Joi.object({
  reason: Joi.string().max(2000).optional(),
});

export const getPurchasesQuerySchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).optional().default(50),
  offset: Joi.number().integer().min(0).optional().default(0),
  item_id: Joi.string().uuid().optional(),
  status: Joi.string().valid('active', 'expired', 'cancelled', 'pending').optional(),
});

export const getExpiringQuerySchema = Joi.object({
  days: Joi.number().integer().min(1).max(365).optional().default(30),
});
