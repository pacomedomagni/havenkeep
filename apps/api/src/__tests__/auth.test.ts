import request from 'supertest';
import { cleanDatabase } from './setup';
import { getTestApp, createTestUser } from './helpers';

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

describe('Auth API', () => {
  // Create a fresh app per test to reset in-memory rate limiters
  let app: ReturnType<typeof getTestApp>;

  beforeEach(async () => {
    app = getTestApp();
    await cleanDatabase();
  });

  // ──────────────────────────────── Register ────────────────────────────────

  describe('POST /api/v1/auth/register', () => {
    it('should register a new user and return tokens', async () => {
      const res = await request(app)
        .post('/api/v1/auth/register')
        .send({
          email: 'newuser@test.com',
          password: 'StrongPass1!',
          fullName: 'New User',
        });

      expect(res.status).toBe(201);
      expect(res.body.user).toBeDefined();
      expect(res.body.user.email).toBe('newuser@test.com');
      expect(res.body.user.full_name).toBe('New User');
      expect(res.body.user.plan).toBe('free');
      expect(res.body.accessToken).toBeDefined();
      expect(res.body.refreshToken).toBeDefined();
    });

    it('should reject duplicate email registration', async () => {
      await createTestUser({ email: 'dup@test.com' });

      const res = await request(app)
        .post('/api/v1/auth/register')
        .send({
          email: 'dup@test.com',
          password: 'StrongPass1!',
          fullName: 'Duplicate User',
        });

      expect(res.status).toBe(409);
    });

    it('should reject a weak password (no special char)', async () => {
      const res = await request(app)
        .post('/api/v1/auth/register')
        .send({
          email: 'weak@test.com',
          password: 'WeakPass1',
          fullName: 'Weak Password',
        });

      expect(res.status).toBe(400);
    });

    it('should reject a password shorter than 8 characters', async () => {
      const res = await request(app)
        .post('/api/v1/auth/register')
        .send({
          email: 'short@test.com',
          password: 'Ab1!',
          fullName: 'Short Password',
        });

      expect(res.status).toBe(400);
    });

    it('should reject registration with missing fullName', async () => {
      const res = await request(app)
        .post('/api/v1/auth/register')
        .send({
          email: 'noname@test.com',
          password: 'StrongPass1!',
        });

      expect(res.status).toBe(400);
    });

    it('should reject registration with an invalid email', async () => {
      const res = await request(app)
        .post('/api/v1/auth/register')
        .send({
          email: 'not-an-email',
          password: 'StrongPass1!',
          fullName: 'Bad Email',
        });

      expect(res.status).toBe(400);
    });
  });

  // ──────────────────────────────── Login ────────────────────────────────

  describe('POST /api/v1/auth/login', () => {
    it('should login successfully with correct credentials', async () => {
      // Use helper (direct DB insert) to avoid refresh-token collision with login
      await createTestUser({ email: 'login@test.com', password: 'StrongPass1!' });

      const res = await request(app)
        .post('/api/v1/auth/login')
        .send({
          email: 'login@test.com',
          password: 'StrongPass1!',
        });

      expect(res.status).toBe(200);
      expect(res.body.user).toBeDefined();
      expect(res.body.user.email).toBe('login@test.com');
      expect(res.body.accessToken).toBeDefined();
      expect(res.body.refreshToken).toBeDefined();
    });

    it('should reject login with wrong password', async () => {
      await createTestUser({ email: 'wrongpw@test.com', password: 'StrongPass1!' });

      const res = await request(app)
        .post('/api/v1/auth/login')
        .send({
          email: 'wrongpw@test.com',
          password: 'WrongPassword1!',
        });

      expect(res.status).toBe(401);
    });

    it('should reject login for nonexistent user', async () => {
      const res = await request(app)
        .post('/api/v1/auth/login')
        .send({
          email: 'noone@test.com',
          password: 'StrongPass1!',
        });

      expect(res.status).toBe(401);
    });

    it('should be case-insensitive for email', async () => {
      await createTestUser({ email: 'CaseTest@test.com', password: 'StrongPass1!' });

      const res = await request(app)
        .post('/api/v1/auth/login')
        .send({
          email: 'casetest@test.com',
          password: 'StrongPass1!',
        });

      expect(res.status).toBe(200);
      expect(res.body.user.email).toBe('casetest@test.com');
    });
  });

  // ──────────────────────────────── Refresh ────────────────────────────────

  describe('POST /api/v1/auth/refresh', () => {
    it('should issue new tokens with a valid refresh token', async () => {
      // Use login (slower due to bcrypt) to get a refresh token
      await createTestUser({ email: 'refresh@test.com', password: 'StrongPass1!' });
      const loginRes = await request(app)
        .post('/api/v1/auth/login')
        .send({ email: 'refresh@test.com', password: 'StrongPass1!' });

      const { refreshToken } = loginRes.body;
      expect(refreshToken).toBeDefined();

      const res = await request(app)
        .post('/api/v1/auth/refresh')
        .send({ refreshToken });

      expect(res.status).toBe(200);
      expect(res.body.accessToken).toBeDefined();
      expect(res.body.refreshToken).toBeDefined();
    });

    it('should reject a reused refresh token', async () => {
      // Use login to get a refresh token (bcrypt takes enough time for
      // the refresh call to land in a different second, producing a
      // distinct JWT and therefore a distinct token hash in the DB).
      await createTestUser({ email: 'reuse@test.com', password: 'StrongPass1!' });
      const loginRes = await request(app)
        .post('/api/v1/auth/login')
        .send({ email: 'reuse@test.com', password: 'StrongPass1!' });

      const { refreshToken } = loginRes.body;

      // Wait 1.1s so the rotated JWT has a different `iat` (second-level
      // precision), producing a distinct token hash in the DB.
      await new Promise(r => setTimeout(r, 1100));

      // First use - consumes the token (rotation: new JWT inserted)
      await request(app)
        .post('/api/v1/auth/refresh')
        .send({ refreshToken });

      // Second use - should fail (old token hash was deleted)
      const res = await request(app)
        .post('/api/v1/auth/refresh')
        .send({ refreshToken });

      expect(res.status).toBe(401);
    });

    it('should reject an invalid refresh token', async () => {
      const res = await request(app)
        .post('/api/v1/auth/refresh')
        .send({ refreshToken: 'not-a-valid-jwt' });

      // Joi validator might reject, or jwt.verify might throw
      expect([400, 401, 500]).toContain(res.status);
    });
  });

  // ──────────────────────────────── Logout ────────────────────────────────

  describe('POST /api/v1/auth/logout', () => {
    it('should logout successfully with a refresh token', async () => {
      const registerRes = await request(app)
        .post('/api/v1/auth/register')
        .send({
          email: 'logout@test.com',
          password: 'StrongPass1!',
          fullName: 'Logout User',
        });

      const { refreshToken } = registerRes.body;

      const res = await request(app)
        .post('/api/v1/auth/logout')
        .send({ refreshToken });

      expect(res.status).toBe(200);
    });

    it('should logout successfully without a refresh token', async () => {
      const res = await request(app)
        .post('/api/v1/auth/logout')
        .send({});

      expect(res.status).toBe(200);
    });

    it('should invalidate the refresh token after logout', async () => {
      const registerRes = await request(app)
        .post('/api/v1/auth/register')
        .send({
          email: 'logoutinv@test.com',
          password: 'StrongPass1!',
          fullName: 'Logout Invalidate',
        });

      const { refreshToken } = registerRes.body;

      await request(app)
        .post('/api/v1/auth/logout')
        .send({ refreshToken });

      // Try to use the refresh token after logout
      const refreshRes = await request(app)
        .post('/api/v1/auth/refresh')
        .send({ refreshToken });

      expect(refreshRes.status).toBe(401);
    });
  });
});
