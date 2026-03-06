import request from 'supertest';
import { cleanDatabase } from './setup';
import { getTestApp, createTestUser, getAuthToken, getAdminToken } from './helpers';

const app = getTestApp();

describe('Admin routes - /api/v1/admin', () => {
  beforeEach(async () => {
    await cleanDatabase();
  });

  describe('GET /api/v1/admin/stats', () => {
    it('should return 403 for a non-admin user', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .get('/api/v1/admin/stats')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(403);
      expect(res.body.error).toBe('Admin access required');
    });

    it('should return 200 with stats for an admin user', async () => {
      const { token } = await createTestUser({ isAdmin: true });

      const res = await request(app)
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
      const { token } = await createTestUser();

      const res = await request(app)
        .get('/api/v1/admin/users')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(403);
    });

    it('should return a paginated user list for an admin', async () => {
      const { token } = await createTestUser({ isAdmin: true });
      // Create a couple more users to have data in the list
      await createTestUser({ email: 'user2@test.com' });
      await createTestUser({ email: 'user3@test.com' });

      const res = await request(app)
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
      const { user: targetUser } = await createTestUser({ email: 'target@test.com' });
      const { token } = await createTestUser();

      const res = await request(app)
        .put(`/api/v1/admin/users/${targetUser.id}/suspend`)
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(403);
    });

    it('should suspend a user', async () => {
      const { token: adminToken } = await createTestUser({ isAdmin: true });
      const { user: targetUser } = await createTestUser({ email: 'suspend-me@test.com' });

      const res = await request(app)
        .put(`/api/v1/admin/users/${targetUser.id}/suspend`)
        .set('Authorization', `Bearer ${adminToken}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.id).toBe(targetUser.id);
      expect(res.body.data.email).toBe('suspend-me@test.com');
      expect(res.body.message).toBe('User suspended');
    });

    it('should return 404 when suspending a non-existent user', async () => {
      const { token: adminToken } = await createTestUser({ isAdmin: true });

      const res = await request(app)
        .put('/api/v1/admin/users/00000000-0000-0000-0000-000000000000/suspend')
        .set('Authorization', `Bearer ${adminToken}`);

      expect(res.status).toBe(404);
      expect(res.body.error).toBe('User not found');
    });

    it('should return 400 when trying to suspend an admin user', async () => {
      const { token: adminToken, user: admin1 } = await createTestUser({ isAdmin: true, email: 'admin1@test.com' });
      const { user: admin2 } = await createTestUser({ isAdmin: true, email: 'admin2@test.com' });

      const res = await request(app)
        .put(`/api/v1/admin/users/${admin2.id}/suspend`)
        .set('Authorization', `Bearer ${adminToken}`);

      expect(res.status).toBe(400);
      expect(res.body.error).toBe('Cannot suspend an admin user');
    });
  });
});
