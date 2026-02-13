"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.authenticate = authenticate;
exports.requireAdmin = requireAdmin;
exports.requirePremium = requirePremium;
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const config_1 = require("../config");
const errorHandler_1 = require("./errorHandler");
const db_1 = require("../db");
const token_blacklist_1 = require("../utils/token-blacklist");
async function authenticate(req, res, next) {
    try {
        const authHeader = req.headers.authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            throw new errorHandler_1.AppError('No token provided', 401);
        }
        const token = authHeader.substring(7);
        // Check if token has been revoked
        if (await (0, token_blacklist_1.isTokenBlacklisted)(token)) {
            throw new errorHandler_1.AppError('Token has been revoked', 401);
        }
        const decoded = jsonwebtoken_1.default.verify(token, config_1.config.jwt.secret);
        // Get user from database
        const result = await (0, db_1.query)(`SELECT u.id, u.email, u.plan, u.is_admin,
              (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = u.id AND p.is_active = TRUE)) as is_partner
       FROM users u WHERE u.id = $1`, [decoded.userId]);
        if (result.rows.length === 0) {
            throw new errorHandler_1.AppError('Invalid token', 401);
        }
        req.user = {
            id: result.rows[0].id,
            email: result.rows[0].email,
            plan: result.rows[0].plan,
            isAdmin: result.rows[0].is_admin,
            isPartner: result.rows[0].is_partner,
        };
        next();
    }
    catch (error) {
        if (error instanceof jsonwebtoken_1.default.JsonWebTokenError) {
            next(new errorHandler_1.AppError('Invalid token', 401));
        }
        else {
            next(error);
        }
    }
}
function requireAdmin(req, res, next) {
    if (!req.user?.isAdmin) {
        throw new errorHandler_1.AppError('Admin access required', 403);
    }
    next();
}
function requirePremium(req, res, next) {
    if (req.user?.plan !== 'premium') {
        throw new errorHandler_1.AppError('Premium plan required', 403);
    }
    next();
}
//# sourceMappingURL=auth.js.map