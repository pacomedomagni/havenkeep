import { Request, Response, NextFunction } from 'express';
import { logger } from '../utils/logger';
import { AppError as UtilsAppError } from '../utils/errors';

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

function isOperationalError(err: Error): err is (AppError | UtilsAppError) {
  return err instanceof AppError || err instanceof UtilsAppError;
}

function getStatusCode(err: AppError | UtilsAppError): number {
  return err.statusCode;
}

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

  if (isOperationalError(err)) {
    const statusCode = getStatusCode(err);

    logger.error({
      statusCode,
      message: err.message,
      path: req.path,
      method: req.method,
      ...('details' in err && { details: (err as AppError).details }),
    }, 'Operational error');

    return res.status(statusCode).json({
      error: err.message,
      statusCode,
      ...('details' in err && (err as AppError).details && { details: (err as AppError).details }),
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
