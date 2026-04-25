import request from 'supertest';
import { cleanDatabase } from './setup';
import { getTestApp, createTestUser, getAdminToken } from './helpers';

const app = getTestApp();

describe('Audit API - /api/v1/audit', () => {
  beforeEach(async () => {
    await cleanDatabase();
  });

  // ──────────────────────────────── GET /audit/logs ────────────────────────────────

  describe('GET /api/v1/audit/logs', () => {
    it('should return own audit logs for authenticated user', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .get('/api/v1/audit/logs')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(Array.isArray(res.body.data)).toBe(true);
      expect(res.body.pagination).toBeDefined();
    });

    it('should reject without authentication (401)', async () => {
      const res = await request(app).get('/api/v1/audit/logs');

      expect(res.status).toBe(401);
    });
  });

  // ──────────────────────────────── GET /audit/logs/me ────────────────────────────────

  describe('GET /api/v1/audit/logs/me', () => {
    it('should return current user\'s own audit logs', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
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
      const { user } = await createTestUser({ isAdmin: true });
      const adminToken = getAdminToken(user.id, user.email);

      const res = await request(app)
        .get('/api/v1/audit/security')
        .set('Authorization', `Bearer ${adminToken}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(Array.isArray(res.body.data)).toBe(true);
    });

    it('should reject non-admin access to security events (403)', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .get('/api/v1/audit/security')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(403);
    });
  });

  // ──────────────────────────────── GET /audit/stats ────────────────────────────────

  describe('GET /api/v1/audit/stats', () => {
    it('should allow admin to get audit stats', async () => {
      const { user } = await createTestUser({ isAdmin: true });
      const adminToken = getAdminToken(user.id, user.email);

      const res = await request(app)
        .get('/api/v1/audit/stats')
        .set('Authorization', `Bearer ${adminToken}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toBeDefined();
    });

    it('should reject non-admin access to stats (403)', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .get('/api/v1/audit/stats')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(403);
    });
  });

  // ──────────────────────────────── GET /audit/activity-summary ────────────────────────────────

  describe('GET /api/v1/audit/activity-summary', () => {
    it('should allow admin to get activity summary', async () => {
      const { user } = await createTestUser({ isAdmin: true });
      const adminToken = getAdminToken(user.id, user.email);

      const res = await request(app)
        .get('/api/v1/audit/activity-summary')
        .set('Authorization', `Bearer ${adminToken}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toBeDefined();
    });

    it('should reject non-admin access to activity summary (403)', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .get('/api/v1/audit/activity-summary')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(403);
    });
  });

  // ──────────────────────────────── POST /audit/cleanup ────────────────────────────────

  describe('POST /api/v1/audit/cleanup', () => {
    it('should allow admin to trigger cleanup', async () => {
      const { user } = await createTestUser({ isAdmin: true });
      const adminToken = getAdminToken(user.id, user.email);

      const res = await request(app)
        .post('/api/v1/audit/cleanup')
        .set('Authorization', `Bearer ${adminToken}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.message).toBe('Audit log cleanup completed');
    });

    it('should reject non-admin from triggering cleanup (403)', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .post('/api/v1/audit/cleanup')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(403);
    });
  });
});
