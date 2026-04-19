"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const supertest_1 = __importDefault(require("supertest"));
const setup_1 = require("./setup");
const helpers_1 = require("./helpers");
// Rate limiters are module-level singletons (in-memory stores) that persist
// across app instances. Mock them all as pass-through in tests.
jest.mock('../middleware/rateLimiter', () => {
    const pass = (_req, _res, next) => next();
    return {
        __esModule: true,
        authRateLimiter: pass,
        refreshRateLimiter: pass,
        passwordResetRateLimiter: pass,
        uploadRateLimiter: pass,
        activationCodeRateLimiter: pass,
        verifyPremiumRateLimiter: pass,
        passwordChangeRateLimiter: pass,
        writeRateLimiter: pass,
        giftResendRateLimiter: pass,
        receiptScanRateLimiter: pass,
        newsletterRateLimiter: pass,
        contactRateLimiter: pass,
        initializeRateLimiter: jest.fn().mockResolvedValue(undefined),
        shutdownRateLimiter: jest.fn().mockResolvedValue(undefined),
    };
});
describe('Stats API - /api/v1/stats', () => {
    let app;
    beforeEach(async () => {
        app = (0, helpers_1.getTestApp)();
        await (0, setup_1.cleanDatabase)();
    });
    // ──────────────────────────────── Dashboard ────────────────────────────────
    describe('GET /api/v1/stats/dashboard', () => {
        it('should return dashboard stats for authenticated user', async () => {
            const { user, token } = await (0, helpers_1.createTestUser)();
            const home = await (0, helpers_1.createTestHome)(user.id);
            await (0, helpers_1.createTestItem)(user.id, home.id, { name: 'Fridge' });
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/stats/dashboard')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data).toBeDefined();
        });
        it('should reject without authentication (401)', async () => {
            const res = await (0, supertest_1.default)(app).get('/api/v1/stats/dashboard');
            expect(res.status).toBe(401);
        });
    });
    // ──────────────────────────────── Health Score ────────────────────────────────
    describe('GET /api/v1/stats/health-score', () => {
        it('should return health score breakdown', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/stats/health-score')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data).toBeDefined();
        });
    });
    describe('POST /api/v1/stats/health-score/calculate', () => {
        it('should recalculate health score', async () => {
            const { user, token } = await (0, helpers_1.createTestUser)();
            const home = await (0, helpers_1.createTestHome)(user.id);
            await (0, helpers_1.createTestItem)(user.id, home.id, { name: 'Boiler' });
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/stats/health-score/calculate')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data).toHaveProperty('score');
            expect(res.body.message).toBe('Health score recalculated');
        });
    });
    // ──────────────────────────────── Analytics ────────────────────────────────
    describe('GET /api/v1/stats/analytics', () => {
        it('should return user analytics', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/stats/analytics')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data).toBeDefined();
        });
    });
    // ──────────────────────────────── Items Needing Attention ────────────────────────────────
    describe('GET /api/v1/stats/items-needing-attention', () => {
        it('should return items needing attention', async () => {
            const { user, token } = await (0, helpers_1.createTestUser)();
            const home = await (0, helpers_1.createTestHome)(user.id);
            // Create an item with a warranty that has already expired
            await (0, helpers_1.createTestItem)(user.id, home.id, {
                name: 'Old HVAC',
                purchaseDate: '2018-01-01',
                warrantyMonths: 12,
                warrantyEndDate: '2019-01-01',
            });
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/stats/items-needing-attention')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data).toBeDefined();
        });
    });
    // ──────────────────────────────── Track Engagement ────────────────────────────────
    describe('POST /api/v1/stats/track-engagement', () => {
        it('should track engagement event', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/stats/track-engagement')
                .set('Authorization', `Bearer ${token}`)
                .send({ type: 'app_open', session_duration: 120 });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.message).toBe('Engagement tracked');
        });
        it('should reject track-engagement with missing type (400)', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/stats/track-engagement')
                .set('Authorization', `Bearer ${token}`)
                .send({ session_duration: 60 });
            expect(res.status).toBe(400);
        });
    });
    // ──────────────────────────────── Track Feature ────────────────────────────────
    describe('POST /api/v1/stats/track-feature', () => {
        it('should track feature usage', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/stats/track-feature')
                .set('Authorization', `Bearer ${token}`)
                .send({ feature: 'warranty_claims' });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.message).toBe('Feature usage tracked');
        });
        it('should reject track-feature with missing feature (400)', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/stats/track-feature')
                .set('Authorization', `Bearer ${token}`)
                .send({});
            expect(res.status).toBe(400);
        });
    });
});
//# sourceMappingURL=stats.test.js.map