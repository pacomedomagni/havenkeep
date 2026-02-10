import { Request, Response, NextFunction } from 'express';
import Joi from 'joi';
import { AppError } from './errorHandler';

export function validate(schema: Joi.ObjectSchema, property: 'body' | 'query' | 'params' = 'body') {
  return (req: Request, res: Response, next: NextFunction) => {
    const { error, value } = schema.validate(req[property], {
      abortEarly: false,
      stripUnknown: true,
    });

    if (error) {
      const errors = error.details.map(detail => ({
        field: detail.path.join('.'),
        message: detail.message,
      }));

      throw new AppError(400, 'Validation failed', true, errors);
    }

    // Replace request property with validated and sanitized value
    req[property] = value;
    next();
  };
}
