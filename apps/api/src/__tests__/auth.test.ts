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
    itemsListRateLimiter: pass,
    csvExportRateLimiter: pass,
    readRateLimiter: pass,
    initializeRateLimiter: jest.fn().mockResolvedValue(undefined),
    shutdownRateLimiter: jest.fn().mockResolvedValue(undefined),
    closeRateLimiterRedis: jest.fn().mockResolvedValue(undefined),
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

    // Audit Ch12-R005: a malformed refresh token must surface as 401 (or
    // 400 from the validator), never a 500. The previous test allowed 500,
    // which codified the bug it was meant to catch.
    it('should reject an invalid refresh token with 401 (audit Ch12-R005)', async () => {
      const res = await request(app)
        .post('/api/v1/auth/refresh')
        .send({ refreshToken: 'not-a-valid-jwt' });
      expect([400, 401]).toContain(res.status);
      expect(res.status).not.toBe(500);
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

      const { accessToken, refreshToken } = registerRes.body.data ?? registerRes.body;

      const res = await request(app)
        .post('/api/v1/auth/logout')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ refreshToken });

      expect(res.status).toBe(200);
    });

    // Audit Ch01-F014: unauthenticated logout used to succeed and let an
    // attacker with a guessed refresh token blacklist arbitrary access
    // tokens. The route now requires a valid access token.
    it('rejects unauthenticated logout', async () => {
      const res = await request(app)
        .post('/api/v1/auth/logout')
        .send({});

      expect(res.status).toBe(401);
    });

    it('should invalidate the refresh token after logout', async () => {
      const registerRes = await request(app)
        .post('/api/v1/auth/register')
        .send({
          email: 'logoutinv@test.com',
          password: 'StrongPass1!',
          fullName: 'Logout Invalidate',
        });

      const { accessToken, refreshToken } = registerRes.body.data ?? registerRes.body;

      await request(app)
        .post('/api/v1/auth/logout')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ refreshToken });

      // Try to use the refresh token after logout
      const refreshRes = await request(app)
        .post('/api/v1/auth/refresh')
        .send({ refreshToken });

      expect(refreshRes.status).toBe(401);
    });
  });

  // ──────────────────── Phase 4 — additional coverage ────────────────────

  describe('POST /api/v1/auth/forgot-password (Ch01-F016/F017/F028)', () => {
    // F016: response shape MUST be identical for unknown vs known emails so
    //   the route isn't an enumeration oracle.
    it('returns the same generic response for unknown and known emails', async () => {
      const { user } = await createTestUser({
        email: 'fp-known@test.com',
        emailVerified: true,
      });
      // Bump a verified flag — createTestUser already does this, but the
      // route also checks auth_provider='email' which the helper sets.

      const known = await request(app)
        .post('/api/v1/auth/forgot-password')
        .send({ email: user.email });
      const unknown = await request(app)
        .post('/api/v1/auth/forgot-password')
        .send({ email: 'nobody-here@test.com' });

      expect(known.status).toBe(200);
      expect(unknown.status).toBe(200);
      expect(known.body.message).toBe(unknown.body.message);
    });

    // F017: never email a reset link to an unverified address.
    it('does not issue a reset token for unverified email accounts', async () => {
      const { user } = await createTestUser({
        email: 'fp-unverified@test.com',
        emailVerified: false,
      });

      const res = await request(app)
        .post('/api/v1/auth/forgot-password')
        .send({ email: user.email });
      expect(res.status).toBe(200);

      const { pool } = require('../db');
      const tokens = await pool.query(
        `SELECT 1 FROM password_reset_tokens WHERE user_id = $1 AND used = FALSE`,
        [user.id],
      );
      expect(tokens.rows.length).toBe(0);
    });
  });

  describe('Refresh token family invalidation (Ch12-T019)', () => {
    // Audit Ch01-F020: a refresh token belongs to exactly ONE user; any
    // attempt to use it on behalf of a different user_id must fail and the
    // server must NOT mass-invalidate based on the attacker's claim.
    it('rejects refresh with no DB-side row even if JWT verifies', async () => {
      const jwt = require('jsonwebtoken');
      const { config } = require('../config');
      const { user } = await createTestUser({ email: 'family@test.com' });

      // Mint a JWT-valid refresh token but never insert it into refresh_tokens.
      const orphan = jwt.sign({ userId: user.id }, config.jwt.refreshSecret, {
        expiresIn: '7d',
      });

      const res = await request(app)
        .post('/api/v1/auth/refresh')
        .send({ refreshToken: orphan });
      expect(res.status).toBe(401);

      // The honest refresh tokens for this user were never issued in this
      // test — we only need to confirm the orphan path doesn't 500 or
      // succeed.
    });
  });

  describe('Email verification token reuse (Ch12-T046)', () => {
    // Verifying twice with the same token must not succeed the second time.
    it('rejects re-use of an email verification token', async () => {
      const crypto = require('crypto');
      const { pool } = require('../db');
      const { user } = await createTestUser({ email: 'reuse@test.com', emailVerified: false });

      const raw = crypto.randomBytes(32).toString('hex');
      const sha = crypto
        .createHmac('sha256', require('../config').config.jwt.refreshSecret)
        .update(raw)
        .digest('hex');
      await pool.query(
        `INSERT INTO email_verification_tokens (user_id, token, expires_at, metadata)
         VALUES ($1, $2, NOW() + INTERVAL '1 hour', '{"type":"register"}'::jsonb)`,
        [user.id, sha],
      );

      const first = await request(app).post('/api/v1/auth/verify-email').send({ token: raw });
      const second = await request(app).post('/api/v1/auth/verify-email').send({ token: raw });

      expect(first.status).toBe(200);
      expect(second.status).toBe(400);
    });
  });
});
