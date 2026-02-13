"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.asyncHandler = void 0;
const logger_1 = require("./logger");
/**
 * Wrapper for async route handlers to catch errors and pass to error middleware
 */
const asyncHandler = (fn) => {
    return (req, res, next) => {
        Promise.resolve(fn(req, res, next)).catch((error) => {
            logger_1.logger.error({ error, method: req.method, path: req.path }, 'Unhandled route error');
            next(error);
        });
    };
};
exports.asyncHandler = asyncHandler;
//# sourceMappingURL=async-handler.js.map