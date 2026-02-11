import { Request, Response, NextFunction } from 'express';
import { logger } from '../utils/logger';

export class AppError extends Error {
  constructor(
    public statusCode: number,
    public message: string,
    public isOperational = true,
    public details?: any[]
  ) {
    super(message);
    Object.setPrototypeOf(this, AppError.prototype);
  }
}

export function errorHandler(
  err: Error | AppError,
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
      path: req.path,
      method: req.method,
      details: err.details,
    }, 'Operational error');

    return res.status(err.statusCode).json({
      error: err.message,
      statusCode: err.statusCode,
      ...(err.details && { details: err.details }),
    });
  }

  // Unexpected errors
  logger.error({
    error: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method,
  }, 'Unexpected error');

  // Don't leak error details in production
  res.status(500).json({
    error: 'Internal server error',
    statusCode: 500,
    ...(process.env.NODE_ENV !== 'production' && { message: err.message }),
  });
}
