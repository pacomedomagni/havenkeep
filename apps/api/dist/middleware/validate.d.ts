import { Request, Response, NextFunction } from 'express';
import Joi from 'joi';
export declare function validate(schema: Joi.ObjectSchema, property?: 'body' | 'query' | 'params'): (req: Request, res: Response, next: NextFunction) => void;
//# sourceMappingURL=validate.d.ts.map