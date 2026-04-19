"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const supertest_1 = __importDefault(require("supertest"));
const setup_1 = require("./setup");
const helpers_1 = require("./helpers");
const db_1 = require("../db");
const app = (0, helpers_1.getTestApp)();
/**
 * Insert a notification directly into the notification_history table for testing.
 */
async function createTestNotification(userId, overrides = {}) {
    const result = await db_1.pool.query(`INSERT INTO notification_history (user_id, type, title, body, sent_at)
     VALUES ($1, $2, $3, $4, NOW())
     RETURNING *`, [
        userId,
        overrides.type || 'system',
        overrides.title || 'Test Notification',
        overrides.body || 'This is a test notification',
    ]);
    return result.rows[0];
}
describe('Notifications routes - /api/v1/notifications', () => {
    beforeEach(async () => {
        await (0, setup_1.cleanDatabase)();
    });
    describe('GET /api/v1/notifications', () => {
        it('should require authentication', async () => {
            const res = await (0, supertest_1.default)(app).get('/api/v1/notifications');
            expect(res.status).toBe(401);
        });
        it('should return an empty list initially', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/notifications')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(Array.isArray(res.body.data)).toBe(true);
            expect(res.body.data.length).toBe(0);
            expect(res.body.pagination).toBeDefined();
            expect(res.body.pagination.total).toBe(0);
        });
        it('should return notifications for the user', async () => {
            const { user, token } = await (0, helpers_1.createTestUser)();
            await createTestNotification(user.id, { title: 'First Notification' });
            await createTestNotification(user.id, { title: 'Second Notification' });
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/notifications')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.length).toBe(2);
            expect(res.body.pagination.total).toBe(2);
        });
        it('should not return notifications belonging to another user', async () => {
            const { user: user1 } = await (0, helpers_1.createTestUser)({ email: 'user1@test.com' });
            const { token: token2 } = await (0, helpers_1.createTestUser)({ email: 'user2@test.com' });
            await createTestNotification(user1.id, { title: 'User1 Notification' });
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/notifications')
                .set('Authorization', `Bearer ${token2}`);
            expect(res.status).toBe(200);
            expect(res.body.data.length).toBe(0);
        });
    });
    describe('PUT /api/v1/notifications/:id/read', () => {
        it('should require authentication', async () => {
            const res = await (0, supertest_1.default)(app).put('/api/v1/notifications/00000000-0000-0000-0000-000000000000/read');
            expect(res.status).toBe(401);
        });
        it('should mark a notification as read', async () => {
            const { user, token } = await (0, helpers_1.createTestUser)();
            const notification = await createTestNotification(user.id);
            const res = await (0, supertest_1.default)(app)
                .put(`/api/v1/notifications/${notification.id}/read`)
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.message).toBe('Notification marked as read');
            expect(res.body.data).toHaveProperty('opened_at');
            expect(res.body.data.opened_at).not.toBeNull();
        });
        it('should return 404 for a non-existent notification', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .put('/api/v1/notifications/00000000-0000-0000-0000-000000000000/read')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(404);
            expect(res.body.error).toBe('Notification not found');
        });
        it('should be idempotent when marking the same notification as read twice', async () => {
            const { user, token } = await (0, helpers_1.createTestUser)();
            const notification = await createTestNotification(user.id);
            // Mark as read first time
            await (0, supertest_1.default)(app)
                .put(`/api/v1/notifications/${notification.id}/read`)
                .set('Authorization', `Bearer ${token}`);
            // Mark as read second time
            const res = await (0, supertest_1.default)(app)
                .put(`/api/v1/notifications/${notification.id}/read`)
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.opened_at).not.toBeNull();
        });
    });
    describe('GET /api/v1/notifications/unread-count', () => {
        it('should return 0 for a user with no notifications', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/notifications/unread-count')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.count).toBe(0);
        });
        it('should return the correct unread count', async () => {
            const { user, token } = await (0, helpers_1.createTestUser)();
            await createTestNotification(user.id);
            await createTestNotification(user.id);
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/notifications/unread-count')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.data.count).toBe(2);
        });
        it('should decrement unread count after marking one as read', async () => {
            const { user, token } = await (0, helpers_1.createTestUser)();
            const n1 = await createTestNotification(user.id);
            await createTestNotification(user.id);
            // Mark one as read
            await (0, supertest_1.default)(app)
                .put(`/api/v1/notifications/${n1.id}/read`)
                .set('Authorization', `Bearer ${token}`);
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/notifications/unread-count')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.data.count).toBe(1);
        });
    });
    describe('DELETE /api/v1/notifications/:id', () => {
        it('should delete a notification', async () => {
            const { user, token } = await (0, helpers_1.createTestUser)();
            const notification = await createTestNotification(user.id);
            const res = await (0, supertest_1.default)(app)
                .delete(`/api/v1/notifications/${notification.id}`)
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.message).toBe('Notification deleted successfully');
            // Verify it is gone
            const listRes = await (0, supertest_1.default)(app)
                .get('/api/v1/notifications')
                .set('Authorization', `Bearer ${token}`);
            expect(listRes.body.data.length).toBe(0);
        });
        it('should return 404 when deleting a non-existent notification', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .delete('/api/v1/notifications/00000000-0000-0000-0000-000000000000')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(404);
        });
    });
});
//# sourceMappingURL=notifications.test.js.map