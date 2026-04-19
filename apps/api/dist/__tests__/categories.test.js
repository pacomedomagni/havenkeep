"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const supertest_1 = __importDefault(require("supertest"));
const setup_1 = require("./setup");
const helpers_1 = require("./helpers");
const app = (0, helpers_1.getTestApp)();
describe('Categories API - /api/v1/categories', () => {
    beforeEach(async () => {
        await (0, setup_1.cleanDatabase)();
    });
    // ──────────────────────────────── Category Defaults ────────────────────────────────
    describe('GET /api/v1/categories/defaults', () => {
        it('should return category defaults for authenticated user', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/categories/defaults')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(Array.isArray(res.body.data)).toBe(true);
        });
        it('should reject without authentication (401)', async () => {
            const res = await (0, supertest_1.default)(app).get('/api/v1/categories/defaults');
            expect(res.status).toBe(401);
        });
        it('should return results sorted by category', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/categories/defaults')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            const categories = res.body.data.map((row) => row.category);
            if (categories.length > 1) {
                for (let i = 1; i < categories.length; i++) {
                    expect(categories[i].localeCompare(categories[i - 1])).toBeGreaterThanOrEqual(0);
                }
            }
        });
    });
    // ──────────────────────────────── Brand Suggestions ────────────────────────────────
    describe('GET /api/v1/categories/:category/brands', () => {
        it('should return brand suggestions for a valid category', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/categories/refrigerator/brands')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(Array.isArray(res.body.data)).toBe(true);
        });
        it('should return 500 for an invalid enum category value', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/categories/unknown_category_xyz/brands')
                .set('Authorization', `Bearer ${token}`);
            // PostgreSQL rejects unknown enum values
            expect(res.status).toBe(500);
        });
    });
});
//# sourceMappingURL=categories.test.js.map