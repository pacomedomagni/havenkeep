import request from 'supertest';
import { cleanDatabase } from './setup';
import { getTestApp, createTestUser } from './helpers';

const app = getTestApp();

describe('Users API', () => {
  beforeEach(async () => {
    await cleanDatabase();
  });

  // ──────────────────────────────── Get Profile ────────────────────────────────

  describe('GET /api/v1/users/me', () => {
    it('should return the authenticated user profile', async () => {
      const { user, token } = await createTestUser({
        email: 'profile@test.com',
        fullName: 'Profile User',
      });

      const res = await request(app)
        .get('/api/v1/users/me')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.id).toBe(user.id);
      expect(res.body.data.email).toBe('profile@test.com');
      expect(res.body.data.full_name).toBe('Profile User');
      expect(res.body.data.plan).toBe('free');
      expect(res.body.data).toHaveProperty('referral_code');
      expect(res.body.data).toHaveProperty('created_at');
      expect(res.body.data).toHaveProperty('updated_at');
    });

    it('should reject unauthenticated requests', async () => {
      const res = await request(app)
        .get('/api/v1/users/me');

      expect(res.status).toBe(401);
    });

    it('should return is_partner field', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .get('/api/v1/users/me')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.data).toHaveProperty('is_partner');
      // Regular user is not a partner
      expect(res.body.data.is_partner).toBe(false);
    });
  });

  // ──────────────────────────────── Update Profile ────────────────────────────────

  describe('PUT /api/v1/users/me', () => {
    it('should update the user full name', async () => {
      const { token } = await createTestUser({ fullName: 'Old Name' });

      const res = await request(app)
        .put('/api/v1/users/me')
        .set('Authorization', `Bearer ${token}`)
        .send({ fullName: 'New Name' });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.full_name).toBe('New Name');
    });

    it('should accept snake_case field names from mobile clients', async () => {
      const { token } = await createTestUser({ fullName: 'Snake Case' });

      const res = await request(app)
        .put('/api/v1/users/me')
        .set('Authorization', `Bearer ${token}`)
        .send({ full_name: 'Updated via Snake' });

      expect(res.status).toBe(200);
      expect(res.body.data.full_name).toBe('Updated via Snake');
    });

    it('should reject an update with no fields', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .put('/api/v1/users/me')
        .set('Authorization', `Bearer ${token}`)
        .send({});

      expect(res.status).toBe(400);
    });

    it('should reject unauthenticated requests', async () => {
      const res = await request(app)
        .put('/api/v1/users/me')
        .send({ fullName: 'Hacker' });

      expect(res.status).toBe(401);
    });

    it('should persist updates across requests', async () => {
      const { token } = await createTestUser({ fullName: 'Before' });

      await request(app)
        .put('/api/v1/users/me')
        .set('Authorization', `Bearer ${token}`)
        .send({ fullName: 'After' });

      // Fetch profile again
      const res = await request(app)
        .get('/api/v1/users/me')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.data.full_name).toBe('After');
    });

    it('should update only the provided fields, leaving others untouched', async () => {
      const { user, token } = await createTestUser({
        email: 'partial@test.com',
        fullName: 'Original Name',
      });

      const res = await request(app)
        .put('/api/v1/users/me')
        .set('Authorization', `Bearer ${token}`)
        .send({ fullName: 'Changed Name' });

      expect(res.status).toBe(200);
      expect(res.body.data.full_name).toBe('Changed Name');
      expect(res.body.data.email).toBe('partial@test.com');
    });
  });
});
