import request from 'supertest';
import { cleanDatabase } from './setup';
import { getTestApp, createTestUser } from './helpers';

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
});
