import request from 'supertest';
import { cleanDatabase } from './setup';
import { getTestApp, createTestUser, createTestHome, createTestItem } from './helpers';

const app = getTestApp();

describe('Homes API', () => {
  beforeEach(async () => {
    await cleanDatabase();
  });

  // ──────────────────────────────── Create ────────────────────────────────

  describe('POST /api/v1/homes', () => {
    it('should create a new home', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .post('/api/v1/homes')
        .set('Authorization', `Bearer ${token}`)
        .send({
          name: 'Beach House',
          address: '456 Ocean Ave',
          city: 'Malibu',
          state: 'CA',
          zip: '90265',
        });

      expect(res.status).toBe(201);
      expect(res.body.success).toBe(true);
      expect(res.body.data.name).toBe('Beach House');
      expect(res.body.data.address).toBe('456 Ocean Ave');
      expect(res.body.data.city).toBe('Malibu');
      expect(res.body.data.state).toBe('CA');
      expect(res.body.data.zip).toBe('90265');
      expect(res.body.data.id).toBeDefined();
    });

    it('should reject creating a home without a name', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .post('/api/v1/homes')
        .set('Authorization', `Bearer ${token}`)
        .send({ address: '123 No Name St' });

      expect(res.status).toBe(400);
      expect(res.body.error).toBeDefined();
    });

    it('should reject unauthenticated requests', async () => {
      const res = await request(app)
        .post('/api/v1/homes')
        .send({ name: 'No Auth Home' });

      expect(res.status).toBe(401);
    });
  });

  // ──────────────────────────────── List ────────────────────────────────

  describe('GET /api/v1/homes', () => {
    it('should list all homes for the authenticated user', async () => {
      const { user, token } = await createTestUser();
      await createTestHome(user.id, { name: 'Home One' });
      await createTestHome(user.id, { name: 'Home Two' });

      const res = await request(app)
        .get('/api/v1/homes')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(Array.isArray(res.body.data)).toBe(true);
      expect(res.body.data.length).toBe(2);
    });

    it('should return an empty array when user has no homes', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .get('/api/v1/homes')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toEqual([]);
    });
  });

  // ──────────────────────────────── Get by ID ────────────────────────────────

  describe('GET /api/v1/homes/:id', () => {
    it('should return a single home by ID', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id, { name: 'My Cottage' });

      const res = await request(app)
        .get(`/api/v1/homes/${home.id}`)
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.id).toBe(home.id);
      expect(res.body.data.name).toBe('My Cottage');
    });

    it('should return 404 for a nonexistent home', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .get('/api/v1/homes/00000000-0000-0000-0000-000000000000')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(404);
      expect(res.body.error).toBe('Home not found');
    });
  });

  // ──────────────────────────────── Update ────────────────────────────────

  describe('PUT /api/v1/homes/:id', () => {
    it('should update an existing home', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id, { name: 'Old Name' });

      const res = await request(app)
        .put(`/api/v1/homes/${home.id}`)
        .set('Authorization', `Bearer ${token}`)
        .send({ name: 'New Name', city: 'New City' });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.name).toBe('New Name');
      expect(res.body.data.city).toBe('New City');
    });

    it('should return 404 when updating a nonexistent home', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .put('/api/v1/homes/00000000-0000-0000-0000-000000000000')
        .set('Authorization', `Bearer ${token}`)
        .send({ name: 'Ghost Home' });

      expect(res.status).toBe(404);
    });

    it('should reject an update with no fields', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);

      const res = await request(app)
        .put(`/api/v1/homes/${home.id}`)
        .set('Authorization', `Bearer ${token}`)
        .send({});

      expect(res.status).toBe(400);
    });
  });

  // ──────────────────────────────── Delete ────────────────────────────────

  describe('DELETE /api/v1/homes/:id', () => {
    it('should delete a home when user has more than one', async () => {
      const { user, token } = await createTestUser();
      const homeA = await createTestHome(user.id, { name: 'Home A' });
      await createTestHome(user.id, { name: 'Home B' });

      const res = await request(app)
        .delete(`/api/v1/homes/${homeA.id}`)
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.message).toBe('Home deleted successfully');

      // Verify it is gone
      const getRes = await request(app)
        .get(`/api/v1/homes/${homeA.id}`)
        .set('Authorization', `Bearer ${token}`);

      expect(getRes.status).toBe(404);
    });

    it('should prevent deleting the last home with a generic message', async () => {
      // Audit Ch02-F016: refused last-home delete returns 409 with a
      // message that doesn't leak the precise home count.
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id, { name: 'Only Home' });

      const res = await request(app)
        .delete(`/api/v1/homes/${home.id}`)
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(409);
      expect(res.body.error).toContain('create another home first');
      // Must not leak the count.
      expect(res.body.error).not.toMatch(/only|last|1\b/i);
    });

    it('should reassign items to another home on delete', async () => {
      const { user, token } = await createTestUser();
      const homeA = await createTestHome(user.id, { name: 'Home A' });
      const homeB = await createTestHome(user.id, { name: 'Home B' });
      const item = await createTestItem(user.id, homeA.id, { name: 'Fridge' });

      // Delete Home A (item should move to Home B)
      await request(app)
        .delete(`/api/v1/homes/${homeA.id}`)
        .set('Authorization', `Bearer ${token}`);

      // Verify item is now in Home B
      const itemRes = await request(app)
        .get(`/api/v1/items/${item.id}`)
        .set('Authorization', `Bearer ${token}`);

      expect(itemRes.status).toBe(200);
      expect(itemRes.body.data.home_id).toBe(homeB.id);
    });
  });

  // ──────────────────────────────── Authorization ────────────────────────────────

  describe('Cross-user isolation', () => {
    it('should not allow user A to access user B homes', async () => {
      const userA = await createTestUser({ email: 'usera@test.com' });
      const userB = await createTestUser({ email: 'userb@test.com' });

      const homeB = await createTestHome(userB.user.id, { name: 'Private Home' });

      // User A tries to read User B's home
      const res = await request(app)
        .get(`/api/v1/homes/${homeB.id}`)
        .set('Authorization', `Bearer ${userA.token}`);

      expect(res.status).toBe(404);
    });

    it('should not allow user A to update user B homes', async () => {
      const userA = await createTestUser({ email: 'usera2@test.com' });
      const userB = await createTestUser({ email: 'userb2@test.com' });

      const homeB = await createTestHome(userB.user.id, { name: 'Private Home' });

      const res = await request(app)
        .put(`/api/v1/homes/${homeB.id}`)
        .set('Authorization', `Bearer ${userA.token}`)
        .send({ name: 'Hacked' });

      expect(res.status).toBe(404);
    });

    it('should not allow user A to delete user B homes', async () => {
      const userA = await createTestUser({ email: 'usera3@test.com' });
      const userB = await createTestUser({ email: 'userb3@test.com' });

      const homeB1 = await createTestHome(userB.user.id, { name: 'Home B1' });
      await createTestHome(userB.user.id, { name: 'Home B2' });

      const res = await request(app)
        .delete(`/api/v1/homes/${homeB1.id}`)
        .set('Authorization', `Bearer ${userA.token}`);

      // User A doesn't own this home so they should get a 404. They never
      // see B's home count, so the 409 last-home path can't trigger here.
      expect([404, 409]).toContain(res.status);
    });
  });
});
