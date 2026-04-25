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
      const { token: adminToken } = await createTestUser({ isAdmin: true, email: 'admin1@test.com' });
      const { user: admin2 } = await createTestUser({ isAdmin: true, email: 'admin2@test.com' });

      const res = await request(app)
        .put(`/api/v1/admin/users/${admin2.id}/suspend`)
        .set('Authorization', `Bearer ${adminToken}`);

      expect(res.status).toBe(400);
      expect(res.body.error).toBe('Cannot suspend an admin user');
    });

    // Audit Ch12-R002: prior code unsuspended a premium user as 'free',
    // stranding paid customers. Phase 1 added plan_before_suspend so the
    // unsuspend route restores the original plan.
    it('preserves the prior plan across suspend → unsuspend', async () => {
      const { token: adminToken } = await createTestUser({ isAdmin: true, email: 'admin-r002@test.com' });
      const { user: premiumUser } = await createTestUser({ email: 'paid@test.com', plan: 'premium' });

      // Suspend
      const sus = await request(app)
        .put(`/api/v1/admin/users/${premiumUser.id}/suspend`)
        .set('Authorization', `Bearer ${adminToken}`);
      expect(sus.status).toBe(200);

      // Unsuspend — plan should be restored to 'premium', not flattened to 'free'.
      const un = await request(app)
        .put(`/api/v1/admin/users/${premiumUser.id}/unsuspend`)
        .set('Authorization', `Bearer ${adminToken}`);
      expect(un.status).toBe(200);
      expect(un.body.data.plan).toBe('premium');
    });

    // Audit Ch12-T030: a JWT signed with isAdmin=true on behalf of a user
    // whose DB row has is_admin=false must NOT be allowed to reach admin
    // routes. The auth middleware re-fetches roles on every request so the
    // token claim is decorative.
    it('rejects a forged isAdmin token for a non-admin user', async () => {
      // Create an honest non-admin user, but mint an admin token claiming the
      // user IS admin. The token signature is valid (real secret), it's the
      // claim that's forged.
      const { user: notAdmin } = await createTestUser({ email: 'notadmin@test.com' });
      const jwt = require('jsonwebtoken');
      const { config } = require('../config');
      const forged = jwt.sign(
        { userId: notAdmin.id, email: notAdmin.email, isAdmin: true, isPartner: false },
        config.jwt.secret,
        { expiresIn: '1h' },
      );

      const res = await request(app)
        .get('/api/v1/admin/stats')
        .set('Authorization', `Bearer ${forged}`);

      expect(res.status).toBe(403);
    });
  });
});
