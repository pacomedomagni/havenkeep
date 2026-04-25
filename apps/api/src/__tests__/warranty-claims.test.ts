import request from 'supertest';
import { cleanDatabase } from './setup';
import { getTestApp, createTestUser, createTestHome, createTestItem } from './helpers';

// Rate limiters are module-level singletons (in-memory stores) that persist
// across app instances. Mock them all as pass-through in tests.
jest.mock('../middleware/rateLimiter', () => {
  const pass = (_req: any, _res: any, next: any) => next();
  return {
    __esModule: true,
    authRateLimiter: pass,
    refreshRateLimiter: pass,
    passwordResetRateLimiter: pass,
    uploadRateLimiter: pass,
    activationCodeRateLimiter: pass,
    verifyPremiumRateLimiter: pass,
    passwordChangeRateLimiter: pass,
    writeRateLimiter: pass,
    giftResendRateLimiter: pass,
    receiptScanRateLimiter: pass,
    newsletterRateLimiter: pass,
    contactRateLimiter: pass,
    itemsListRateLimiter: pass,
    csvExportRateLimiter: pass,
    readRateLimiter: pass,
    initializeRateLimiter: jest.fn().mockResolvedValue(undefined),
    shutdownRateLimiter: jest.fn().mockResolvedValue(undefined),
  };
});

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
          repair_cost: 150.00,
          amount_saved: 300.00,
          issue_description: 'Motor failed after 2 years',
        });

      expect(res.status).toBe(201);
      expect(res.body.success).toBe(true);
      expect(res.body.data.item_id).toBe(item.id);
      expect(res.body.data.repair_cost).toBe('150.00');
      expect(res.body.data.amount_saved).toBe('300.00');
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
          repair_cost: 250.00,
          amount_saved: 500.00,
          issue_description: 'Compressor stopped working',
          status: 'pending',
          claim_date: '2025-01-15',
          filed_with: 'Samsung Warranty',
          notes: 'Contacted support on Jan 10th',
        });

      expect(res.status).toBe(201);
      expect(res.body.success).toBe(true);
      expect(res.body.data.status).toBe('pending');
      expect(res.body.data.filed_with).toBe('Samsung Warranty');
      expect(res.body.data.notes).toBe('Contacted support on Jan 10th');
    });

    it('should reject create without authentication (401)', async () => {
      const res = await request(app)
        .post('/api/v1/warranty-claims')
        .send({
          item_id: '00000000-0000-0000-0000-000000000000',
          repair_cost: 100,
          amount_saved: 200,
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
          repair_cost: 100,
          amount_saved: 200,
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
          .send({ item_id: item.id, repair_cost: i * 100, amount_saved: i * 200 });
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
        .send({ item_id: itemA.id, repair_cost: 100, amount_saved: 200 });

      await request(app)
        .post('/api/v1/warranty-claims')
        .set('Authorization', `Bearer ${token}`)
        .send({ item_id: itemB.id, repair_cost: 50, amount_saved: 100 });

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
        .send({ item_id: item.id, repair_cost: 100, amount_saved: 500 });

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
        .send({ item_id: itemB.id, repair_cost: 100, amount_saved: 200 });

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
        .send({ item_id: item.id, repair_cost: 100, amount_saved: 200, status: 'pending' });

      const claimId = createRes.body.data.id;

      const res = await request(app)
        .put(`/api/v1/warranty-claims/${claimId}`)
        .set('Authorization', `Bearer ${token}`)
        .send({ status: 'completed', repair_cost: 125.00 });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.status).toBe('completed');
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
        .send({ item_id: itemB.id, repair_cost: 100, amount_saved: 200 });

      const claimId = createRes.body.data.id;

      // User A tries to delete User B's claim
      const res = await request(app)
        .delete(`/api/v1/warranty-claims/${claimId}`)
        .set('Authorization', `Bearer ${userA.token}`);

      expect(res.status).toBe(404);
    });
  });
});
