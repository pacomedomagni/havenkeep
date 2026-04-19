"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const supertest_1 = __importDefault(require("supertest"));
const setup_1 = require("./setup");
const helpers_1 = require("./helpers");
const app = (0, helpers_1.getTestApp)();
describe('Audit API - /api/v1/audit', () => {
    beforeEach(async () => {
        await (0, setup_1.cleanDatabase)();
    });
    // ──────────────────────────────── GET /audit/logs ────────────────────────────────
    describe('GET /api/v1/audit/logs', () => {
        it('should return own audit logs for authenticated user', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/audit/logs')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(Array.isArray(res.body.data)).toBe(true);
            expect(res.body.pagination).toBeDefined();
        });
        it('should reject without authentication (401)', async () => {
            const res = await (0, supertest_1.default)(app).get('/api/v1/audit/logs');
            expect(res.status).toBe(401);
        });
    });
    // ──────────────────────────────── GET /audit/logs/me ────────────────────────────────
    describe('GET /api/v1/audit/logs/me', () => {
        it('should return current user\'s own audit logs', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/audit/logs/me')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(Array.isArray(res.body.data)).toBe(true);
            expect(res.body.pagination).toBeDefined();
            expect(res.body.pagination.total).toBeGreaterThanOrEqual(0);
        });
    });
    // ──────────────────────────────── GET /audit/security ────────────────────────────────
    describe('GET /api/v1/audit/security', () => {
        it('should allow admin to access security events', async () => {
            const { user } = await (0, helpers_1.createTestUser)({ isAdmin: true });
            const adminToken = (0, helpers_1.getAdminToken)(user.id);
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/audit/security')
                .set('Authorization', `Bearer ${adminToken}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(Array.isArray(res.body.data)).toBe(true);
        });
        it('should reject non-admin access to security events (403)', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/audit/security')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(403);
        });
    });
    // ──────────────────────────────── GET /audit/stats ────────────────────────────────
    describe('GET /api/v1/audit/stats', () => {
        it('should allow admin to get audit stats', async () => {
            const { user } = await (0, helpers_1.createTestUser)({ isAdmin: true });
            const adminToken = (0, helpers_1.getAdminToken)(user.id);
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/audit/stats')
                .set('Authorization', `Bearer ${adminToken}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data).toBeDefined();
        });
        it('should reject non-admin access to stats (403)', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/audit/stats')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(403);
        });
    });
    // ──────────────────────────────── GET /audit/activity-summary ────────────────────────────────
    describe('GET /api/v1/audit/activity-summary', () => {
        it('should allow admin to get activity summary', async () => {
            const { user } = await (0, helpers_1.createTestUser)({ isAdmin: true });
            const adminToken = (0, helpers_1.getAdminToken)(user.id);
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/audit/activity-summary')
                .set('Authorization', `Bearer ${adminToken}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data).toBeDefined();
        });
        it('should reject non-admin access to activity summary (403)', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/audit/activity-summary')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(403);
        });
    });
    // ──────────────────────────────── POST /audit/cleanup ────────────────────────────────
    describe('POST /api/v1/audit/cleanup', () => {
        it('should allow admin to trigger cleanup', async () => {
            const { user } = await (0, helpers_1.createTestUser)({ isAdmin: true });
            const adminToken = (0, helpers_1.getAdminToken)(user.id);
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/audit/cleanup')
                .set('Authorization', `Bearer ${adminToken}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.message).toBe('Audit log cleanup completed');
        });
        it('should reject non-admin from triggering cleanup (403)', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/audit/cleanup')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(403);
        });
    });
});
//# sourceMappingURL=audit.test.js.map