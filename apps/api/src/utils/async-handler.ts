import { Request, Response, NextFunction } from 'express';
import { logger } from './logger';

type AsyncFunction = (req: Request, res: Response, next: NextFunction) => Promise<any>;

/**
 * Wrapper for async route handlers to catch errors and pass to error middleware
 */
export const asyncHandler = (fn: AsyncFunction) => {
  return (req: Request, res: Response, next: NextFunction) => {
    Promise.resolve(fn(req, res, next)).catch((error) => {
      logger.error({ error, method: req.method, path: req.path }, 'Unhandled route error');
      next(error);
    });
  };
};
