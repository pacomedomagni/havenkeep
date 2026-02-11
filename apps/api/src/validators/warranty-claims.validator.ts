import Joi from 'joi';

export const createWarrantyClaimSchema = Joi.object({
  item_id: Joi.string().uuid().required(),
  claim_date: Joi.date().iso().optional().max('now'),
  issue_description: Joi.string().max(2000).optional(),
  repair_description: Joi.string().max(2000).optional(),
  repair_cost: Joi.number().min(0).max(1000000).required(),
  amount_saved: Joi.number().min(0).max(1000000).required(),
  out_of_pocket: Joi.number().min(0).max(1000000).optional(),
  status: Joi.string().valid('pending', 'in_progress', 'completed', 'denied').optional(),
  filed_with: Joi.string().max(100).optional(),
  claim_number: Joi.string().max(100).optional(),
  notes: Joi.string().max(5000).optional(),
});

export const updateWarrantyClaimSchema = Joi.object({
  claim_date: Joi.date().iso().optional(),
  issue_description: Joi.string().max(2000).optional().allow(null),
  repair_description: Joi.string().max(2000).optional().allow(null),
  repair_cost: Joi.number().min(0).max(1000000).optional(),
  amount_saved: Joi.number().min(0).max(1000000).optional(),
  out_of_pocket: Joi.number().min(0).max(1000000).optional().allow(null),
  status: Joi.string().valid('pending', 'in_progress', 'completed', 'denied').optional(),
  filed_with: Joi.string().max(100).optional().allow(null),
  claim_number: Joi.string().max(100).optional().allow(null),
  notes: Joi.string().max(5000).optional().allow(null),
}).min(1);

export const getClaimsQuerySchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).optional().default(50),
  offset: Joi.number().integer().min(0).optional().default(0),
  item_id: Joi.string().uuid().optional(),
});
