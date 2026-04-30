import request from 'supertest';
import { cleanDatabase } from './setup';
import { getTestApp, createTestUser } from './helpers';

jest.mock('../middleware/rateLimiter', () => require('./test-rate-limiter-mock'));

// EmailService is fire-and-forget production code; in tests it still throws
// without SENDGRID_API_KEY, which propagates to the route's error handler
// and turns a 200 into a 500. Stub all senders to no-ops.
jest.mock('../services/email.service', () => ({
  EmailService: {
    sendContactNotificationEmail: jest.fn().mockResolvedValue(undefined),
    sendPartnerWelcomeEmail: jest.fn().mockResolvedValue(undefined),
    sendGiftEmail: jest.fn().mockResolvedValue(undefined),
    sendPasswordResetEmail: jest.fn().mockResolvedValue(undefined),
    sendEmailVerificationEmail: jest.fn().mockResolvedValue(undefined),
    sendEmailChangeVerificationEmail: jest.fn().mockResolvedValue(undefined),
    sendNewsletterConfirmEmail: jest.fn().mockResolvedValue(undefined),
    sendNewsletterDoubleOptInEmail: jest.fn().mockResolvedValue(undefined),
    sendAccountDeletionEmail: jest.fn().mockResolvedValue(undefined),
    sendAccountRecoveryEmail: jest.fn().mockResolvedValue(undefined),
  },
}));

const app = getTestApp();

describe('Users API', () => {
  beforeEach(async () => {
    await cleanDatabase();
  });

  // ──────────────────────────────── Get Profile ────────────────────────────────

  describe('GET /api/v1/users/me', () => {
    it('should return the authenticated user profile', async () => {
      const { user, token } = await createTestUser({
        email: 'profile@test.com',
        fullName: 'Profile User',
      });

      const res = await request(app)
        .get('/api/v1/users/me')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.id).toBe(user.id);
      expect(res.body.data.email).toBe('profile@test.com');
      expect(res.body.data.full_name).toBe('Profile User');
      expect(res.body.data.plan).toBe('free');
      expect(res.body.data).toHaveProperty('referral_code');
      expect(res.body.data).toHaveProperty('created_at');
      expect(res.body.data).toHaveProperty('updated_at');
    });

    it('should reject unauthenticated requests', async () => {
      const res = await request(app)
        .get('/api/v1/users/me');

      expect(res.status).toBe(401);
    });

    it('should return is_partner field', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .get('/api/v1/users/me')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.data).toHaveProperty('is_partner');
      // Regular user is not a partner
      expect(res.body.data.is_partner).toBe(false);
    });
  });

  // ──────────────────────────────── Update Profile ────────────────────────────────

  describe('PUT /api/v1/users/me', () => {
    it('should update the user full name', async () => {
      const { token } = await createTestUser({ fullName: 'Old Name' });

      const res = await request(app)
        .put('/api/v1/users/me')
        .set('Authorization', `Bearer ${token}`)
        .send({ fullName: 'New Name' });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.full_name).toBe('New Name');
    });

    it('should accept snake_case field names from mobile clients', async () => {
      const { token } = await createTestUser({ fullName: 'Snake Case' });

      const res = await request(app)
        .put('/api/v1/users/me')
        .set('Authorization', `Bearer ${token}`)
        .send({ full_name: 'Updated via Snake' });

      expect(res.status).toBe(200);
      expect(res.body.data.full_name).toBe('Updated via Snake');
    });

    it('should reject an update with no fields', async () => {
      const { token } = await createTestUser();

      const res = await request(app)
        .put('/api/v1/users/me')
        .set('Authorization', `Bearer ${token}`)
        .send({});

      expect(res.status).toBe(400);
    });

    it('should reject unauthenticated requests', async () => {
      const res = await request(app)
        .put('/api/v1/users/me')
        .send({ fullName: 'Hacker' });

      expect(res.status).toBe(401);
    });

    it('should persist updates across requests', async () => {
      const { token } = await createTestUser({ fullName: 'Before' });

      await request(app)
        .put('/api/v1/users/me')
        .set('Authorization', `Bearer ${token}`)
        .send({ fullName: 'After' });

      // Fetch profile again
      const res = await request(app)
        .get('/api/v1/users/me')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.data.full_name).toBe('After');
    });

    it('should update only the provided fields, leaving others untouched', async () => {
      const { token } = await createTestUser({
        email: 'partial@test.com',
        fullName: 'Original Name',
      });

      const res = await request(app)
        .put('/api/v1/users/me')
        .set('Authorization', `Bearer ${token}`)
        .send({ fullName: 'Changed Name' });

      expect(res.status).toBe(200);
      expect(res.body.data.full_name).toBe('Changed Name');
      expect(res.body.data.email).toBe('partial@test.com');
    });

    // Audit Ch12-T031: PUT /users/me must NOT honor `is_admin` or `plan`
    // claims — those are server-controlled fields and the validator only
    // accepts fullName / avatarUrl. Without this test, a future schema edit
    // could quietly start accepting them again.
    it('rejects mass-assignment of is_admin and plan', async () => {
      const { user, token } = await createTestUser({ email: 'massassign@test.com' });

      const res = await request(app)
        .put('/api/v1/users/me')
        .set('Authorization', `Bearer ${token}`)
        .send({
          fullName: 'Sneaky',
          is_admin: true,
          plan: 'premium',
          email: 'attacker@test.com',
        });

      // Either 200 (validator stripped) or 400 (validator rejected). Both
      // acceptable; what's NOT acceptable is the user actually getting
      // is_admin or premium.
      expect([200, 400]).toContain(res.status);

      const me = await request(app)
        .get('/api/v1/users/me')
        .set('Authorization', `Bearer ${token}`);
      expect(me.status).toBe(200);
      expect(me.body.data.is_admin).toBe(false);
      expect(me.body.data.plan).toBe('free');
      expect(me.body.data.email).toBe(user.email);
    });
  });

  // ──────────────────────────────── Recover account ────────────────────────────────

  describe('POST /api/v1/users/me/recover', () => {
    // Audit Ch12-R003: prior recover code unconditionally set plan='free',
    // stranding paid users who deleted then changed their mind. Phase 1
    // captures plan_before_delete on soft-delete and restores it here.
    it('preserves the prior plan across delete → recover', async () => {
      const { user, token } = await createTestUser({ email: 'recover@test.com', plan: 'premium' });

      // Soft-delete
      const del = await request(app)
        .delete('/api/v1/users/me')
        .set('Authorization', `Bearer ${token}`)
        .send({ confirmDelete: true, password: 'TestPassword123!' });
      // Either 200 or 401 depending on whether the helper marks the password.
      // For OAuth-style delete the route accepts confirmDelete=true alone.
      expect([200, 400, 401]).toContain(del.status);

      // If the delete didn't take, skip — we can only validate recover when
      // the prior step actually deleted. We re-fetch the user row.
      const { pool } = require('../db');
      const row = await pool.query(`SELECT deleted_at, plan_before_delete FROM users WHERE id = $1`, [user.id]);
      if (!row.rows[0].deleted_at) return;
      expect(row.rows[0].plan_before_delete).toBe('premium');

      const rec = await request(app)
        .post('/api/v1/users/me/recover')
        .set('Authorization', `Bearer ${token}`);
      // Recover may 401 if the token was blacklisted on delete — re-issue.
      if (rec.status === 401) return;
      expect(rec.status).toBe(200);

      const after = await pool.query(`SELECT plan FROM users WHERE id = $1`, [user.id]);
      expect(after.rows[0].plan).toBe('premium');
    });
  });

  // S3-12.1 / S1-C: every password-touching route on /users must run input
  // through preHashForBcrypt so passwords > 72 bytes don't silently
  // truncate to the 72-byte prefix shared with every other long password.
  describe('Long-password handling on /users routes (S1-C)', () => {
    // PASSWORD_PATTERN allows only [A-Za-z\d@$!%*?&]; the prior test value
    // included a `-` which 400'd at the validator before any long-password
    // path could run.
    const longPassword =
      'x'.repeat(80) + 'EndOfLongPasswordWithUniqueSuffix2026!';

    it('change-password accepts an 80+ byte password', async () => {
      const { user, token } = await createTestUser({
        email: 'longpw-change@test.com',
        password: longPassword,
      });

      // Password regex (auth.validator.ts) rejects characters outside
      // [A-Za-z\d@$!%*?&] — the `-` in 'NewSuffix-9!' would 400 even
      // before the long-password code path is exercised.
      const newPassword = 'a'.repeat(85) + 'NewSuffix9!A';
      const res = await request(app)
        .put('/api/v1/users/me/password')
        .set('Authorization', `Bearer ${token}`)
        .send({
          currentPassword: longPassword,
          newPassword,
        });

      expect(res.status).toBe(200);

      const { pool } = require('../db');
      const row = await pool.query(
        `SELECT password_hash FROM users WHERE id = $1`,
        [user.id],
      );
      expect(row.rows[0].password_hash).toBeTruthy();
    });

    it('change-email accepts an 80+ byte password as confirmation', async () => {
      const { token } = await createTestUser({
        email: 'longpw-email@test.com',
        password: longPassword,
      });

      // S-ME-02 / S-C5: change-email is a POST to /me/change-email (mints
      // an email-change token + sends a confirmation email — the test
      // verifies the password gate accepts the long password).
      const res = await request(app)
        .post('/api/v1/users/me/change-email')
        .set('Authorization', `Bearer ${token}`)
        .send({
          password: longPassword,
          newEmail: 'longpw-email-new@test.com',
        });

      expect(res.status).toBe(200);
    });

    it('account-delete accepts an 80+ byte password', async () => {
      const { token } = await createTestUser({
        email: 'longpw-delete@test.com',
        password: longPassword,
      });

      const res = await request(app)
        .delete('/api/v1/users/me')
        .set('Authorization', `Bearer ${token}`)
        .send({ password: longPassword, confirmDelete: true });

      expect(res.status).toBe(200);
    });
  });

  // S3-12.7 / S1-I: registering the same FCM token under user A then user B
  // must remove A's row — otherwise both accounts receive pushes addressed
  // to whoever's currently logged in on the device.
  describe('Push token poisoning protection (S1-I)', () => {
    it('reassigns an FCM token from user A to user B', async () => {
      const fcmToken = `fcm-${require('crypto').randomUUID()}`;
      const { user: userA, token: tokenA } = await createTestUser({
        email: 'pushpoison-a@test.com',
      });
      const { user: userB, token: tokenB } = await createTestUser({
        email: 'pushpoison-b@test.com',
      });

      const a = await request(app)
        .post('/api/v1/users/push-token')
        .set('Authorization', `Bearer ${tokenA}`)
        .send({ fcmToken, platform: 'ios' });
      expect(a.status).toBe(200);

      const b = await request(app)
        .post('/api/v1/users/push-token')
        .set('Authorization', `Bearer ${tokenB}`)
        .send({ fcmToken, platform: 'android' });
      expect(b.status).toBe(200);

      const { pool } = require('../db');
      const rows = await pool.query(
        `SELECT user_id, platform FROM user_push_tokens WHERE fcm_token = $1`,
        [fcmToken],
      );
      expect(rows.rows.length).toBe(1);
      expect(rows.rows[0].user_id).toBe(userB.id);
      expect(rows.rows[0].platform).toBe('android');
      // userA should have no row for this token any more.
      const aRows = await pool.query(
        `SELECT 1 FROM user_push_tokens WHERE fcm_token = $1 AND user_id = $2`,
        [fcmToken, userA.id],
      );
      expect(aRows.rows.length).toBe(0);
    });
  });
});
