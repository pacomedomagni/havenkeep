"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateCsrfToken = generateCsrfToken;
exports.csrfProtection = csrfProtection;
exports.setCsrfToken = setCsrfToken;
const crypto_1 = __importDefault(require("crypto"));
// Double-submit cookie pattern CSRF implementation
// The token cookie is NOT httpOnly so the client JS can read it and
// send it back via the x-csrf-token header. The server then compares
// the header value against the cookie value.
const CSRF_HEADER = 'x-csrf-token';
const CSRF_COOKIE = 'csrf_token';
function generateCsrfToken() {
    return crypto_1.default.randomBytes(32).toString('hex');
}
function csrfProtection(req, res, next) {
    // Skip CSRF for GET, HEAD, OPTIONS (safe methods)
    if (['GET', 'HEAD', 'OPTIONS'].includes(req.method)) {
        return next();
    }
    const tokenFromHeader = req.get(CSRF_HEADER);
    const tokenFromCookie = req.cookies?.[CSRF_COOKIE];
    if (!tokenFromHeader ||
        !tokenFromCookie ||
        tokenFromHeader.length !== tokenFromCookie.length ||
        !crypto_1.default.timingSafeEqual(Buffer.from(tokenFromHeader), Buffer.from(tokenFromCookie))) {
        res.status(403).json({ error: 'Invalid CSRF token', statusCode: 403 });
        return;
    }
    // Rotate token after successful validation
    const newToken = generateCsrfToken();
    res.cookie(CSRF_COOKIE, newToken, {
        httpOnly: false, // Client JS must read this to include in header
        secure: process.env.NODE_ENV === 'production',
        sameSite: 'strict',
        maxAge: 86400000, // 24 hours
    });
    next();
}
function setCsrfToken(req, res, next) {
    if (!req.cookies?.[CSRF_COOKIE]) {
        const token = generateCsrfToken();
        res.cookie(CSRF_COOKIE, token, {
            httpOnly: false, // Client JS must read this to include in header
            secure: process.env.NODE_ENV === 'production',
            sameSite: 'strict',
            maxAge: 86400000, // 24 hours
        });
    }
    next();
}
//# sourceMappingURL=csrf.js.map