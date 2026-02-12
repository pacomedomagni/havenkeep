import Joi from 'joi';

export const userIdParamSchema = Joi.object({
  id: Joi.string().uuid().required(),
});

export const dateRangeQuerySchema = Joi.object({
  days: Joi.number().integer().min(1).max(365).default(30),
});
