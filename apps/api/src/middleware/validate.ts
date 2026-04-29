import { Request, Response, NextFunction } from 'express';
import Joi from 'joi';
import { ValidationError } from '../utils/errors';
import { logger } from '../utils/logger';

export type ValidateTarget = 'body' | 'query' | 'params';

/**
 * Joi-validate one or many request properties.
 *
 * Single-target form (back-compat):
 *   validate(schema)                         — body
 *   validate(schema, 'query')                — query
 *
 * Multi-target form:
 *   validate({ body: bodySchema, params: paramsSchema })
 *
 * The audit (Ch11-I023 / I024) flagged two real bugs:
 *   - `stripUnknown: true` silently dropped misspelled fields, masking
 *     client bugs (`fullname` vs `fullName`). We now run with
 *     `allowUnknown: false`/`stripUnknown: false` in dev/test so the bug
 *     surfaces, and stripUnknown:true in production where forward-compat
 *     is more important than developer feedback.
 *   - Each callsite could only validate ONE target — params and query were
 *     often unchecked even when a body validator existed. The map form
 *     fixes that.
 */
export function validate(
  schema: Joi.ObjectSchema | Partial<Record<ValidateTarget, Joi.ObjectSchema>>,
  target: ValidateTarget = 'body',
) {
  const schemas: Partial<Record<ValidateTarget, Joi.ObjectSchema>> = Joi.isSchema(schema)
    ? { [target]: schema as Joi.ObjectSchema }
    : (schema as Partial<Record<ValidateTarget, Joi.ObjectSchema>>);

  const isProd = process.env.NODE_ENV === 'production';

  return (req: Request, _res: Response, next: NextFunction) => {
    for (const [prop, sch] of Object.entries(schemas) as [ValidateTarget, Joi.ObjectSchema][]) {
      if (!sch) continue;
      const { error, value } = sch.validate(req[prop], {
        abortEarly: false,
        // In production we strip unknowns so a future client field that the
        // server hasn't been deployed-with yet doesn't 400 every call. In
        // dev/test we want the typo to fail loud.
        stripUnknown: isProd,
        allowUnknown: isProd,
      });

      if (error) {
        const details = error.details.map((d) => ({
          field: d.path.join('.'),
          message: d.message,
        }));
        return next(new ValidationError(`Validation failed for ${prop}`, details));
      }

      // S-LO-01: in production we strip unknown keys silently so a forward-
      // compat client doesn't 400. But silent drops mask client typos
      // (`fullname` vs `fullName`) that surface as weird UX bugs. Log the
      // dropped keys at warn so the misspell is at least observable.
      if (isProd && req[prop] && typeof req[prop] === 'object' && value && typeof value === 'object') {
        const inputKeys = Object.keys(req[prop] as object);
        const validatedKeys = new Set(Object.keys(value as object));
        const dropped = inputKeys.filter((k) => !validatedKeys.has(k));
        if (dropped.length > 0) {
          logger.warn(
            { prop, dropped, route: req.originalUrl, method: req.method },
            'Validator stripped unknown keys',
          );
        }
      }

      // Replace request property with validated value
      (req as any)[prop] = value;
    }
    next();
  };
}
