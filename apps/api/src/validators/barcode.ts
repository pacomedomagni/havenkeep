import Joi from 'joi';

/**
 * F107: only valid EAN/UPC lengths are accepted. Previously the regex
 * matched 8..14 digits inclusive, which let through 9/10/11-digit partial
 * inputs that the upstream provider would 404 on (and we'd cache the 404
 * for 24h, hiding the real product if the user re-tried with a fixed
 * length). Restrict to:
 *   - 8  digits  (EAN-8 / UPC-E)
 *   - 12 digits  (UPC-A)
 *   - 13 digits  (EAN-13)
 *   - 14 digits  (GTIN-14 / ITF-14)
 */
export const barcodeLookupSchema = Joi.object({
  barcode: Joi.string()
    .pattern(/^([0-9]{8}|[0-9]{12}|[0-9]{13}|[0-9]{14})$/)
    .required()
    .messages({
      'string.pattern.base': 'Barcode must be 8, 12, 13, or 14 digits (EAN/UPC/GTIN)',
      'any.required': 'Barcode is required',
    }),
});
