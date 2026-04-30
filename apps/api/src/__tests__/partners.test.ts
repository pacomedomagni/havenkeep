import request from 'supertest';
import { cleanDatabase } from './setup';
import { getTestApp, createTestUser } from './helpers';

jest.mock('../middleware/rateLimiter', () => require('./test-rate-limiter-mock'));

// Mock EmailService so partner welcome emails do not hit SendGrid
jest.mock('../services/email.service', () => ({
  EmailService: {
    sendContactNotificationEmail: jest.fn().mockResolvedValue(undefined),
    sendPartnerWelcomeEmail: jest.fn().mockResolvedValue(undefined),
    sendGiftEmail: jest.fn().mockResolvedValue(undefined),
    sendPasswordResetEmail: jest.fn().mockResolvedValue(undefined),
    sendEmailVerificationEmail: jest.fn().mockResolvedValue(undefined),
  },
}));

const REGISTER_PAYLOAD = {
  partner_type: 'realtor',
  company_name: 'Acme Realty',
  phone: '555-0100',
};

describe('Partners Routes', () => {
  let app: ReturnType<typeof getTestApp>;
  let token: string;

  beforeAll(() => {
    app = getTestApp();
  });

  beforeEach(async () => {
    await cleanDatabase();
    const { token: t } = await createTestUser();
    token = t;
  });

  // ----------------------------------------------------------------
  // Public endpoints
  // ----------------------------------------------------------------

  describe('GET /api/v1/partners/tiers', () => {
    it('should return partner tiers for authenticated user', async () => {
      const res = await request(app)
        .get('/api/v1/partners/tiers')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(Array.isArray(res.body.data)).toBe(true);
      expect(res.body.data.length).toBeGreaterThan(0);

      // Each tier should have the expected shape
      const tier = res.body.data[0];
      expect(tier).toHaveProperty('id');
      expect(tier).toHaveProperty('name');
      expect(tier).toHaveProperty('commission_rate');
    });
  });

  // ----------------------------------------------------------------
  // Registration
  // ----------------------------------------------------------------

  describe('POST /api/v1/partners/register', () => {
    it('should return 401 when no auth token is provided', async () => {
      const res = await request(app)
        .post('/api/v1/partners/register')
        .send(REGISTER_PAYLOAD);

      expect(res.status).toBe(401);
    });

    it('should return 400 when partner_type is missing', async () => {
      const res = await request(app)
        .post('/api/v1/partners/register')
        .set('Authorization', `Bearer ${token}`)
        .send({ company_name: 'Acme Realty' }); // no partner_type

      expect(res.status).toBe(400);
    });

    it('should register as a partner successfully', async () => {
      const res = await request(app)
        .post('/api/v1/partners/register')
        .set('Authorization', `Bearer ${token}`)
        .send(REGISTER_PAYLOAD);

      expect(res.status).toBe(201);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toMatchObject({
        partner_type: 'realtor',
        company_name: 'Acme Realty',
      });
    });

    it('should return 400 when the user tries to register as a partner a second time', async () => {
      // First registration
      await request(app)
        .post('/api/v1/partners/register')
        .set('Authorization', `Bearer ${token}`)
        .send(REGISTER_PAYLOAD);

      // Duplicate registration
      const res = await request(app)
        .post('/api/v1/partners/register')
        .set('Authorization', `Bearer ${token}`)
        .send(REGISTER_PAYLOAD);

      expect(res.status).toBe(400);
    });
  });

  // ----------------------------------------------------------------
  // GET /me
  // ----------------------------------------------------------------

  describe('GET /api/v1/partners/me', () => {
    it('should return 404 when the user is not a partner', async () => {
      const res = await request(app)
        .get('/api/v1/partners/me')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(404);
    });

    it('should return the partner profile after registration', async () => {
      // Register first
      await request(app)
        .post('/api/v1/partners/register')
        .set('Authorization', `Bearer ${token}`)
        .send(REGISTER_PAYLOAD);

      const res = await request(app)
        .get('/api/v1/partners/me')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toMatchObject({
        partner_type: 'realtor',
        company_name: 'Acme Realty',
      });
    });
  });

  // ----------------------------------------------------------------
  // PUT /me
  // ----------------------------------------------------------------

  describe('PUT /api/v1/partners/me', () => {
    it('should update the partner profile', async () => {
      // Register first
      await request(app)
        .post('/api/v1/partners/register')
        .set('Authorization', `Bearer ${token}`)
        .send(REGISTER_PAYLOAD);

      const res = await request(app)
        .put('/api/v1/partners/me')
        .set('Authorization', `Bearer ${token}`)
        .send({ company_name: 'Updated Realty LLC' });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.company_name).toBe('Updated Realty LLC');
    });
  });

  // ----------------------------------------------------------------
  // Activation code verify (audit Ch09-FlowC-T-C2/C3/C16)
  // ----------------------------------------------------------------

  describe('POST /api/v1/partners/gifts/verify-code', () => {
    // C3: verify-code requires email as a 2nd factor — without it the route
    // is an enumeration oracle.
    it('rejects requests without homebuyer_email', async () => {
      const res = await request(app)
        .post('/api/v1/partners/gifts/verify-code')
        .send({ activation_code: 'AAAA-BBBB-CCCC-DDDD' });

      expect(res.status).toBe(400);
    });

    // C2/C16: even with a valid code shape, an unknown code returns the
    // same opaque 404 as a known code with the wrong email.
    it('returns 404 for an unknown code', async () => {
      const res = await request(app)
        .post('/api/v1/partners/gifts/verify-code')
        .send({
          activation_code: 'AAAA-BBBB-CCCC-DDDD',
          homebuyer_email: 'nope@test.com',
        });

      expect(res.status).toBe(404);
    });
  });

  // ----------------------------------------------------------------
  // Tier rates locked (Ch12-T037)
  // ----------------------------------------------------------------

  describe('GET /api/v1/partners/tiers — rate values locked', () => {
    it('locks commission_rate to 0.10/0.15/0.20 across basic/premium/platinum', async () => {
      const res = await request(app)
        .get('/api/v1/partners/tiers')
        .set('Authorization', `Bearer ${token}`);
      expect(res.status).toBe(200);
      const byId = Object.fromEntries(
        (res.body.data as Array<{ id: string; commission_rate: number }>).map((t) => [
          t.id,
          t.commission_rate,
        ]),
      );
      expect(byId.basic).toBe(0.1);
      expect(byId.premium).toBe(0.15);
      expect(byId.platinum).toBe(0.2);
    });

    it('matches the service-side TIER_COMMISSION_RATES constant', () => {
      // Import lazily so the mock for rateLimiter resolves first.
      const { TIER_COMMISSION_RATES } = require('../services/partners.service');
      expect(TIER_COMMISSION_RATES.basic).toBe(0.1);
      expect(TIER_COMMISSION_RATES.premium).toBe(0.15);
      expect(TIER_COMMISSION_RATES.platinum).toBe(0.2);
    });
  });

  // ----------------------------------------------------------------
  // Partner type lock (Ch03-F015)
  // ----------------------------------------------------------------

  describe('PUT /api/v1/partners/me — partner_type lock', () => {
    it('rejects updates that try to change partner_type', async () => {
      await request(app)
        .post('/api/v1/partners/register')
        .set('Authorization', `Bearer ${token}`)
        .send(REGISTER_PAYLOAD);

      const res = await request(app)
        .put('/api/v1/partners/me')
        .set('Authorization', `Bearer ${token}`)
        .send({ partner_type: 'builder', company_name: 'Sneaky Builder LLC' });

      // Validator rejects the unknown field — it isn't in updatePartnerSchema.
      expect(res.status).toBe(400);
    });
  });
});
