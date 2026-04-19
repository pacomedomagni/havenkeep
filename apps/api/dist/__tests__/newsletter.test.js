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
describe('Newsletter Routes', () => {
    let app;
    beforeAll(() => {
        app = (0, helpers_1.getTestApp)();
    });
    beforeEach(async () => {
        await (0, setup_1.cleanDatabase)();
    });
    describe('POST /api/v1/newsletter/subscribe', () => {
        it('should subscribe a valid email successfully', async () => {
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/newsletter/subscribe')
                .send({ email: 'newsletter@example.com' });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.message).toMatch(/successfully subscribed/i);
        });
        it('should return 400 when email is missing', async () => {
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/newsletter/subscribe')
                .send({});
            expect(res.status).toBe(400);
            expect(res.body.success).toBe(false);
        });
        it('should return 400 for an invalid email format', async () => {
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/newsletter/subscribe')
                .send({ email: 'not-an-email' });
            expect(res.status).toBe(400);
            expect(res.body.success).toBe(false);
        });
        it('should succeed (upsert) when subscribing with a duplicate email', async () => {
            const email = 'duplicate@example.com';
            // First subscription
            const first = await (0, supertest_1.default)(app)
                .post('/api/v1/newsletter/subscribe')
                .send({ email });
            expect(first.status).toBe(200);
            // Duplicate subscription — should still succeed
            const second = await (0, supertest_1.default)(app)
                .post('/api/v1/newsletter/subscribe')
                .send({ email });
            expect(second.status).toBe(200);
            expect(second.body.success).toBe(true);
        });
        it('should include a success message in the response body', async () => {
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/newsletter/subscribe')
                .send({ email: 'msg-check@example.com' });
            expect(res.status).toBe(200);
            expect(typeof res.body.message).toBe('string');
            expect(res.body.message.length).toBeGreaterThan(0);
        });
    });
});
//# sourceMappingURL=newsletter.test.js.map