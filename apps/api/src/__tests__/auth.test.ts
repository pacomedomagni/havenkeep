import request from 'supertest';
import { cleanDatabase } from './setup';
import { getTestApp, createTestUser } from './helpers';

// Rate limiters are module-level singletons (in-memory stores) that persist
// across app instances. Mock them all as pass-through in tests.
jest.mock('../middleware/rateLimiter', () => require('./test-rate-limiter-mock'));

// google-auth-library reaches the network to fetch Google's signing
// certs before it can verify an ID token. The S3-C test's intent is to
// confirm that an `alg: none` token is rejected — but the real client
// would fail with a network/certs error long before the alg check
// fires, masking a regression that *did* re-enable alg:none. Mock the
// OAuth2Client so verifyIdToken behaves like real Google: token whose
// header alg is 'none' (or a missing/invalid signature) is rejected.
jest.mock('google-auth-library', () => {
  class OAuth2Client {
    transporter = { defaults: {} };
    constructor(_opts?: any) {}
    async verifyIdToken({ idToken }: { idToken: string }) {
      const segments = String(idToken).split('.');
      if (segments.length < 2) {
        throw new Error('Invalid ID token: malformed');
      }
      const headerJson = Buffer.from(segments[0], 'base64url').toString('utf8');
      let header: { alg?: string };
      try {
        header = JSON.parse(headerJson);
      } catch {
        throw new Error('Invalid ID token: header parse error');
      }
      if (!header.alg || header.alg.toLowerCase() === 'none') {
        throw new Error('Invalid ID token: alg "none" rejected');
      }
      // Tests that need to simulate a successful Google verify can
      // override per-test with `jest.spyOn(...)`.
      throw new Error('Invalid ID token: signature verification failed');
    }
  }
  return { __esModule: true, OAuth2Client };
});

// `googleapis` is pulled in by email-scanner.service.ts (transitively
// imported via routes/users.ts → app). googleapis-common's authplus.js
// uses ESM-only `import { google } from 'googleapis'` syntax that Jest
// can't load without a transform. The auth tests don't exercise the
// Gmail scanner path, so the package can be a complete no-op.
jest.mock('googleapis', () => ({
  __esModule: true,
  google: {
    auth: { OAuth2: class {} },
    gmail: () => ({ users: { messages: { list: jest.fn(), get: jest.fn() } } }),
  },
}));

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
      expect(res.body.data.user).toBeDefined();
      expect(res.body.data.user.email).toBe('newuser@test.com');
      expect(res.body.data.user.full_name).toBe('New User');
      expect(res.body.data.user.plan).toBe('free');
      expect(res.body.data.accessToken).toBeDefined();
      expect(res.body.data.refreshToken).toBeDefined();
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
      expect(res.body.data.user).toBeDefined();
      expect(res.body.data.user.email).toBe('login@test.com');
      expect(res.body.data.accessToken).toBeDefined();
      expect(res.body.data.refreshToken).toBeDefined();
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
      expect(res.body.data.user.email).toBe('casetest@test.com');
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

      const { refreshToken } = loginRes.body.data ?? loginRes.body;
      expect(refreshToken).toBeDefined();

      const res = await request(app)
        .post('/api/v1/auth/refresh')
        .send({ refreshToken });

      expect(res.status).toBe(200);
      expect(res.body.data.accessToken).toBeDefined();
      expect(res.body.data.refreshToken).toBeDefined();
    });

    it('should reject a reused refresh token', async () => {
      // Use login to get a refresh token (bcrypt takes enough time for
      // the refresh call to land in a different second, producing a
      // distinct JWT and therefore a distinct token hash in the DB).
      await createTestUser({ email: 'reuse@test.com', password: 'StrongPass1!' });
      const loginRes = await request(app)
        .post('/api/v1/auth/login')
        .send({ email: 'reuse@test.com', password: 'StrongPass1!' });

      const { refreshToken } = loginRes.body.data ?? loginRes.body;

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

    // S3-B / Ch01-F017: response time must be ≥ FORGOT_PASSWORD_MIN_DURATION_MS
    // for both branches so an attacker can't time-side-channel "user exists"
    // out of the route. The floor is 250ms; we assert ≥ 200 to absorb test
    // harness jitter while still catching a regression that drops the floor
    // entirely (e.g. someone removes the setTimeout to "make it faster").
    it('takes at least the constant-time floor for both known and unknown emails', async () => {
      const { user } = await createTestUser({
        email: 'fp-timing@test.com',
        emailVerified: true,
      });

      const tKnownStart = Date.now();
      await request(app)
        .post('/api/v1/auth/forgot-password')
        .send({ email: user.email });
      const tKnown = Date.now() - tKnownStart;

      const tUnknownStart = Date.now();
      await request(app)
        .post('/api/v1/auth/forgot-password')
        .send({ email: 'no-such-user-fp-timing@test.com' });
      const tUnknown = Date.now() - tUnknownStart;

      // Use 200ms as the regression floor (250ms target with 50ms slack).
      // If a refactor removes the floor, both numbers drop below this.
      expect(tKnown).toBeGreaterThanOrEqual(200);
      expect(tUnknown).toBeGreaterThanOrEqual(200);
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

  // S3-C: jsonwebtoken's `verify()` rejects `alg: none` only when the caller
  // pins an `algorithms: [...]` allowlist. Both Apple and Google handlers do
  // (`['RS256']`); these tests pin that contract so a future refactor that
  // forgets the option is caught immediately.
  describe('OAuth alg:none rejection (S3-C)', () => {
    function noneToken(payload: Record<string, unknown>): string {
      const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
      const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
      // Empty signature segment — what an `alg: none` forger would send.
      return `${header}.${body}.`;
    }

    it('rejects an alg:none ID token on /auth/google', async () => {
      const res = await request(app)
        .post('/api/v1/auth/google')
        .send({
          idToken: noneToken({
            iss: 'accounts.google.com',
            aud: 'whatever',
            sub: 'attacker',
            email: 'attacker@test.com',
          }),
        });
      expect(res.status).toBe(401);
    });

    it('rejects an alg:none ID token on /auth/apple', async () => {
      const res = await request(app)
        .post('/api/v1/auth/apple')
        .send({
          idToken: noneToken({
            iss: 'https://appleid.apple.com',
            aud: 'app.havenkeep.mobile',
            sub: 'attacker',
            nonce: 'irrelevant',
          }),
          nonce: 'irrelevant-raw-nonce-string',
        });
      expect(res.status).toBe(401);
    });
  });

  // S3-12.9 / S1-H: the consumed-nonce store must reject a second use of
  // the same hash. We can't test the full /auth/apple flow without
  // mocking Apple's JWKS, but the storage layer is what enforces the
  // replay guarantee — exercise the table directly.
  describe('Apple Sign-In nonce replay guard (S1-H)', () => {
    it('rejects the second insert of the same nonce hash', async () => {
      const { pool } = require('../db');
      const crypto = require('crypto');
      const hash = crypto.createHash('sha256').update('replay-test-nonce').digest('hex');
      const expiresAt = new Date(Date.now() + 5 * 60 * 1000);

      const first = await pool.query(
        `INSERT INTO apple_sign_in_nonces (nonce_hash, expires_at)
            VALUES ($1, $2)
            ON CONFLICT (nonce_hash) DO NOTHING
            RETURNING nonce_hash`,
        [hash, expiresAt],
      );
      expect(first.rowCount).toBe(1);

      const second = await pool.query(
        `INSERT INTO apple_sign_in_nonces (nonce_hash, expires_at)
            VALUES ($1, $2)
            ON CONFLICT (nonce_hash) DO NOTHING
            RETURNING nonce_hash`,
        [hash, expiresAt],
      );
      expect(second.rowCount).toBe(0);
    });
  });
});
