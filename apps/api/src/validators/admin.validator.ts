import Joi from 'joi';

export const userIdParamSchema = Joi.object({
  id: Joi.string().uuid().required(),
});

export const dateRangeQuerySchema = Joi.object({
  days: Joi.number().integer().min(1).max(365).default(30),
});

// S-ME-03: explicit body shape for partner rejection. The handler trims
// + slices `reason` to 1024 chars; the schema rejects any other body
// fields a future refactor might accidentally introduce.
export const rejectPartnerBodySchema = Joi.object({
  reason: Joi.string().max(1024).allow('', null).optional(),
}).unknown(false);
