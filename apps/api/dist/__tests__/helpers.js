"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getTestApp = getTestApp;
exports.getAuthToken = getAuthToken;
exports.getAdminToken = getAdminToken;
exports.createTestUser = createTestUser;
exports.createTestHome = createTestHome;
exports.createTestItem = createTestItem;
const bcryptjs_1 = __importDefault(require("bcryptjs"));
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const crypto_1 = __importDefault(require("crypto"));
const db_1 = require("../db");
const config_1 = require("../config");
const app_1 = require("../app");
function getTestApp() {
    return (0, app_1.createApp)();
}
function getAuthToken(userId, extra = {}) {
    return jsonwebtoken_1.default.sign({ userId, email: `user-${userId}@test.com`, isAdmin: false, isPartner: false, ...extra }, config_1.config.jwt.secret, { expiresIn: '1h' });
}
function getAdminToken(userId) {
    return getAuthToken(userId, { isAdmin: true });
}
async function createTestUser(overrides = {}) {
    const email = (overrides.email || `test-${crypto_1.default.randomUUID()}@test.com`).toLowerCase();
    const passwordHash = await bcryptjs_1.default.hash(overrides.password || 'TestPassword123!', 4); // low rounds for speed
    const fullName = overrides.fullName || 'Test User';
    const isAdmin = overrides.isAdmin || false;
    const plan = overrides.plan || 'free';
    const result = await db_1.pool.query(`INSERT INTO users (email, password_hash, full_name, is_admin, plan, referral_code)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING *`, [email, passwordHash, fullName, isAdmin, plan, crypto_1.default.randomUUID().slice(0, 8)]);
    const user = result.rows[0];
    const token = getAuthToken(user.id, { email: user.email, isAdmin: user.is_admin });
    return { user, token };
}
async function createTestHome(userId, overrides = {}) {
    const name = overrides.name || 'Test Home';
    const result = await db_1.pool.query(`INSERT INTO homes (user_id, name, address, city, state, zip)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING *`, [userId, name, overrides.address || '123 Test St', overrides.city || 'Testville', overrides.state || 'TS', overrides.zip || '12345']);
    return result.rows[0];
}
async function createTestItem(userId, homeId, overrides = {}) {
    const name = overrides.name || 'Test Item';
    const purchaseDate = overrides.purchaseDate || '2024-01-01';
    const warrantyMonths = overrides.warrantyMonths || 12;
    // Calculate warranty_end_date from purchase_date + warranty_months
    const purchaseDateObj = new Date(purchaseDate);
    purchaseDateObj.setMonth(purchaseDateObj.getMonth() + warrantyMonths);
    const warrantyEndDate = overrides.warrantyEndDate || purchaseDateObj.toISOString().split('T')[0];
    const result = await db_1.pool.query(`INSERT INTO items (user_id, home_id, name, category, room, price, purchase_date, warranty_months, warranty_end_date)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
     RETURNING *`, [userId, homeId, name, overrides.category || 'other', overrides.room || 'living_room', overrides.price || 99.99, purchaseDate, warrantyMonths, warrantyEndDate]);
    return result.rows[0];
}
//# sourceMappingURL=helpers.js.map