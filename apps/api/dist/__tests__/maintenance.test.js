"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const supertest_1 = __importDefault(require("supertest"));
const setup_1 = require("./setup");
const helpers_1 = require("./helpers");
const app = (0, helpers_1.getTestApp)();
describe('Maintenance routes - /api/v1/maintenance', () => {
    beforeEach(async () => {
        await (0, setup_1.cleanDatabase)();
    });
    describe('GET /api/v1/maintenance/schedules/:category', () => {
        it('should require authentication', async () => {
            const res = await (0, supertest_1.default)(app).get('/api/v1/maintenance/schedules/hvac');
            expect(res.status).toBe(401);
        });
        it('should return schedules for a valid category', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/maintenance/schedules/hvac')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(Array.isArray(res.body.data)).toBe(true);
        });
        it('should return 400 for an invalid category', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/maintenance/schedules/invalid_category_xyz')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(400);
        });
    });
    describe('GET /api/v1/maintenance/due', () => {
        it('should require authentication', async () => {
            const res = await (0, supertest_1.default)(app).get('/api/v1/maintenance/due');
            expect(res.status).toBe(401);
        });
        it('should return maintenance summary for authenticated user', async () => {
            const { user, token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/maintenance/due')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data).toHaveProperty('total_due');
            expect(res.body.data).toHaveProperty('total_overdue');
            expect(res.body.data).toHaveProperty('items');
            expect(Array.isArray(res.body.data.items)).toBe(true);
        });
    });
    describe('POST /api/v1/maintenance/log', () => {
        it('should require authentication', async () => {
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/maintenance/log')
                .send({ item_id: '00000000-0000-0000-0000-000000000000', task_name: 'Test task' });
            expect(res.status).toBe(401);
        });
        it('should log a maintenance task for a valid item', async () => {
            const { user, token } = await (0, helpers_1.createTestUser)();
            const home = await (0, helpers_1.createTestHome)(user.id);
            const item = await (0, helpers_1.createTestItem)(user.id, home.id);
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/maintenance/log')
                .set('Authorization', `Bearer ${token}`)
                .send({
                item_id: item.id,
                task_name: 'Changed HVAC filter',
                notes: 'Used a MERV-13 filter',
                cost: 25.99,
            });
            expect(res.status).toBe(201);
            expect(res.body.success).toBe(true);
            expect(res.body.data).toHaveProperty('id');
            expect(res.body.data.item_id).toBe(item.id);
            expect(res.body.data.task_name).toBe('Changed HVAC filter');
            expect(res.body.message).toBe('Maintenance task logged successfully');
        });
        it('should return 404 when logging for a non-existent item', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/maintenance/log')
                .set('Authorization', `Bearer ${token}`)
                .send({
                item_id: '00000000-0000-0000-0000-000000000000',
                task_name: 'Some task',
            });
            expect(res.status).toBe(404);
        });
        it('should return 400 when task_name is missing', async () => {
            const { user, token } = await (0, helpers_1.createTestUser)();
            const home = await (0, helpers_1.createTestHome)(user.id);
            const item = await (0, helpers_1.createTestItem)(user.id, home.id);
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/maintenance/log')
                .set('Authorization', `Bearer ${token}`)
                .send({
                item_id: item.id,
            });
            expect(res.status).toBe(400);
        });
    });
    describe('GET /api/v1/maintenance/history', () => {
        it('should require authentication', async () => {
            const res = await (0, supertest_1.default)(app).get('/api/v1/maintenance/history');
            expect(res.status).toBe(401);
        });
        it('should return empty history for a new user', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/maintenance/history')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(Array.isArray(res.body.data)).toBe(true);
            expect(res.body.data.length).toBe(0);
            expect(res.body.pagination).toBeDefined();
            expect(res.body.pagination.total).toBe(0);
        });
        it('should return history after logging maintenance', async () => {
            const { user, token } = await (0, helpers_1.createTestUser)();
            const home = await (0, helpers_1.createTestHome)(user.id);
            const item = await (0, helpers_1.createTestItem)(user.id, home.id);
            // Log a maintenance task first
            await (0, supertest_1.default)(app)
                .post('/api/v1/maintenance/log')
                .set('Authorization', `Bearer ${token}`)
                .send({
                item_id: item.id,
                task_name: 'Cleaned gutters',
            });
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/maintenance/history')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.length).toBe(1);
            expect(res.body.data[0].task_name).toBe('Cleaned gutters');
            expect(res.body.pagination.total).toBe(1);
        });
    });
    describe('DELETE /api/v1/maintenance/history/:id', () => {
        it('should require authentication', async () => {
            const res = await (0, supertest_1.default)(app).delete('/api/v1/maintenance/history/00000000-0000-0000-0000-000000000000');
            expect(res.status).toBe(401);
        });
        it('should delete a maintenance log entry', async () => {
            const { user, token } = await (0, helpers_1.createTestUser)();
            const home = await (0, helpers_1.createTestHome)(user.id);
            const item = await (0, helpers_1.createTestItem)(user.id, home.id);
            // Log a maintenance task
            const logRes = await (0, supertest_1.default)(app)
                .post('/api/v1/maintenance/log')
                .set('Authorization', `Bearer ${token}`)
                .send({
                item_id: item.id,
                task_name: 'Replaced water filter',
            });
            const entryId = logRes.body.data.id;
            // Delete it
            const res = await (0, supertest_1.default)(app)
                .delete(`/api/v1/maintenance/history/${entryId}`)
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.message).toBe('Maintenance log entry deleted successfully');
            // Verify it is gone
            const historyRes = await (0, supertest_1.default)(app)
                .get('/api/v1/maintenance/history')
                .set('Authorization', `Bearer ${token}`);
            expect(historyRes.body.data.length).toBe(0);
        });
        it('should return 404 when deleting a non-existent entry', async () => {
            const { token } = await (0, helpers_1.createTestUser)();
            const res = await (0, supertest_1.default)(app)
                .delete('/api/v1/maintenance/history/00000000-0000-0000-0000-000000000000')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(404);
        });
    });
});
//# sourceMappingURL=maintenance.test.js.map