import { Request, Response, NextFunction } from 'express';
import { JsonWebTokenError, TokenExpiredError, NotBeforeError } from 'jsonwebtoken';
import { logger } from '../utils/logger';
import { AppError, AppErrorCode, ValidationError } from '../utils/errors';

interface ErrorEnvelope {
  success: false;
  error: string;
  code: AppErrorCode;
  statusCode: number;
  requestId?: string;
  /** Validation details — present only on 400/VALIDATION_ERROR. */
  details?: Array<{ field: string; message: string }>;
  /** Dev-only: extra context for triage. Stripped in production. */
  message?: string;
  stack?: string;
}

function getRequestId(req: Request): string | undefined {
  return (req.headers['x-request-id'] as string | undefined)
    ?? (req.get('x-request-id') as string | undefined);
}

function pgErrorToApp(err: any): AppError | null {
  const pgCode: string | undefined = err?.code;
  if (typeof pgCode !== 'string') return null;
  switch (pgCode) {
    case '23505':
      return new AppError('A record with that value already exists', 409, 'CONFLICT', err);
    case '23503':
      return new AppError('Referenced record does not exist', 409, 'CONFLICT', err);
    case '23502':
      // NOT NULL violation — usually a server bug, but some routes accept
      // partial input and the right answer is 400 to surface the missing
      // field. Audit Ch11-I019 caught these falling through to 500.
      return new AppError('A required field is missing', 400, 'VALIDATION_ERROR', err);
    case '22001':
      return new AppError('Field exceeds maximum length', 400, 'VALIDATION_ERROR', err);
    case '22P02':
      return new AppError('Field has the wrong type or format', 400, 'VALIDATION_ERROR', err);
    case '57P03':
      return new AppError('Service temporarily unavailable', 503, 'UNHEALTHY', err);
    default:
      return null;
  }
}

export function errorHandler(
  err: Error,
  req: Request,
  res: Response,
  next: NextFunction,
) {
  if (res.headersSent) return next(err);

  const requestId = getRequestId(req);
  const isDev = process.env.NODE_ENV === 'development' || process.env.NODE_ENV === 'test';

  // ── Operational errors (AppError + ValidationError) ───────────────────
  if (err instanceof AppError) {
    // 4xx errors are user-facing, not "errors" worth Loki ERROR-level traffic. Log at
    // warn unless 5xx. (Ch11-I016)
    const level = err.statusCode >= 500 ? 'error' : 'warn';
    logger[level](
      {
        statusCode: err.statusCode,
        code: err.code,
        message: err.message,
        path: req.path,
        method: req.method,
        cause: err.cause,
      },
      'Operational error',
    );

    const body: ErrorEnvelope = {
      success: false,
      error: err.message,
      code: err.code,
      statusCode: err.statusCode,
      requestId,
    };
    if (err instanceof ValidationError) body.details = err.details;
    return res.status(err.statusCode).json(body);
  }

  // ── JWT errors ────────────────────────────────────────────────────────
  if (err instanceof JsonWebTokenError || err instanceof TokenExpiredError || err instanceof NotBeforeError) {
    // 4.7: pass the Error itself so pino's err serializer captures
    // stack + name + cause. The previous shape (`err: err.message`)
    // flattened to a string, so a "JsonWebTokenError: jwt malformed"
    // landed in Loki with no name — making it impossible to tell
    // signature failures from malformed tokens at a glance.
    logger.warn(
      { err, message: err.message, path: req.path, method: req.method },
      'JWT auth error',
    );
    const expired = err instanceof TokenExpiredError;
    return res.status(401).json({
      success: false,
      error: expired ? 'Token expired' : 'Invalid token',
      code: expired ? 'TOKEN_EXPIRED' : 'INVALID_TOKEN',
      statusCode: 401,
      requestId,
    } satisfies ErrorEnvelope);
  }

  // ── Postgres ──────────────────────────────────────────────────────────
  const pgWrapped = pgErrorToApp(err);
  if (pgWrapped) {
    logger.warn(
      {
        code: pgWrapped.code,
        pgCode: (err as any).code,
        pgMessage: (err as any).message,
        pgDetail: (err as any).detail,
        pgColumn: (err as any).column,
        pgTable: (err as any).table,
        path: req.path,
      },
      'PG error mapped to AppError',
    );
    return res.status(pgWrapped.statusCode).json({
      success: false,
      error: pgWrapped.message,
      code: pgWrapped.code,
      statusCode: pgWrapped.statusCode,
      requestId,
    } satisfies ErrorEnvelope);
  }

  // ── Unknown / unexpected ──────────────────────────────────────────────
  logger.error(
    { err, stack: err.stack, path: req.path, method: req.method },
    'Unexpected error',
  );

  const body: ErrorEnvelope = {
    success: false,
    error: 'Internal server error',
    code: 'INTERNAL',
    statusCode: 500,
    requestId,
  };
  if (isDev) {
    body.message = err.message;
    body.stack = err.stack;
  }
  res.status(500).json(body);
}
