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
    initializeRateLimiter: jest.fn().mockResolvedValue(undefined),
    shutdownRateLimiter: jest.fn().mockResolvedValue(undefined),
  };
});

describe('Warranty Purchases API - /api/v1/warranty-purchases', () => {
  let app: ReturnType<typeof getTestApp>;

  beforeEach(async () => {
    app = getTestApp();
    await cleanDatabase();
  });

  // ──────────────────────────────── List (empty) ────────────────────────────────

  describe('GET /api/v1/warranty-purchases', () => {
    it('should return an empty list for a new user', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .get('/api/v1/warranty-purchases')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(Array.isArray(res.body.data)).toBe(true);
      expect(res.body.data.length).toBe(0);
      expect(res.body.pagination).toBeDefined();
      expect(res.body.pagination.total).toBe(0);
    });

    it('should list purchases after creation', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id, { name: 'Dishwasher' });

      await request(app)
        .post('/api/v1/warranty-purchases')
        .set('Authorization', `Bearer ${token}`)
        .send({
          item_id: item.id,
          provider: 'HavenShield',
          plan_name: '2 Year Protection',
          duration_months: 24,
          starts_at: '2025-01-01',
          price: 79.99,
        });

      const res = await request(app)
        .get('/api/v1/warranty-purchases')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.data.length).toBe(1);
      expect(res.body.pagination.total).toBe(1);
    });

    it('should filter purchases by status', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id, { name: 'Dryer' });

      // Create one purchase then cancel it
      const createRes = await request(app)
        .post('/api/v1/warranty-purchases')
        .set('Authorization', `Bearer ${token}`)
        .send({
          item_id: item.id,
          provider: 'ProtectAll',
          plan_name: '1 Year Plan',
          duration_months: 12,
          starts_at: '2025-01-01',
          price: 49.99,
        });

      const purchaseId = createRes.body.data.id;

      await request(app)
        .post(`/api/v1/warranty-purchases/${purchaseId}/cancel`)
        .set('Authorization', `Bearer ${token}`)
        .send({ reason: 'No longer needed' });

      // Filter for active — should return empty
      const activeRes = await request(app)
        .get('/api/v1/warranty-purchases?status=active')
        .set('Authorization', `Bearer ${token}`);

      expect(activeRes.status).toBe(200);
      expect(activeRes.body.data.length).toBe(0);

      // Filter for cancelled — should return 1
      const cancelledRes = await request(app)
        .get('/api/v1/warranty-purchases?status=cancelled')
        .set('Authorization', `Bearer ${token}`);

      expect(cancelledRes.status).toBe(200);
      expect(cancelledRes.body.data.length).toBe(1);
    });
  });

  // ──────────────────────────────── Create ────────────────────────────────

  describe('POST /api/v1/warranty-purchases', () => {
    it('should create a purchase successfully (201)', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id, { name: 'Oven' });

      const res = await request(app)
        .post('/api/v1/warranty-purchases')
        .set('Authorization', `Bearer ${token}`)
        .send({
          item_id: item.id,
          provider: 'HavenShield Plus',
          plan_name: '3 Year Protection',
          duration_months: 36,
          starts_at: '2025-06-01',
          price: 120.00,
        });

      expect(res.status).toBe(201);
      expect(res.body.success).toBe(true);
      expect(res.body.data.item_id).toBe(item.id);
      expect(res.body.data.provider).toBe('HavenShield Plus');
      expect(res.body.data.plan_name).toBe('3 Year Protection');
      expect(res.body.data.duration_months).toBe(36);
      expect(res.body.data.id).toBeDefined();
      expect(res.body.message).toBe('Warranty purchase created successfully');
    });

    it('should reject create without authentication (401)', async () => {
      const res = await request(app)
        .post('/api/v1/warranty-purchases')
        .send({
          item_id: '00000000-0000-0000-0000-000000000000',
          provider: 'Test',
          plan_name: 'Plan',
          duration_months: 12,
          starts_at: '2025-01-01',
          price: 50,
        });

      expect(res.status).toBe(401);
    });

    it('should reject create with missing required fields (400)', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .post('/api/v1/warranty-purchases')
        .set('Authorization', `Bearer ${token}`)
        .send({
          item_id: '00000000-0000-0000-0000-000000000000',
          // missing provider, plan_name, duration_months, starts_at, price
        });

      expect(res.status).toBe(400);
    });
  });

  // ──────────────────────────────── Active Coverage ────────────────────────────────

  describe('GET /api/v1/warranty-purchases/active', () => {
    it('should get active coverage', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id, { name: 'Microwave' });

      await request(app)
        .post('/api/v1/warranty-purchases')
        .set('Authorization', `Bearer ${token}`)
        .send({
          item_id: item.id,
          provider: 'SafeGuard',
          plan_name: '2 Year Plan',
          duration_months: 24,
          starts_at: '2025-01-01',
          price: 60.00,
        });

      const res = await request(app)
        .get('/api/v1/warranty-purchases/active')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(Array.isArray(res.body.data)).toBe(true);
    });
  });

  // ──────────────────────────────── Expiring ────────────────────────────────

  describe('GET /api/v1/warranty-purchases/expiring', () => {
    it('should return expiring warranties', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .get('/api/v1/warranty-purchases/expiring?days=30')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(Array.isArray(res.body.data)).toBe(true);
    });
  });

  // ──────────────────────────────── Quotes ────────────────────────────────

  describe('GET /api/v1/warranty-purchases/quotes', () => {
    it('should return quotes for a valid item', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id, { name: 'TV', price: 800 });

      const res = await request(app)
        .get(`/api/v1/warranty-purchases/quotes?item_id=${item.id}`)
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.quotes).toBeDefined();
      expect(Array.isArray(res.body.data.quotes)).toBe(true);
      expect(res.body.data.quotes.length).toBeGreaterThan(0);
      expect(res.body.data.item).toBeDefined();
      expect(res.body.data.item.id).toBe(item.id);
    });

    it('should reject quotes without item_id (400)', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .get('/api/v1/warranty-purchases/quotes')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(400);
    });

    it('should reject quotes for a non-existent item (404)', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .get('/api/v1/warranty-purchases/quotes?item_id=00000000-0000-0000-0000-000000000000')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(404);
    });
  });

  // ──────────────────────────────── Get by ID ────────────────────────────────

  describe('GET /api/v1/warranty-purchases/:id', () => {
    it('should get a single purchase by ID', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id, { name: 'Washer' });

      const createRes = await request(app)
        .post('/api/v1/warranty-purchases')
        .set('Authorization', `Bearer ${token}`)
        .send({
          item_id: item.id,
          provider: 'CoverAll',
          plan_name: '1 Year Basic',
          duration_months: 12,
          starts_at: '2025-03-01',
          price: 39.99,
        });

      const purchaseId = createRes.body.data.id;

      const res = await request(app)
        .get(`/api/v1/warranty-purchases/${purchaseId}`)
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.id).toBe(purchaseId);
      expect(res.body.data.provider).toBe('CoverAll');
    });

    it('should reject access to another user\'s purchase (404)', async () => {
      const userA = await createTestUser({ email: 'purchaseusera@test.com' });
      const userB = await createTestUser({ email: 'purchaseuserb@test.com' });
      const homeB = await createTestHome(userB.user.id);
      const itemB = await createTestItem(userB.user.id, homeB.id);

      const createRes = await request(app)
        .post('/api/v1/warranty-purchases')
        .set('Authorization', `Bearer ${userB.token}`)
        .send({
          item_id: itemB.id,
          provider: 'Private Plan',
          plan_name: 'Premium',
          duration_months: 24,
          starts_at: '2025-01-01',
          price: 100,
        });

      const purchaseId = createRes.body.data.id;

      // User A tries to access User B's purchase
      const res = await request(app)
        .get(`/api/v1/warranty-purchases/${purchaseId}`)
        .set('Authorization', `Bearer ${userA.token}`);

      expect(res.status).toBe(404);
    });
  });

  // ──────────────────────────────── Cancel ────────────────────────────────

  describe('POST /api/v1/warranty-purchases/:id/cancel', () => {
    it('should cancel a purchase', async () => {
      const { user, token } = await createTestUser();
      const home = await createTestHome(user.id);
      const item = await createTestItem(user.id, home.id, { name: 'Furnace' });

      const createRes = await request(app)
        .post('/api/v1/warranty-purchases')
        .set('Authorization', `Bearer ${token}`)
        .send({
          item_id: item.id,
          provider: 'ShieldMax',
          plan_name: '2 Year Standard',
          duration_months: 24,
          starts_at: '2025-01-01',
          price: 89.99,
        });

      const purchaseId = createRes.body.data.id;

      const res = await request(app)
        .post(`/api/v1/warranty-purchases/${purchaseId}/cancel`)
        .set('Authorization', `Bearer ${token}`)
        .send({ reason: 'Sold the appliance' });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.status).toBe('cancelled');
      expect(res.body.message).toBe('Warranty purchase cancelled successfully');
    });
  });
});
