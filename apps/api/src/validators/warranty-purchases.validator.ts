import Joi from 'joi';

export const createWarrantyPurchaseSchema = Joi.object({
  itemId: Joi.string().uuid().required(),
  provider: Joi.string().max(100).required(),
  planName: Joi.string().max(255).required(),
  externalPolicyId: Joi.string().max(255).optional(),
  durationMonths: Joi.number().integer().min(1).max(240).required(),
  // F017: cap startsAt at 1y in the future so a 73-year-out payload can't
  // even reach the service. Service does a parallel guard.
  startsAt: Joi.date()
    .iso()
    .required()
    .max(new Date(Date.now() + 365 * 24 * 60 * 60 * 1000 + 1000)),
  coverageDetails: Joi.object().optional(),
  price: Joi.number().min(0).max(1000000).required(),
  deductible: Joi.number().min(0).max(1000000).optional().default(0),
  claimLimit: Joi.number().min(0).max(1000000).optional(),
  // Ch08-WarrantyPurchase-D027: bound commission_amount so a runaway
  // partner-side calculation can't insert a six-figure commission row.
  commissionAmount: Joi.number().min(0).max(999999.99).optional(),
  // F019: clients are NOT trusted to set commission_rate. Reject loudly so
  // a hand-crafted payload doesn't silently float the partner percentage.
  commissionRate: Joi.any().forbidden(),
  // SECURITY: clients are NOT trusted to set stripe_payment_intent_id
  // either. The extended-warranty marketplace that would charge a PI on
  // HavenKeep's behalf is deferred (see docs/DEFERRED.md #1), and
  // cancelPurchase issues `stripe.refunds.create({payment_intent: <stored
  // value>})` on the row's stored value — accepting a client-supplied PI
  // means an authenticated user could refund another HavenKeep user's
  // charge by binding their cancel to a PI on the same Stripe account.
  // Reject any non-null value. When the marketplace ships, the API will
  // create the PI itself and bind it server-side; this field becomes
  // unnecessary in the request body entirely.
  stripePaymentIntentId: Joi.any().forbidden(),
  // Ch08-WarrantyPurchase-D029: explicit status default at the schema layer.
  // The DB column also defaults to 'active' but having it here means the
  // body that hits the service is self-describing.
  status: Joi.string()
    .valid('active', 'expired', 'cancelled', 'pending', 'claimed')
    .default('active'),
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
  page: Joi.number().integer().min(1).optional(),
  itemId: Joi.string().uuid().optional(),
  homeId: Joi.string().uuid().optional(),
  status: Joi.string().valid('active', 'expired', 'cancelled', 'pending', 'claimed').optional(),
})
  .rename('item_id', 'itemId', { ignoreUndefined: true, override: false })
  .rename('home_id', 'homeId', { ignoreUndefined: true, override: false });

export const getExpiringQuerySchema = Joi.object({
  days: Joi.number().integer().min(1).max(365).optional().default(30),
});
