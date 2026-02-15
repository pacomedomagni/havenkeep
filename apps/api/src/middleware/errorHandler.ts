import { Request, Response, NextFunction } from 'express';
import { logger } from '../utils/logger';
import { AppError } from '../utils/errors';

// Re-export AppError so existing imports from this file continue to work
export { AppError } from '../utils/errors';

export function errorHandler(
  err: Error,
  req: Request,
  res: Response,
  next: NextFunction
) {
  // If response already sent, delegate to Express default handler
  if (res.headersSent) {
    return next(err);
  }

  if (err instanceof AppError) {
    logger.error({
      statusCode: err.statusCode,
      message: err.message,
      code: err.code,
      path: req.path,
      method: req.method,
    }, 'Operational error');

    return res.status(err.statusCode).json({
      error: err.message,
      statusCode: err.statusCode,
    });
  }

  // PostgreSQL-specific error code mapping
  const pgCode = (err as any).code;
  if (typeof pgCode === 'string') {
    if (pgCode === '23505') {
      // Unique constraint violation
      logger.error({ error: err.message, code: pgCode, path: req.path, method: req.method }, 'Unique constraint violation');
      return res.status(409).json({
        error: 'A record with that value already exists',
        statusCode: 409,
      });
    }
    if (pgCode === '23503') {
      // Foreign key violation
      logger.error({ error: err.message, code: pgCode, path: req.path, method: req.method }, 'Foreign key violation');
      return res.status(409).json({
        error: 'Referenced record does not exist or would be violated',
        statusCode: 409,
      });
    }
    if (pgCode === '57P03') {
      // Database unavailable
      logger.error({ error: err.message, code: pgCode, path: req.path, method: req.method }, 'Database unavailable');
      return res.status(503).json({
        error: 'Service temporarily unavailable',
        statusCode: 503,
      });
    }
  }

  // Unexpected errors — log real details server-side only, never send to client in production
  logger.error({
    error: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method,
  }, 'Unexpected error');

  const isDevelopment = process.env.NODE_ENV === 'development' || process.env.NODE_ENV === 'test';

  res.status(500).json({
    error: 'Internal server error',
    statusCode: 500,
    ...(isDevelopment && { message: err.message, stack: err.stack }),
  });
}
