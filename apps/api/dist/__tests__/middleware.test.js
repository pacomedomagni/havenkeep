"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const supertest_1 = __importDefault(require("supertest"));
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const setup_1 = require("./setup");
const helpers_1 = require("./helpers");
const config_1 = require("../config");
const app = (0, helpers_1.getTestApp)();
describe('Middleware', () => {
    beforeEach(async () => {
        await (0, setup_1.cleanDatabase)();
    });
    describe('Auth middleware', () => {
        it('should return 401 when no token is provided', async () => {
            const res = await (0, supertest_1.default)(app).get('/api/v1/notifications');
            expect(res.status).toBe(401);
            expect(res.body.error).toBe('No token provided');
        });
        it('should return 401 when an invalid token is provided', async () => {
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/notifications')
                .set('Authorization', 'Bearer invalid-token-here');
            expect(res.status).toBe(401);
            expect(res.body.error).toBe('Invalid token');
        });
        it('should return 401 when an expired token is provided', async () => {
            const expiredToken = jsonwebtoken_1.default.sign({ userId: '00000000-0000-0000-0000-000000000000', email: 'expired@test.com', isAdmin: false, isPartner: false }, config_1.config.jwt.secret, { expiresIn: '-1s' });
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/notifications')
                .set('Authorization', `Bearer ${expiredToken}`);
            expect(res.status).toBe(401);
            expect(res.body.error).toBe('Invalid token');
        });
        it('should pass through with a valid token', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/notifications')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
        });
    });
    describe('404 handler', () => {
        it('should return 404 for an unknown endpoint', async () => {
            const res = await (0, supertest_1.default)(app).get('/api/v1/nonexistent-endpoint');
            expect(res.status).toBe(404);
            expect(res.body.error).toBe('Not found');
            expect(res.body.suggestion).toBe('Check API documentation for available endpoints');
        });
    });
    describe('Error handler', () => {
        it('should return the correct status code and message for an AppError', async () => {
            // Trigger a known AppError: admin route accessed by non-admin user returns 403
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/admin/stats')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(403);
            expect(res.body.error).toBe('Admin access required');
            expect(res.body.statusCode).toBe(403);
        });
    });
});
//# sourceMappingURL=middleware.test.js.map