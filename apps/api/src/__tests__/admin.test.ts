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
      expect(res.body.meta.pagination).toBeDefined();
      expect(res.body.meta.pagination).toHaveProperty('page');
      expect(res.body.meta.pagination).toHaveProperty('limit');
      expect(res.body.meta.pagination).toHaveProperty('total');
      expect(res.body.meta.pagination).toHaveProperty('total_pages');
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
      expect(res.body.meta?.message).toBe('User suspended');
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
      // H13: middleware pins iss + aud — the forged token must clear
      // signature + iss/aud verification so the admin re-fetch is the
      // gate this assertion actually probes. Without these, the test
      // would 401 at the middleware and never reach the admin re-check.
      const forged = jwt.sign(
        { userId: notAdmin.id, email: notAdmin.email, isAdmin: true, isPartner: false },
        config.jwt.secret,
        {
          expiresIn: '1h',
          issuer: config.jwt.issuer,
          audience: config.jwt.audience,
        },
      );

      const res = await request(app)
        .get('/api/v1/admin/stats')
        .set('Authorization', `Bearer ${forged}`);

      expect(res.status).toBe(403);
    });
  });

  // S3-12.4 / S1-D: admin stats must exclude soft-deleted users from
  // every users count so leadership numbers reflect live accounts.
  describe('Admin stats exclude soft-deleted users (S1-D)', () => {
    it('drops soft-deleted users from stats/full and user-activity', async () => {
      const { user: live } = await createTestUser({ email: 'live@test.com' });
      const { user: dead } = await createTestUser({ email: 'dead@test.com' });
      const { user: admin, token: adminToken } = await createTestUser({
        email: 'admin@test.com',
        isAdmin: true,
      });

      const { pool } = require('../db');
      // Mark `dead` as soft-deleted.
      await pool.query(
        `UPDATE users SET deleted_at = NOW(), plan = 'suspended' WHERE id = $1`,
        [dead.id],
      );

      const stats = await request(app)
        .get('/api/v1/admin/stats/full')
        .set('Authorization', `Bearer ${adminToken}`);
      expect(stats.status).toBe(200);
      // total_users counts live + admin (= 2), excluding `dead`.
      const total = Number(stats.body.data?.total_users ?? stats.body.total_users);
      expect(total).toBe(2);

      const activity = await request(app)
        .get('/api/v1/admin/users/activity')
        .set('Authorization', `Bearer ${adminToken}`);
      expect(activity.status).toBe(200);
      const ids = (activity.body.data ?? activity.body).map((r: any) => r.id);
      expect(ids).toContain(live.id);
      expect(ids).toContain(admin.id);
      expect(ids).not.toContain(dead.id);
    });
  });
});
