import { Request, Response, NextFunction } from 'express';
import Joi from 'joi';
import { ValidationError } from '../utils/errors';

export function validate(schema: Joi.ObjectSchema, property: 'body' | 'query' | 'params' = 'body') {
  return (req: Request, res: Response, next: NextFunction) => {
    // NOTE: stripUnknown silently removes unrecognized fields, which can mask client bugs
    // (e.g., sending 'fullname' instead of 'fullName'). Consider setting allowUnknown: false
    // in development/staging to surface these issues early.
    const { error, value } = schema.validate(req[property], {
      abortEarly: false,
      stripUnknown: true,
    });

    if (error) {
      const errors = error.details.map(detail => ({
        field: detail.path.join('.'),
        message: detail.message,
      }));

      throw new ValidationError('Validation failed', errors);
    }

    // Replace request property with validated and sanitized value
    req[property] = value;
    next();
  };
}
