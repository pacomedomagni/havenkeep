import crypto from 'crypto';
import request from 'supertest';
import { cleanDatabase } from './setup';
import { getTestApp, createTestUser } from './helpers';
import { pool } from '../db';
import { PartnersService, hashActivationCode } from '../services/partners.service';

jest.mock('../middleware/rateLimiter', () => require('./test-rate-limiter-mock'));

// Mock EmailService so partner welcome / gift emails do not hit SendGrid.
jest.mock('../services/email.service', () => ({
  EmailService: {
    sendContactNotificationEmail: jest.fn().mockResolvedValue(undefined),
    sendPartnerWelcomeEmail: jest.fn().mockResolvedValue(undefined),
    sendGiftActivationEmail: jest.fn().mockResolvedValue(undefined),
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
  let userId: string;

  beforeAll(() => {
    app = getTestApp();
  });

  beforeEach(async () => {
    await cleanDatabase();
    const { token: t, user } = await createTestUser();
    token = t;
    userId = user.id;
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
        .send({ company_name: 'Acme Realty' });

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
      await request(app)
        .post('/api/v1/partners/register')
        .set('Authorization', `Bearer ${token}`)
        .send(REGISTER_PAYLOAD);

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

    it('rejects updates that try to change partner_type (immutable after registration)', async () => {
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
  // partner_gifts.activation_code + activation_url are wiped on terminal
  // transitions so a DB dump can never resurrect a redeemed or expired
  // code. The hash stays so verifyActivationCode keeps working for
  // audit / historical lookups.
  // ----------------------------------------------------------------

  describe('partner_gifts plaintext wipe on terminal transition', () => {
    async function seedPartnerWithGift(opts: {
      ownerToken: string;
      ownerId: string;
      homebuyerEmail: string;
      expiresAt?: Date;
    }) {
      await request(app)
        .post('/api/v1/partners/register')
        .set('Authorization', `Bearer ${opts.ownerToken}`)
        .send(REGISTER_PAYLOAD);

      const partnerRow = await pool.query(
        'SELECT id FROM partners WHERE user_id = $1',
        [opts.ownerId],
      );
      const partnerId = partnerRow.rows[0].id;

      // Build a plaintext code + matching hash inline so the test doesn't
      // depend on the createGift code path.
      const raw = crypto.randomBytes(8).toString('hex').toUpperCase();
      const plaintext = `${raw.slice(0, 4)}-${raw.slice(4, 8)}-${raw.slice(8, 12)}-${raw.slice(12, 16)}`;
      const hash = hashActivationCode(plaintext);
      const url = `http://localhost:3000/gifts/activate?code=${encodeURIComponent(plaintext)}`;

      const expiresAt =
        opts.expiresAt ?? new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

      const giftRow = await pool.query(
        `INSERT INTO partner_gifts (
           partner_id, homebuyer_email, homebuyer_name,
           premium_months, status, expires_at,
           activation_code, activation_code_hash, activation_url
         ) VALUES ($1, $2, 'Buyer', 6, 'created', $3, $4, $5, $6)
         RETURNING id`,
        [
          partnerId,
          opts.homebuyerEmail.toLowerCase(),
          expiresAt,
          plaintext,
          hash,
          url,
        ],
      );

      return { partnerId, giftId: giftRow.rows[0].id, plaintext, hash };
    }

    it('activateGift nulls activation_code + activation_url, keeps the hash', async () => {
      const homebuyerEmail = `homebuyer-${crypto.randomUUID()}@test.com`;
      const homebuyer = await createTestUser({ email: homebuyerEmail, emailVerified: true });

      const { giftId, hash } = await seedPartnerWithGift({
        ownerToken: token,
        ownerId: userId,
        homebuyerEmail,
      });

      const result = await PartnersService.activateGift(
        giftId,
        homebuyer.user.id,
        homebuyerEmail,
      );

      expect(result.is_activated).toBe(true);
      expect(result.activation_code).toBeNull();
      expect(result.activation_url).toBeNull();

      // The hash column is the verification source — it must survive.
      const post = await pool.query(
        `SELECT activation_code, activation_code_hash, activation_url
           FROM partner_gifts WHERE id = $1`,
        [giftId],
      );
      expect(post.rows[0].activation_code).toBeNull();
      expect(post.rows[0].activation_url).toBeNull();
      expect(post.rows[0].activation_code_hash).toBe(hash);
    });

    it('resendGiftEmail refuses once activation_code has been wiped', async () => {
      const homebuyerEmail = `homebuyer-${crypto.randomUUID()}@test.com`;

      const { giftId } = await seedPartnerWithGift({
        ownerToken: token,
        ownerId: userId,
        homebuyerEmail,
      });

      // Simulate the daily expiry sweep wiping the plaintext between the
      // partner's "Resend" click and the service-level read.
      await pool.query(
        `UPDATE partner_gifts
            SET status = 'expired',
                activation_code = NULL,
                activation_url = NULL
          WHERE id = $1`,
        [giftId],
      );

      await expect(
        PartnersService.resendGiftEmail(giftId, userId),
      ).rejects.toMatchObject({ statusCode: 400, message: 'Gift has expired' });
    });
  });

  // ----------------------------------------------------------------
  // S-M7: public CSRF mint endpoint for browser clients that bypass
  // the partner-dashboard proxy.
  // ----------------------------------------------------------------

  describe('GET /api/v1/csrf', () => {
    it('mints a fresh 64-char hex token when no cookie is present', async () => {
      const res = await request(app).get('/api/v1/csrf');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.csrfToken).toMatch(/^[a-f0-9]{64}$/);
      expect(res.headers['cache-control']).toBe('no-store');

      const setCookie = res.headers['set-cookie'];
      expect(setCookie).toBeDefined();
      // supertest types the header as `string`, but Express sends an array
      // when there are multiple Set-Cookie entries. Normalise both shapes.
      const cookies = Array.isArray(setCookie) ? setCookie : [setCookie as unknown as string];
      const csrfCookie = cookies.find((c) => c.startsWith('csrf_token='));
      expect(csrfCookie).toBeDefined();
      expect(csrfCookie).toContain(`csrf_token=${res.body.csrfToken}`);
      // SameSite=Lax + non-HttpOnly (double-submit needs JS read access).
      expect(csrfCookie).toMatch(/SameSite=Lax/i);
      expect(csrfCookie).not.toMatch(/HttpOnly/i);
    });

    it('returns the existing well-formed token unchanged (idempotent)', async () => {
      const existing = 'a'.repeat(64);
      const res = await request(app)
        .get('/api/v1/csrf')
        .set('Cookie', `csrf_token=${existing}`);

      expect(res.status).toBe(200);
      expect(res.body.csrfToken).toBe(existing);
    });

    it('replaces a malformed cookie with a fresh token', async () => {
      const res = await request(app)
        .get('/api/v1/csrf')
        .set('Cookie', 'csrf_token=not-a-valid-token');

      expect(res.status).toBe(200);
      expect(res.body.csrfToken).toMatch(/^[a-f0-9]{64}$/);
      expect(res.body.csrfToken).not.toBe('not-a-valid-token');
    });
  });
});
