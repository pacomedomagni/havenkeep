"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const supertest_1 = __importDefault(require("supertest"));
const setup_1 = require("./setup");
const helpers_1 = require("./helpers");
const app = (0, helpers_1.getTestApp)();
describe('Admin routes - /api/v1/admin', () => {
    beforeEach(async () => {
        await (0, setup_1.cleanDatabase)();
    });
    describe('GET /api/v1/admin/stats', () => {
        it('should return 403 for a non-admin user', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/admin/stats')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(403);
            expect(res.body.error).toBe('Admin access required');
        });
        it('should return 200 with stats for an admin user', async () => {
            const { token } = await (0, helpers_1.createTestUser)({ isAdmin: true });
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/admin/stats')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data).toHaveProperty('total_users');
            expect(res.body.data).toHaveProperty('premium_users');
            expect(res.body.data).toHaveProperty('total_items');
        });
    });
    describe('GET /api/v1/admin/users', () => {
        it('should return 403 for a non-admin user', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/admin/users')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(403);
        });
        it('should return a paginated user list for an admin', async () => {
            const { token } = await (0, helpers_1.createTestUser)({ isAdmin: true });
            // Create a couple more users to have data in the list
            await (0, helpers_1.createTestUser)({ email: 'user2@test.com' });
            await (0, helpers_1.createTestUser)({ email: 'user3@test.com' });
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/admin/users')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(Array.isArray(res.body.data)).toBe(true);
            expect(res.body.data.length).toBeGreaterThanOrEqual(3);
            expect(res.body.pagination).toBeDefined();
            expect(res.body.pagination).toHaveProperty('page');
            expect(res.body.pagination).toHaveProperty('limit');
            expect(res.body.pagination).toHaveProperty('total');
            expect(res.body.pagination).toHaveProperty('total_pages');
        });
    });
    describe('PUT /api/v1/admin/users/:id/suspend', () => {
        it('should return 403 for a non-admin user', async () => {
            const { user: targetUser } = await (0, helpers_1.createTestUser)({ email: 'target@test.com' });
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .put(`/api/v1/admin/users/${targetUser.id}/suspend`)
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(403);
        });
        it('should suspend a user', async () => {
            const { token: adminToken } = await (0, helpers_1.createTestUser)({ isAdmin: true });
            const { user: targetUser } = await (0, helpers_1.createTestUser)({ email: 'suspend-me@test.com' });
            const res = await (0, supertest_1.default)(app)
                .put(`/api/v1/admin/users/${targetUser.id}/suspend`)
                .set('Authorization', `Bearer ${adminToken}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.id).toBe(targetUser.id);
            expect(res.body.data.email).toBe('suspend-me@test.com');
            expect(res.body.message).toBe('User suspended');
        });
        it('should return 404 when suspending a non-existent user', async () => {
            const { token: adminToken } = await (0, helpers_1.createTestUser)({ isAdmin: true });
            const res = await (0, supertest_1.default)(app)
                .put('/api/v1/admin/users/00000000-0000-0000-0000-000000000000/suspend')
                .set('Authorization', `Bearer ${adminToken}`);
            expect(res.status).toBe(404);
            expect(res.body.error).toBe('User not found');
        });
        it('should return 400 when trying to suspend an admin user', async () => {
            const { token: adminToken, user: admin1 } = await (0, helpers_1.createTestUser)({ isAdmin: true, email: 'admin1@test.com' });
            const { user: admin2 } = await (0, helpers_1.createTestUser)({ isAdmin: true, email: 'admin2@test.com' });
            const res = await (0, supertest_1.default)(app)
                .put(`/api/v1/admin/users/${admin2.id}/suspend`)
                .set('Authorization', `Bearer ${adminToken}`);
            expect(res.status).toBe(400);
            expect(res.body.error).toBe('Cannot suspend an admin user');
        });
    });
});
//# sourceMappingURL=admin.test.js.map