import Joi from 'joi';

export const barcodeLookupSchema = Joi.object({
  barcode: Joi.string()
    .pattern(/^[0-9]{8,14}$/)
    .required()
    .messages({
      'string.pattern.base': 'Barcode must be 8-14 digits',
      'any.required': 'Barcode is required',
    }),
});
