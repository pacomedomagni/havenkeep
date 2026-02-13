"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.AppError = void 0;
exports.errorHandler = errorHandler;
const logger_1 = require("../utils/logger");
const errors_1 = require("../utils/errors");
// Re-export AppError so existing imports from this file continue to work
var errors_2 = require("../utils/errors");
Object.defineProperty(exports, "AppError", { enumerable: true, get: function () { return errors_2.AppError; } });
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
    // Unexpected errors — don't leak details in production
    logger_1.logger.error({
        error: err.message,
        stack: err.stack,
        path: req.path,
        method: req.method,
    }, 'Unexpected error');
    res.status(500).json({
        error: 'Internal server error',
        statusCode: 500,
        ...(process.env.NODE_ENV !== 'production' && { message: err.message }),
    });
}
//# sourceMappingURL=errorHandler.js.map