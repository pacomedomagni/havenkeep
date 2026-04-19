"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateUniqueReferralCode = generateUniqueReferralCode;
const crypto_1 = __importDefault(require("crypto"));
const db_1 = require("../db");
const REFERRAL_CODE_PREFIX = 'HK';
const REFERRAL_CODE_ATTEMPTS = 20;
function formatReferralCode(raw) {
    const upper = raw.toUpperCase();
    return `${REFERRAL_CODE_PREFIX}-${upper.slice(0, 4)}-${upper.slice(4, 8)}`;
}
async function generateUniqueReferralCode() {
    for (let attempt = 0; attempt < REFERRAL_CODE_ATTEMPTS; attempt += 1) {
        const raw = crypto_1.default.randomBytes(4).toString('hex');
        const code = formatReferralCode(raw);
        const exists = await (0, db_1.query)(`SELECT 1 FROM users WHERE referral_code = $1`, [code]);
        if (exists.rows.length === 0) {
            return code;
        }
    }
    // Fallback: append a UUID suffix to guarantee uniqueness
    const uuid = crypto_1.default.randomUUID().replace(/-/g, '').slice(0, 8).toUpperCase();
    const fallbackCode = `${REFERRAL_CODE_PREFIX}-${uuid.slice(0, 4)}-${uuid.slice(4, 8)}`;
    const exists = await (0, db_1.query)(`SELECT 1 FROM users WHERE referral_code = $1`, [fallbackCode]);
    if (exists.rows.length === 0) {
        return fallbackCode;
    }
    // Extremely unlikely: use full UUID for absolute uniqueness
    const fullUuid = crypto_1.default.randomUUID().replace(/-/g, '').toUpperCase();
    return `${REFERRAL_CODE_PREFIX}-${fullUuid.slice(0, 4)}-${fullUuid.slice(4, 12)}`;
}
//# sourceMappingURL=referral-code.js.map