import request from 'supertest';
import { cleanDatabase } from './setup';
import { getTestApp, createTestUser, createTestHome, createTestItem } from './helpers';

// Rate limiters are module-level singletons (in-memory stores) that persist
// across app instances. Mock them all as pass-through in tests.
jest.mock('../middleware/rateLimiter', () => require('./test-rate-limiter-mock'));

describe('Warranty Claims API - /api/v1/warranty-claims', () => {
  let app: ReturnType<typeof getTestApp>;

  beforeEach(async () => {
    app = getTestApp();
    await cleanDatabase();
  });

  // ──────────────────────────────── Create ────────────────────────────────

  describe('POST /api/v1/warranty-claims', () => {
    it('should create a warranty claim successfully (201)', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id, { name: 'Washing Machine' });

      const res = await request(app)
        .post('/api/v1/warranty-claims')
        .set('Authorization', `Bearer ${token}`)
        .send({
          item_id: item.id,
          repair_cost: 300.00,
          amount_saved: 150.00,
          issue_description: 'Motor failed after 2 years',
        });

      expect(res.status).toBe(201);
      expect(res.body.success).toBe(true);
      expect(res.body.data.item_id).toBe(item.id);
      expect(res.body.data.repair_cost).toBe('300.00');
      expect(res.body.data.amount_saved).toBe('150.00');
      expect(res.body.data.id).toBeDefined();
      expect(res.body.message).toBe('Warranty claim created successfully');
    });

    it('should create a warranty claim with all optional fields', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id, { name: 'Refrigerator' });

      const res = await request(app)
        .post('/api/v1/warranty-claims')
        .set('Authorization', `Bearer ${token}`)
        .send({
          item_id: item.id,
          repair_cost: 500.00,
          amount_saved: 250.00,
          issue_description: 'Compressor stopped working',
          status: 'filed',
          claim_date: '2025-01-15',
          filed_with: 'Samsung Warranty',
          notes: 'Contacted support on Jan 10th',
        });

      expect(res.status).toBe(201);
      expect(res.body.success).toBe(true);
      expect(res.body.data.status).toBe('filed');
      expect(res.body.data.filed_with).toBe('Samsung Warranty');
      expect(res.body.data.notes).toBe('Contacted support on Jan 10th');
    });

    it('should reject create without authentication (401)', async () => {
      const res = await request(app)
        .post('/api/v1/warranty-claims')
        .send({
          item_id: '00000000-0000-0000-0000-000000000000',
          repair_cost: 200,
          amount_saved: 100,
        });

      expect(res.status).toBe(401);
    });

    it('should reject create with missing required fields (400)', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .post('/api/v1/warranty-claims')
        .set('Authorization', `Bearer ${token}`)
        .send({
          item_id: '00000000-0000-0000-0000-000000000000',
          // missing repair_cost and amount_saved
        });

      expect(res.status).toBe(400);
    });

    it('should reject create with an invalid item_id', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);

      // Create claim for a non-existent item UUID
      const res = await request(app)
        .post('/api/v1/warranty-claims')
        .set('Authorization', `Bearer ${token}`)
        .send({
          item_id: '00000000-0000-0000-0000-000000000000',
          repair_cost: 200,
          amount_saved: 100,
        });

      expect([400, 404]).toContain(res.status);
    });
  });

  // ──────────────────────────────── List ────────────────────────────────

  describe('GET /api/v1/warranty-claims', () => {
    it('should list claims with pagination', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id);

      // Create 3 claims
      for (let i = 1; i <= 3; i++) {
        await request(app)
          .post('/api/v1/warranty-claims')
          .set('Authorization', `Bearer ${token}`)
          .send({ item_id: item.id, repair_cost: i * 200, amount_saved: i * 100 });
      }

      const res = await request(app)
        .get('/api/v1/warranty-claims?page=1&limit=2')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(Array.isArray(res.body.data)).toBe(true);
      expect(res.body.data.length).toBe(2);
      expect(res.body.pagination).toBeDefined();
      expect(res.body.pagination.total).toBe(3);
      expect(res.body.pagination.total_pages).toBe(2);
    });

    it('should filter claims by item_id', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const itemA = await createTestItem(user.id, home.id, { name: 'Item A' });
      const itemB = await createTestItem(user.id, home.id, { name: 'Item B' });

      // Create one claim for each item
      await request(app)
        .post('/api/v1/warranty-claims')
        .set('Authorization', `Bearer ${token}`)
        .send({ item_id: itemA.id, repair_cost: 200, amount_saved: 100 });

      await request(app)
        .post('/api/v1/warranty-claims')
        .set('Authorization', `Bearer ${token}`)
        .send({ item_id: itemB.id, repair_cost: 100, amount_saved: 50 });

      const res = await request(app)
        .get(`/api/v1/warranty-claims?item_id=${itemA.id}`)
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.data.length).toBe(1);
      expect(res.body.data[0].item_id).toBe(itemA.id);
    });
  });

  // ──────────────────────────────── Savings ────────────────────────────────

  describe('GET /api/v1/warranty-claims/savings', () => {
    it('should return total savings for user', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id);

      await request(app)
        .post('/api/v1/warranty-claims')
        .set('Authorization', `Bearer ${token}`)
        .send({ item_id: item.id, repair_cost: 500, amount_saved: 100 });

      const res = await request(app)
        .get('/api/v1/warranty-claims/savings')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toBeDefined();
    });
  });

  // ──────────────────────────────── Feed ────────────────────────────────

  describe('GET /api/v1/warranty-claims/feed', () => {
    it('should return savings feed', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .get('/api/v1/warranty-claims/feed')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(Array.isArray(res.body.data)).toBe(true);
    });

    it('should respect the limit query parameter', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .get('/api/v1/warranty-claims/feed?limit=5')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.data.length).toBeLessThanOrEqual(5);
    });
  });

  // ──────────────────────────────── Get by ID ────────────────────────────────

  describe('GET /api/v1/warranty-claims/:id', () => {
    it('should get a single claim by ID', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id);

      const createRes = await request(app)
        .post('/api/v1/warranty-claims')
        .set('Authorization', `Bearer ${token}`)
        .send({ item_id: item.id, repair_cost: 200, amount_saved: 400, issue_description: 'Screen cracked' });

      const claimId = createRes.body.data.id;

      const res = await request(app)
        .get(`/api/v1/warranty-claims/${claimId}`)
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.id).toBe(claimId);
      expect(res.body.data.issue_description).toBe('Screen cracked');
    });

    it('should reject access to another user\'s claim (404)', async () => {
      const userA = await createTestUser({ email: 'claimusera@test.com' });
      const userB = await createTestUser({ email: 'claimuserb@test.com' });
      const homeB = await createTestHome(userB.user.id);
      const itemB = await createTestItem(userB.user.id, homeB.id);

      const createRes = await request(app)
        .post('/api/v1/warranty-claims')
        .set('Authorization', `Bearer ${userB.token}`)
        .send({ item_id: itemB.id, repair_cost: 200, amount_saved: 100 });

      const claimId = createRes.body.data.id;

      // User A tries to access User B's claim
      const res = await request(app)
        .get(`/api/v1/warranty-claims/${claimId}`)
        .set('Authorization', `Bearer ${userA.token}`);

      expect(res.status).toBe(404);
    });
  });

  // ──────────────────────────────── Update ────────────────────────────────

  describe('PUT /api/v1/warranty-claims/:id', () => {
    it('should update a claim', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id);

      const createRes = await request(app)
        .post('/api/v1/warranty-claims')
        .set('Authorization', `Bearer ${token}`)
        .send({ item_id: item.id, repair_cost: 200, amount_saved: 100, status: 'filed' });

      const claimId = createRes.body.data.id;

      const res = await request(app)
        .put(`/api/v1/warranty-claims/${claimId}`)
        .set('Authorization', `Bearer ${token}`)
        .send({ status: 'in_review', repair_cost: 250.00 });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.status).toBe('in_review');
      expect(res.body.message).toBe('Warranty claim updated successfully');
    });
  });

  // ──────────────────────────────── Delete ────────────────────────────────

  describe('DELETE /api/v1/warranty-claims/:id', () => {
    it('should delete a claim', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id);

      const createRes = await request(app)
        .post('/api/v1/warranty-claims')
        .set('Authorization', `Bearer ${token}`)
        .send({ item_id: item.id, repair_cost: 100, amount_saved: 200 });

      const claimId = createRes.body.data.id;

      const res = await request(app)
        .delete(`/api/v1/warranty-claims/${claimId}`)
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.message).toBe('Warranty claim deleted successfully');

      // Verify it is gone
      const getRes = await request(app)
        .get(`/api/v1/warranty-claims/${claimId}`)
        .set('Authorization', `Bearer ${token}`);

      expect(getRes.status).toBe(404);
    });

    it('should reject delete of another user\'s claim (404)', async () => {
      const userA = await createTestUser({ email: 'delclaimusera@test.com' });
      const userB = await createTestUser({ email: 'delclaimuserb@test.com' });
      const homeB = await createTestHome(userB.user.id);
      const itemB = await createTestItem(userB.user.id, homeB.id);

      const createRes = await request(app)
        .post('/api/v1/warranty-claims')
        .set('Authorization', `Bearer ${userB.token}`)
        .send({ item_id: itemB.id, repair_cost: 200, amount_saved: 100 });

      const claimId = createRes.body.data.id;

      // User A tries to delete User B's claim
      const res = await request(app)
        .delete(`/api/v1/warranty-claims/${claimId}`)
        .set('Authorization', `Bearer ${userA.token}`);

      expect(res.status).toBe(404);
    });
  });

  // S3-12.10/11/12 / S1-bundle: Idempotency-Key end-to-end. The mobile
  // offline queue stamps a UUID per entry and re-sends with the same key
  // after a crash; the server's request_idempotency middleware must
  // collapse the second request into the cached response without
  // creating a duplicate row.
  describe('Idempotency-Key end-to-end (S1-J/K/L)', () => {
    it('replays the cached response for a repeated POST with the same key', async () => {
      const { user, token } = await createTestUser({ email: 'idempo@test.com' });
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id);
      const key = `idempo-${require('crypto').randomUUID()}`;
      const body = {
        item_id: item.id,
        repair_cost: 200,
        amount_saved: 100,
        issue_description: 'Compressor noise',
      };

      const first = await request(app)
        .post('/api/v1/warranty-claims')
        .set('Authorization', `Bearer ${token}`)
        .set('Idempotency-Key', key)
        .send(body);
      expect(first.status).toBe(201);
      const firstId = first.body.data?.id ?? first.body.id;
      expect(firstId).toBeDefined();

      const second = await request(app)
        .post('/api/v1/warranty-claims')
        .set('Authorization', `Bearer ${token}`)
        .set('Idempotency-Key', key)
        .send(body);
      // Must replay the same response (status + id), not create a new row.
      expect(second.status).toBe(201);
      const secondId = second.body.data?.id ?? second.body.id;
      expect(secondId).toBe(firstId);

      const { pool } = require('../db');
      const rows = await pool.query(
        `SELECT id FROM warranty_claims WHERE user_id = $1 AND item_id = $2`,
        [user.id, item.id],
      );
      expect(rows.rows.length).toBe(1);
    });

    it('rejects with 409 when the same key is reused for a different body', async () => {
      const { user, token } = await createTestUser({ email: 'idempo-conflict@test.com' });
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id);
      const key = `idempo-${require('crypto').randomUUID()}`;

      const first = await request(app)
        .post('/api/v1/warranty-claims')
        .set('Authorization', `Bearer ${token}`)
        .set('Idempotency-Key', key)
        .send({ item_id: item.id, repair_cost: 200, amount_saved: 100 });
      expect(first.status).toBe(201);

      const second = await request(app)
        .post('/api/v1/warranty-claims')
        .set('Authorization', `Bearer ${token}`)
        .set('Idempotency-Key', key)
        .send({ item_id: item.id, repair_cost: 999, amount_saved: 100 });
      expect(second.status).toBe(409);
    });
  });
});
