"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateUniqueReferralCode = generateUniqueReferralCode;
const crypto_1 = __importDefault(require("crypto"));
const db_1 = require("../db");
const REFERRAL_CODE_PREFIX = 'HK';
const REFERRAL_CODE_ATTEMPTS = 5;
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
    throw new Error('Failed to generate unique referral code');
}
//# sourceMappingURL=referral-code.js.map