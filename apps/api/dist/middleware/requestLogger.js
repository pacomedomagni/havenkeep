"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.requestLogger = requestLogger;
const crypto_1 = __importDefault(require("crypto"));
const logger_1 = require("../utils/logger");
function requestLogger(req, res, next) {
    const start = Date.now();
    // Generate or use existing request ID for correlation
    const requestId = req.get('x-request-id') || crypto_1.default.randomUUID();
    req.headers['x-request-id'] = requestId;
    res.setHeader('x-request-id', requestId);
    res.on('finish', () => {
        const duration = Date.now() - start;
        logger_1.logger.info({
            requestId,
            method: req.method,
            path: req.path,
            statusCode: res.statusCode,
            duration,
            userAgent: req.get('user-agent'),
            ip: req.ip,
        }, 'Request completed');
    });
    next();
}
//# sourceMappingURL=requestLogger.js.map