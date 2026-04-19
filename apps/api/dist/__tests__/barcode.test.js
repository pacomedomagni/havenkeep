"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const supertest_1 = __importDefault(require("supertest"));
const setup_1 = require("./setup");
const helpers_1 = require("./helpers");
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
// ------------------------------------------------------------------
// Helpers for building mock fetch responses
// ------------------------------------------------------------------
function makeFetchResponse(status, body) {
    return {
        ok: status >= 200 && status < 300,
        status,
        json: async () => body,
        text: async () => JSON.stringify(body),
    };
}
const SAMPLE_PRODUCT_RESPONSE = {
    items: [
        {
            title: 'Samsung 65" 4K TV',
            brand: 'Samsung',
            category: 'Electronics',
            description: 'A great 4K television',
            images: ['https://example.com/tv.jpg'],
        },
    ],
};
describe('Barcode Routes', () => {
    let app;
    let premiumToken;
    let freeToken;
    let fetchSpy;
    beforeAll(() => {
        app = (0, helpers_1.getTestApp)();
    });
    beforeEach(async () => {
        await (0, setup_1.cleanDatabase)();
        // Create a premium user and a free user for auth checks
        const premiumUser = await (0, helpers_1.createTestUser)({ plan: 'premium' });
        premiumToken = premiumUser.token;
        const freeUser = await (0, helpers_1.createTestUser)({ plan: 'free' });
        freeToken = freeUser.token;
        // Spy on the global fetch used by the barcode route
        fetchSpy = jest.spyOn(global, 'fetch');
    });
    afterEach(() => {
        fetchSpy.mockRestore();
    });
    describe('POST /api/v1/barcode/lookup', () => {
        it('should return 401 when no auth token is provided', async () => {
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/barcode/lookup')
                .send({ barcode: '012345678905' });
            expect(res.status).toBe(401);
        });
        it('should return 403 for a non-premium (free) user', async () => {
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/barcode/lookup')
                .set('Authorization', `Bearer ${freeToken}`)
                .send({ barcode: '012345678905' });
            expect(res.status).toBe(403);
        });
        it('should return product data on a successful barcode lookup', async () => {
            fetchSpy.mockResolvedValueOnce(makeFetchResponse(200, SAMPLE_PRODUCT_RESPONSE));
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/barcode/lookup')
                .set('Authorization', `Bearer ${premiumToken}`)
                .send({ barcode: '012345678905' });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data).toMatchObject({
                barcode: '012345678905',
                brand: 'Samsung',
                product_name: 'Samsung 65" 4K TV',
            });
        });
        it('should return null product fields when the barcode is not found (API 404)', async () => {
            fetchSpy.mockResolvedValueOnce(makeFetchResponse(404, { message: 'Not found' }));
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/barcode/lookup')
                .set('Authorization', `Bearer ${premiumToken}`)
                .send({ barcode: '012345678905' });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data).toMatchObject({
                barcode: '012345678905',
                brand: null,
                product_name: null,
            });
        });
        it('should return 400 for an invalid barcode format', async () => {
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/barcode/lookup')
                .set('Authorization', `Bearer ${premiumToken}`)
                .send({ barcode: 'INVALID' });
            expect(res.status).toBe(400);
        });
        it('should serve a cached result on the second lookup without hitting fetch again', async () => {
            // First call — prime the Redis cache
            fetchSpy.mockResolvedValueOnce(makeFetchResponse(200, SAMPLE_PRODUCT_RESPONSE));
            await (0, supertest_1.default)(app)
                .post('/api/v1/barcode/lookup')
                .set('Authorization', `Bearer ${premiumToken}`)
                .send({ barcode: '012345678905' });
            expect(fetchSpy).toHaveBeenCalledTimes(1);
            // Second call — should hit the Redis cache; fetch must NOT be called again
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/barcode/lookup')
                .set('Authorization', `Bearer ${premiumToken}`)
                .send({ barcode: '012345678905' });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.barcode).toBe('012345678905');
            // fetch was not called a second time because the result was cached
            expect(fetchSpy).toHaveBeenCalledTimes(1);
        });
    });
});
//# sourceMappingURL=barcode.test.js.map