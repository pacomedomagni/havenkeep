"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.setCsrfToken = setCsrfToken;
exports.validateCsrfToken = validateCsrfToken;
const crypto_1 = __importDefault(require("crypto"));
const CSRF_COOKIE = 'csrf_token';
const CSRF_HEADER = 'x-csrf-token';
function generateCsrfToken() {
    return crypto_1.default.randomBytes(32).toString('hex');
}
function setCsrfToken(req, res, next) {
    if (!req.cookies?.[CSRF_COOKIE]) {
        const token = generateCsrfToken();
        res.cookie(CSRF_COOKIE, token, {
            httpOnly: false,
            secure: process.env.NODE_ENV === 'production',
            sameSite: 'strict',
            maxAge: 86400000, // 24 hours
        });
    }
    next();
}
/**
 * Validate that the CSRF token in the request header matches the one in the cookie.
 * Only applies to state-changing methods (POST, PUT, PATCH, DELETE).
 * GET/HEAD/OPTIONS are safe methods and skip validation.
 */
function validateCsrfToken(req, res, next) {
    const safeMethods = ['GET', 'HEAD', 'OPTIONS'];
    if (safeMethods.includes(req.method)) {
        return next();
    }
    // Skip CSRF for requests using Bearer token auth (mobile app, API clients).
    // CSRF protection is only relevant for cookie-based browser sessions.
    const authHeader = req.headers.authorization;
    if (authHeader?.startsWith('Bearer ')) {
        return next();
    }
    // Double-submit cookie pattern: only validate when the client already has
    // a CSRF cookie (i.e., they've made at least one prior request). On the
    // very first request the cookie hasn't been issued yet, so skip.
    const cookieToken = req.cookies?.[CSRF_COOKIE];
    if (!cookieToken) {
        return next();
    }
    const headerToken = req.headers[CSRF_HEADER];
    if (!headerToken || cookieToken !== headerToken) {
        return res.status(403).json({ message: 'Invalid CSRF token' });
    }
    next();
}
//# sourceMappingURL=csrf.js.map