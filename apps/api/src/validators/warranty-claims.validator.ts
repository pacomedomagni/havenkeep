import Joi from 'joi';

export const createWarrantyClaimSchema = Joi.object({
  itemId: Joi.string().uuid().required(),
  claimDate: Joi.date().iso().optional().max('now'),
  issueDescription: Joi.string().max(2000).optional(),
  repairDescription: Joi.string().max(2000).optional(),
  repairCost: Joi.number().min(0).max(1000000).required(),
  amountSaved: Joi.number().min(0).max(1000000).required(),
  outOfPocket: Joi.number().min(0).max(1000000).optional(),
  // Canonical state machine: filed → in_review → approved/denied → settled/closed.
  // Mirrors migration 060's CHECK constraint.
  status: Joi.string().valid('filed', 'in_review', 'approved', 'denied', 'settled', 'closed').optional(),
  filedWith: Joi.string().max(100).optional(),
  claimNumber: Joi.string().max(100).optional(),
  notes: Joi.string().max(5000).optional(),
})
  // Accept snake_case from mobile clients
  .rename('item_id', 'itemId', { ignoreUndefined: true, override: false })
  .rename('claim_date', 'claimDate', { ignoreUndefined: true, override: false })
  .rename('issue_description', 'issueDescription', { ignoreUndefined: true, override: false })
  .rename('repair_description', 'repairDescription', { ignoreUndefined: true, override: false })
  .rename('repair_cost', 'repairCost', { ignoreUndefined: true, override: false })
  .rename('amount_saved', 'amountSaved', { ignoreUndefined: true, override: false })
  .rename('out_of_pocket', 'outOfPocket', { ignoreUndefined: true, override: false })
  .rename('filed_with', 'filedWith', { ignoreUndefined: true, override: false })
  .rename('claim_number', 'claimNumber', { ignoreUndefined: true, override: false });

export const updateWarrantyClaimSchema = Joi.object({
  // Ch08-WarrantyClaim-D022: mirror the create-side .max('now') guard.
  // Backdating "the dishwasher broke yesterday" is fine; future-dating a
  // claim is always wrong.
  claimDate: Joi.date().iso().max('now').optional(),
  issueDescription: Joi.string().max(2000).optional().allow(null),
  repairDescription: Joi.string().max(2000).optional().allow(null),
  repairCost: Joi.number().min(0).max(1000000).optional(),
  amountSaved: Joi.number().min(0).max(1000000).optional(),
  outOfPocket: Joi.number().min(0).max(1000000).optional().allow(null),
  // Canonical state machine: filed → in_review → approved/denied → settled/closed.
  // Mirrors migration 060's CHECK constraint.
  status: Joi.string().valid('filed', 'in_review', 'approved', 'denied', 'settled', 'closed').optional(),
  filedWith: Joi.string().max(100).optional().allow(null),
  claimNumber: Joi.string().max(100).optional().allow(null),
  notes: Joi.string().max(5000).optional().allow(null),
}).min(1)
  // Accept snake_case from mobile clients
  .rename('claim_date', 'claimDate', { ignoreUndefined: true, override: false })
  .rename('issue_description', 'issueDescription', { ignoreUndefined: true, override: false })
  .rename('repair_description', 'repairDescription', { ignoreUndefined: true, override: false })
  .rename('repair_cost', 'repairCost', { ignoreUndefined: true, override: false })
  .rename('amount_saved', 'amountSaved', { ignoreUndefined: true, override: false })
  .rename('out_of_pocket', 'outOfPocket', { ignoreUndefined: true, override: false })
  .rename('filed_with', 'filedWith', { ignoreUndefined: true, override: false })
  .rename('claim_number', 'claimNumber', { ignoreUndefined: true, override: false });

export const getClaimsQuerySchema = Joi.object({
  page: Joi.number().integer().min(1).optional().default(1),
  limit: Joi.number().integer().min(1).max(100).optional().default(50),
  itemId: Joi.string().uuid().optional(),
})
  .rename('item_id', 'itemId', { ignoreUndefined: true, override: false });
