import { Request, Response, NextFunction } from 'express';
export { AppError } from '../utils/errors';
export declare function errorHandler(err: Error, req: Request, res: Response, next: NextFunction): void | Response<any, Record<string, any>>;
//# sourceMappingURL=errorHandler.d.ts.map