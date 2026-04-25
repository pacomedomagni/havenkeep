/**
 * Enumerated error codes — every code the API surfaces to clients lives here
 * so a future refactor can't quietly introduce a new one without grep-ing
 * this file. Audit Ch11-I027 caught the prior `code?: string` for being
 * effectively typed as `string` everywhere.
 */
export type AppErrorCode =
  | 'VALIDATION_ERROR'
  | 'AUTH_REQUIRED'
  | 'INVALID_TOKEN'
  | 'TOKEN_EXPIRED'
  | 'FORBIDDEN'
  | 'NOT_FOUND'
  | 'CONFLICT'
  | 'PAYMENT_REQUIRED'
  | 'RATE_LIMITED'
  | 'UPSTREAM_FAILED'
  | 'CSRF_FAILED'
  | 'UNHEALTHY'
  | 'INTERNAL';

export interface ValidationDetail {
  field: string;
  message: string;
}

export class AppError extends Error {
  public readonly statusCode: number;
  public readonly code: AppErrorCode;
  /**
   * Original error captured for log-side triage. Never reaches the wire —
   * the error handler renders only `code` + `message`.
   */
  public readonly cause?: unknown;

  constructor(
    message: string,
    statusCode: number = 500,
    code: AppErrorCode = 'INTERNAL',
    cause?: unknown,
  ) {
    super(message);
    this.name = 'AppError';
    this.statusCode = statusCode;
    this.code = code;
    this.cause = cause;
    Error.captureStackTrace(this, this.constructor);
  }
}

export class ValidationError extends AppError {
  public readonly details: ValidationDetail[];

  constructor(message: string, details: ValidationDetail[] = []) {
    super(message, 400, 'VALIDATION_ERROR');
    this.name = 'ValidationError';
    this.details = details;
  }
}
