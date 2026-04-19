"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.errorHandler = errorHandler;
const jsonwebtoken_1 = require("jsonwebtoken");
const logger_1 = require("../utils/logger");
const errors_1 = require("../utils/errors");
function errorHandler(err, req, res, next) {
    // If response already sent, delegate to Express default handler
    if (res.headersSent) {
        return next(err);
    }
    if (err instanceof errors_1.AppError) {
        logger_1.logger.error({
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
    // JWT errors — malformed, expired, or invalid tokens
    if (err instanceof jsonwebtoken_1.JsonWebTokenError || err instanceof jsonwebtoken_1.TokenExpiredError || err instanceof jsonwebtoken_1.NotBeforeError) {
        logger_1.logger.warn({
            error: err.message,
            path: req.path,
            method: req.method,
        }, 'JWT authentication error');
        const message = err instanceof jsonwebtoken_1.TokenExpiredError ? 'Token expired' : 'Invalid token';
        return res.status(401).json({
            error: message,
            statusCode: 401,
        });
    }
    // PostgreSQL-specific error code mapping
    const pgCode = err.code;
    if (typeof pgCode === 'string') {
        if (pgCode === '23505') {
            // Unique constraint violation
            logger_1.logger.error({ error: err.message, code: pgCode, path: req.path, method: req.method }, 'Unique constraint violation');
            return res.status(409).json({
                error: 'A record with that value already exists',
                statusCode: 409,
            });
        }
        if (pgCode === '23503') {
            // Foreign key violation
            logger_1.logger.error({ error: err.message, code: pgCode, path: req.path, method: req.method }, 'Foreign key violation');
            return res.status(409).json({
                error: 'Referenced record does not exist or would be violated',
                statusCode: 409,
            });
        }
        if (pgCode === '57P03') {
            // Database unavailable
            logger_1.logger.error({ error: err.message, code: pgCode, path: req.path, method: req.method }, 'Database unavailable');
            return res.status(503).json({
                error: 'Service temporarily unavailable',
                statusCode: 503,
            });
        }
    }
    // Unexpected errors — log real details server-side only, never send to client in production
    logger_1.logger.error({
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
//# sourceMappingURL=errorHandler.js.map