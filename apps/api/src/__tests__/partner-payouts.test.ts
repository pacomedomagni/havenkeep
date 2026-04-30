import request from 'supertest';
import { cleanDatabase } from './setup';
import { getTestApp, createTestUser } from './helpers';
import { pool } from '../db';

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

// Mock the Stripe client factory so tests don't reach the network. Each
// `transfers.create` returns a deterministic transfer id derived from the
// idempotencyKey so a re-run yields the same row state.
const transfersCreate = jest.fn(async (_args: any, opts: any) => ({
  id: `tr_test_${opts?.idempotencyKey ?? 'no-key'}`,
}));
const accountsCreateLoginLink = jest.fn(async (accountId: string) => ({
  url: `https://connect.stripe.test/login/${accountId}`,
}));

jest.mock('../utils/stripe-client', () => ({
  createStripeClient: () => ({
    transfers: { create: transfersCreate },
    accounts: { createLoginLink: accountsCreateLoginLink },
  }),
}));

async function makeActivePartner(
  userId: string,
  opts: { stripeStatus?: string; stripeAccountId?: string | null } = {},
) {
  const { stripeStatus = 'enabled', stripeAccountId = 'acct_test_partner' } = opts;
  const result = await pool.query(
    `INSERT INTO partners (user_id, partner_type, company_name, status, is_active, subscription_tier, stripe_account_id, stripe_account_status)
       VALUES ($1, 'realtor', 'Test Realty', 'active', TRUE, 'basic', $2, $3::partner_stripe_account_status)
     RETURNING id`,
    [userId, stripeAccountId, stripeStatus],
  );
  return result.rows[0].id;
}

async function insertCommission(
  partnerId: string,
  opts: { status: string; amount?: number; createdDaysAgo?: number; reversed?: boolean },
) {
  const { status, amount = 9.9, createdDaysAgo = 0, reversed = false } = opts;
  const inserted = await pool.query(
    `INSERT INTO partner_commissions (partner_id, type, amount, commission_rate, status, reference_id, reference_type, approved_at, created_at)
       VALUES ($1, 'gift', $2, 0.10, $3::commission_status, gen_random_uuid(), 'partner_gift',
               CASE WHEN $3::commission_status IN ('approved', 'paid') THEN NOW() - ($4::int || ' days')::interval ELSE NULL END,
               NOW() - ($4::int || ' days')::interval)
     RETURNING id`,
    [partnerId, amount, status, createdDaysAgo],
  );
  const commissionId = inserted.rows[0].id;
  if (reversed) {
    await pool.query(
      `INSERT INTO partner_commissions (partner_id, type, amount, commission_rate, status, reversal_of_commission_id, reference_id, reference_type)
         VALUES ($1, 'gift', $2, 0.10, 'reversed', $3, gen_random_uuid(), 'partner_gift')`,
      [partnerId, -amount, commissionId],
    );
  }
  return commissionId;
}

describe('Partner self-service payouts', () => {
  let app: ReturnType<typeof getTestApp>;
  let userId: string;
  let token: string;

  beforeAll(() => {
    app = getTestApp();
  });

  beforeEach(async () => {
    await cleanDatabase();
    transfersCreate.mockClear();
    accountsCreateLoginLink.mockClear();
    const u = await createTestUser();
    userId = u.user.id;
    token = u.token;
  });

  describe('GET /api/v1/partners/me/payouts/summary', () => {
    it('returns 403 for non-partner users', async () => {
      const res = await request(app)
        .get('/api/v1/partners/me/payouts/summary')
        .set('Authorization', `Bearer ${token}`);
      expect(res.status).toBe(403);
    });

    it('returns zero totals for a fresh partner with no commissions', async () => {
      await makeActivePartner(userId);
      const res = await request(app)
        .get('/api/v1/partners/me/payouts/summary')
        .set('Authorization', `Bearer ${token}`);
      expect(res.status).toBe(200);
      expect(res.body.data).toMatchObject({
        pending_amount: 0,
        approved_amount: 0,
        paid_lifetime: 0,
        paid_ytd: 0,
        stripe_payouts_enabled: true,
      });
    });

    it('aggregates pending + approved + paid totals correctly', async () => {
      const partnerId = await makeActivePartner(userId);
      await insertCommission(partnerId, { status: 'pending', amount: 5 });
      await insertCommission(partnerId, { status: 'approved', amount: 10 });
      await insertCommission(partnerId, { status: 'approved', amount: 15 });
      await insertCommission(partnerId, { status: 'paid', amount: 20 });
      const res = await request(app)
        .get('/api/v1/partners/me/payouts/summary')
        .set('Authorization', `Bearer ${token}`);
      expect(res.status).toBe(200);
      expect(res.body.data.pending_amount).toBe(5);
      expect(res.body.data.approved_amount).toBe(25);
      expect(res.body.data.paid_lifetime).toBe(20);
    });
  });

  describe('POST /api/v1/partners/me/payouts', () => {
    it('returns 409 when Stripe Connect is not enabled', async () => {
      const partnerId = await makeActivePartner(userId, { stripeStatus: 'pending' });
      await insertCommission(partnerId, { status: 'approved' });
      const res = await request(app)
        .post('/api/v1/partners/me/payouts')
        .set('Authorization', `Bearer ${token}`);
      expect(res.status).toBe(409);
      expect(res.body.error).toMatch(/onboarding/i);
      expect(transfersCreate).not.toHaveBeenCalled();
    });

    it('returns 200 with zero counts when no commissions are eligible', async () => {
      await makeActivePartner(userId);
      const res = await request(app)
        .post('/api/v1/partners/me/payouts')
        .set('Authorization', `Bearer ${token}`);
      expect(res.status).toBe(200);
      expect(res.body.data).toMatchObject({ paid_count: 0, failed_count: 0, paid_total: 0 });
      expect(transfersCreate).not.toHaveBeenCalled();
    });

    it('pays approved commissions one transfer per row', async () => {
      const partnerId = await makeActivePartner(userId);
      await insertCommission(partnerId, { status: 'approved', amount: 10 });
      await insertCommission(partnerId, { status: 'approved', amount: 25 });
      const res = await request(app)
        .post('/api/v1/partners/me/payouts')
        .set('Authorization', `Bearer ${token}`);
      expect(res.status).toBe(200);
      expect(res.body.data.paid_count).toBe(2);
      expect(res.body.data.paid_total).toBe(35);
      expect(transfersCreate).toHaveBeenCalledTimes(2);
      const updated = await pool.query(
        `SELECT COUNT(*) FROM partner_commissions WHERE partner_id = $1 AND status = 'paid'`,
        [partnerId],
      );
      expect(Number(updated.rows[0].count)).toBe(2);
    });

    it('skips pending commissions even on a successful sweep', async () => {
      const partnerId = await makeActivePartner(userId);
      await insertCommission(partnerId, { status: 'approved', amount: 10 });
      await insertCommission(partnerId, { status: 'pending', amount: 50 });
      const res = await request(app)
        .post('/api/v1/partners/me/payouts')
        .set('Authorization', `Bearer ${token}`);
      expect(res.status).toBe(200);
      expect(res.body.data.paid_total).toBe(10);
      expect(transfersCreate).toHaveBeenCalledTimes(1);
    });

    it('continues sweeping when a single transfer fails', async () => {
      const partnerId = await makeActivePartner(userId);
      await insertCommission(partnerId, { status: 'approved', amount: 10 });
      await insertCommission(partnerId, { status: 'approved', amount: 20 });
      transfersCreate
        .mockResolvedValueOnce({ id: 'tr_test_ok' } as any)
        .mockRejectedValueOnce(new Error('Stripe boom'));
      const res = await request(app)
        .post('/api/v1/partners/me/payouts')
        .set('Authorization', `Bearer ${token}`);
      expect(res.status).toBe(200);
      expect(res.body.data.paid_count).toBe(1);
      expect(res.body.data.failed_count).toBe(1);
      const remaining = await pool.query(
        `SELECT COUNT(*) FROM partner_commissions WHERE partner_id = $1 AND status = 'approved'`,
        [partnerId],
      );
      expect(Number(remaining.rows[0].count)).toBe(1);
    });

    it('stamps last_payout_requested_at even on a zero-row sweep', async () => {
      await makeActivePartner(userId);
      await request(app)
        .post('/api/v1/partners/me/payouts')
        .set('Authorization', `Bearer ${token}`);
      const stamp = await pool.query(
        `SELECT last_payout_requested_at FROM partners WHERE user_id = $1`,
        [userId],
      );
      expect(stamp.rows[0].last_payout_requested_at).not.toBeNull();
    });
  });

  describe('POST /api/v1/partners/me/tax-form-link', () => {
    it('returns 409 if Stripe Connect onboarding has not started', async () => {
      await makeActivePartner(userId, { stripeAccountId: null, stripeStatus: 'unknown' });
      const res = await request(app)
        .post('/api/v1/partners/me/tax-form-link')
        .set('Authorization', `Bearer ${token}`);
      expect(res.status).toBe(409);
      expect(accountsCreateLoginLink).not.toHaveBeenCalled();
    });

    it('returns a Stripe-hosted login link when Connect is set up', async () => {
      await makeActivePartner(userId);
      const res = await request(app)
        .post('/api/v1/partners/me/tax-form-link')
        .set('Authorization', `Bearer ${token}`);
      expect(res.status).toBe(200);
      expect(res.body.data.url).toMatch(/^https:\/\/connect\.stripe\.test\//);
      expect(accountsCreateLoginLink).toHaveBeenCalledWith('acct_test_partner');
    });
  });
});
