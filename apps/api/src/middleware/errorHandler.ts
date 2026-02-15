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
