import request from 'supertest';
import jwt from 'jsonwebtoken';
import { cleanDatabase } from './setup';
import { getTestApp, createTestUser, getAuthToken } from './helpers';
import { config } from '../config';

const app = getTestApp();

describe('Middleware', () => {
  beforeEach(async () => {
    await cleanDatabase();
  });

  describe('Auth middleware', () => {
    it('should return 401 when no token is provided', async () => {
      const res = await request(app).get('/api/v1/notifications');

      expect(res.status).toBe(401);
      expect(res.body.error).toBe('No token provided');
    });

    it('should return 401 when an invalid token is provided', async () => {
      const res = await request(app)
        .get('/api/v1/notifications')
        .set('Authorization', 'Bearer invalid-token-here');

      expect(res.status).toBe(401);
      expect(res.body.error).toBe('Invalid token');
    });

    it('should return 401 when an expired token is provided', async () => {
      const expiredToken = jwt.sign(
        { userId: '00000000-0000-0000-0000-000000000000', email: 'expired@test.com', isAdmin: false, isPartner: false },
        config.jwt.secret,
        { expiresIn: '-1s' }
      );

      const res = await request(app)
        .get('/api/v1/notifications')
        .set('Authorization', `Bearer ${expiredToken}`);

      expect(res.status).toBe(401);
      expect(res.body.error).toBe('Invalid token');
    });

    it('should pass through with a valid token', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .get('/api/v1/notifications')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
    });
  });

  describe('404 handler', () => {
    it('should return 404 for an unknown endpoint', async () => {
      const res = await request(app).get('/api/v1/nonexistent-endpoint');

      expect(res.status).toBe(404);
      expect(res.body.error).toBe('Not found');
      expect(res.body.suggestion).toBe('Check API documentation for available endpoints');
    });
  });

  describe('Error handler', () => {
    it('should return the correct status code and message for an AppError', async () => {
      // Trigger a known AppError: admin route accessed by non-admin user returns 403
      const { token } = await createTestUser();

      const res = await request(app)
        .get('/api/v1/admin/stats')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(403);
      expect(res.body.error).toBe('Admin access required');
      expect(res.body.statusCode).toBe(403);
    });
  });
});
