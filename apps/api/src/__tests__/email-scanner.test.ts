import request from 'supertest';
import { cleanDatabase } from './setup';
import { getTestApp, createTestUser } from './helpers';
import { encryptToken, decryptToken } from '../utils/oauth-encryption';

jest.mock('../middleware/rateLimiter', () => require('./test-rate-limiter-mock'));

// ------------------------------------------------------------------
// Mock EmailScannerService for the route-level tests so we don't make
// real Gmail/Outlook/OpenAI calls. The service-level tests below use
// the real implementation against the test DB.
// ------------------------------------------------------------------
const mockScan = {
  id: '00000000-0000-0000-0000-000000000001',
  user_id: 'placeholder',
  provider: 'gmail',
  status: 'pending',
  emails_scanned: 0,
  receipts_found: 0,
  items_imported: 0,
  error_message: null,
  date_range_start: null,
  date_range_end: null,
  created_at: new Date().toISOString(),
  completed_at: null,
};

const mockReviewRow = {
  id: '00000000-0000-0000-0000-0000000000aa',
  user_id: 'placeholder',
  email_scan_id: mockScan.id,
  sender_address: 'someone@example.com',
  sender_domain: 'example.com',
  subject: 'Order confirmation',
  suggested_item: { productName: 'Mystery TV' },
  confidence_score: '0.4',
  state: 'pending',
  rejection_reason: null,
  rejected_by_pattern: null,
  reviewed_at: null,
  applied_item_id: null,
  created_at: new Date().toISOString(),
};

jest.mock('../services/email-scanner.service', () => ({
  EmailScannerService: {
    initiateScan: jest.fn().mockImplementation(async (userId: string) => ({
      ...mockScan,
      user_id: userId,
    })),
    getScanStatus: jest.fn().mockImplementation(async (scanId: string, userId: string) => ({
      ...mockScan,
      id: scanId,
      user_id: userId,
    })),
    getUserScans: jest.fn().mockImplementation(async (userId: string) => [
      { ...mockScan, user_id: userId },
    ]),
    listPendingReviews: jest.fn().mockImplementation(async (userId: string) => [
      { ...mockReviewRow, user_id: userId },
    ]),
    approveReview: jest.fn().mockResolvedValue({ item_id: '11111111-1111-1111-1111-111111111111' }),
    rejectReview: jest.fn().mockResolvedValue(undefined),
    revokeIntegration: jest.fn().mockResolvedValue(undefined),
  },
}));

jest.mock('../utils/oauth-encryption', () => {
  const actual = jest.requireActual('../utils/oauth-encryption');
  return {
    ...actual,
    isOAuthEncryptionConfigured: () => true,
  };
});

describe('Email Scanner Routes', () => {
  let app: ReturnType<typeof getTestApp>;
  let premiumToken: string;
  let freeToken: string;
  let scanId: string;

  beforeAll(() => {
    app = getTestApp();
  });

  beforeEach(async () => {
    await cleanDatabase();

    const premium = await createTestUser({ plan: 'premium' });
    premiumToken = premium.token;

    const free = await createTestUser({ plan: 'free' });
    freeToken = free.token;

    scanId = mockScan.id;
  });

  describe('POST /api/v1/email-scanner/scan', () => {
    it('should return 401 when no auth token is provided', async () => {
      const res = await request(app)
        .post('/api/v1/email-scanner/scan')
        .send({ provider: 'gmail', code: 'auth-code', redirect_uri: 'https://example.com/cb' });

      expect(res.status).toBe(401);
    });

    it('should return 403 for a non-premium user', async () => {
      // The premium gate fires before the state-token verification. Send
      // a fake state string that satisfies Joi's `.min(20)` so we clear
      // body validation and the premium gate is what gets exercised.
      // (Both /scan and /state-token are premium-gated; we couldn't
      // legitimately mint a state token as a free user anyway.)
      const res = await request(app)
        .post('/api/v1/email-scanner/scan')
        .set('Authorization', `Bearer ${freeToken}`)
        .send({
          provider: 'gmail',
          code: 'auth-code',
          redirect_uri: 'havenkeep://oauth-callback',
          state: 'a'.repeat(40),
        });

      expect(res.status).toBe(403);
    });

    it('should return 400 when required fields are missing', async () => {
      const res = await request(app)
        .post('/api/v1/email-scanner/scan')
        .set('Authorization', `Bearer ${premiumToken}`)
        .send({});

      expect(res.status).toBe(400);
    });

    it('should reject any incoming access_token field', async () => {
      const res = await request(app)
        .post('/api/v1/email-scanner/scan')
        .set('Authorization', `Bearer ${premiumToken}`)
        .send({
          provider: 'gmail',
          code: 'auth-code',
          redirect_uri: 'havenkeep://oauth-callback',
          access_token: 'should-be-rejected',
        });

      expect(res.status).toBe(400);
    });

    it('should reject any incoming accessToken field', async () => {
      const res = await request(app)
        .post('/api/v1/email-scanner/scan')
        .set('Authorization', `Bearer ${premiumToken}`)
        .send({
          provider: 'gmail',
          code: 'auth-code',
          redirect_uri: 'havenkeep://oauth-callback',
          accessToken: 'should-be-rejected',
        });

      expect(res.status).toBe(400);
    });

    it('should initiate a scan and return 202 for a premium user', async () => {
      // H47: mint a state token first; /scan now requires it.
      const stateRes = await request(app)
        .post('/api/v1/email-scanner/state-token')
        .set('Authorization', `Bearer ${premiumToken}`);
      expect(stateRes.status).toBe(200);
      const state = stateRes.body.data.state as string;
      expect(state).toBeTruthy();

      const res = await request(app)
        .post('/api/v1/email-scanner/scan')
        .set('Authorization', `Bearer ${premiumToken}`)
        .send({
          provider: 'gmail',
          code: 'authorization-code-from-google',
          redirect_uri: 'havenkeep://oauth-callback',
          state,
        });

      expect(res.status).toBe(202);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toHaveProperty('id');
      expect(res.body.data).toHaveProperty('status');
    });
  });

  describe('GET /api/v1/email-scanner/scans/:id', () => {
    it('should return the scan status for a premium user', async () => {
      const res = await request(app)
        .get(`/api/v1/email-scanner/scans/${scanId}`)
        .set('Authorization', `Bearer ${premiumToken}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.id).toBe(scanId);
    });
  });

  describe('GET /api/v1/email-scanner/scans', () => {
    it('should return a list of scans for a premium user', async () => {
      const res = await request(app)
        .get('/api/v1/email-scanner/scans')
        .set('Authorization', `Bearer ${premiumToken}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(Array.isArray(res.body.data)).toBe(true);
    });
  });

  describe('GET /api/v1/email-scanner/review', () => {
    it('returns pending review-queue rows for the user', async () => {
      const res = await request(app)
        .get('/api/v1/email-scanner/review')
        .set('Authorization', `Bearer ${premiumToken}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(Array.isArray(res.body.data)).toBe(true);
      expect(res.body.data[0]).toHaveProperty('sender_domain');
    });

    it('requires premium', async () => {
      const res = await request(app)
        .get('/api/v1/email-scanner/review')
        .set('Authorization', `Bearer ${freeToken}`);
      expect(res.status).toBe(403);
    });
  });

  describe('POST /api/v1/email-scanner/review/:id/approve', () => {
    it('approves a queued row and returns the new item id', async () => {
      const reviewId = '00000000-0000-0000-0000-0000000000aa';
      const res = await request(app)
        .post(`/api/v1/email-scanner/review/${reviewId}/approve`)
        .set('Authorization', `Bearer ${premiumToken}`)
        .send({});

      expect(res.status).toBe(201);
      expect(res.body.data).toHaveProperty('item_id');
    });
  });

  describe('POST /api/v1/email-scanner/review/:id/reject', () => {
    it('rejects a queued row', async () => {
      const reviewId = '00000000-0000-0000-0000-0000000000aa';
      const res = await request(app)
        .post(`/api/v1/email-scanner/review/${reviewId}/reject`)
        .set('Authorization', `Bearer ${premiumToken}`)
        .send({ reason: 'not mine' });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
    });
  });
});

// ------------------------------------------------------------------
// Service-level tests (no route mock). These exercise the real
// EmailScannerService to confirm the trusted-domain auto-create path,
// the review-queue path, and the OAuth token encryption round-trip.
// ------------------------------------------------------------------
describe('EmailScannerService — trusted-domain + review queue', () => {
  // Lazy-require because the top-level mock above replaces the module for
  // the route tests; we want the real implementation here.
  jest.unmock('../services/email-scanner.service');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { EmailScannerService: RealService } = jest.requireActual(
    '../services/email-scanner.service',
  );
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { pool } = jest.requireActual('../db');

  // Reach into the private methods we need to drive the test path. These
  // tests are tightly coupled to the implementation on purpose — they
  // assert the security-relevant gating logic.
  const performScan = (...args: any[]) =>
    (RealService as any).performScan.apply(RealService, args);
  const enqueueReview = (...args: any[]) =>
    (RealService as any).enqueueReview.apply(RealService, args);
  const createItemFromReceipt = (...args: any[]) =>
    (RealService as any).createItemFromReceipt.apply(RealService, args);

  let userId: string;
  let scanId: string;

  beforeEach(async () => {
    await cleanDatabase();
    const premium = await createTestUser({ plan: 'premium' });
    userId = premium.user.id;

    // Premium user needs a home for createItemFromReceipt to succeed.
    const home = await pool.query(
      `INSERT INTO homes (user_id, name) VALUES ($1, 'Test Home') RETURNING id`,
      [userId],
    );
    void home;

    const scan = await pool.query(
      `INSERT INTO email_scans (user_id, provider, status)
       VALUES ($1, 'gmail', 'pending') RETURNING id`,
      [userId],
    );
    scanId = scan.rows[0].id;

    // user_analytics row is needed by performScan's UPDATE.
    await pool.query(
      `INSERT INTO user_analytics (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING`,
      [userId],
    );
  });

  it('createItemFromReceipt: builds a real items row from an extracted receipt', async () => {
    const created = await createItemFromReceipt(
      userId,
      {
        productName: 'LG French Door Refrigerator',
        category: 'refrigerator',
        emailSubject: 'Your Best Buy Order',
        emailDate: new Date().toISOString(),
        senderAddress: 'orders@bestbuy.com',
        senderDomain: 'bestbuy.com',
        confidence: 0.95,
      },
      scanId,
    );

    expect(created).toBe(true);
    const items = await pool.query('SELECT name FROM items WHERE user_id = $1', [userId]);
    expect(items.rows.length).toBe(1);
    expect(items.rows[0].name).toBe('LG French Door Refrigerator');
  });

  it('enqueueReview: writes a row when sender is not on the trusted allowlist', async () => {
    await enqueueReview(
      userId,
      scanId,
      {
        productName: 'Random TV',
        category: 'tv',
        senderAddress: 'random@spam.com',
        senderDomain: 'spam.com',
        confidence: 0.4,
        emailSubject: 'You won a TV',
      },
      0.4,
    );
    const rows = await pool.query(
      'SELECT sender_domain, state FROM email_scanner_review_queue WHERE user_id = $1',
      [userId],
    );
    expect(rows.rows.length).toBe(1);
    expect(rows.rows[0].sender_domain).toBe('spam.com');
    expect(rows.rows[0].state).toBe('pending');
  });

  it('approveReview promotes the queued row to an items row and marks applied_item_id', async () => {
    const reviewInsert = await pool.query(
      `INSERT INTO email_scanner_review_queue
        (user_id, email_scan_id, sender_address, sender_domain, subject,
         suggested_item, confidence_score, state)
       VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7, 'pending')
       RETURNING id`,
      [
        userId,
        scanId,
        'orders@walmart.com',
        'walmart.com',
        'Walmart order',
        JSON.stringify({
          productName: 'Maytag Dishwasher',
          category: 'dishwasher',
          emailSubject: 'Walmart order',
          emailDate: new Date().toISOString(),
          senderAddress: 'orders@walmart.com',
          senderDomain: 'walmart.com',
          confidence: 0.7,
        }),
        '0.70',
      ],
    );
    const reviewId = reviewInsert.rows[0].id;

    const result = await RealService.approveReview(userId, reviewId);
    expect(result).toHaveProperty('item_id');

    const after = await pool.query(
      'SELECT state, applied_item_id FROM email_scanner_review_queue WHERE id = $1',
      [reviewId],
    );
    expect(after.rows[0].state).toBe('approved');
    expect(after.rows[0].applied_item_id).toBe(result.item_id);
  });

  it('rejectReview marks the row rejected with a reason', async () => {
    const insert = await pool.query(
      `INSERT INTO email_scanner_review_queue
        (user_id, email_scan_id, sender_address, sender_domain, subject,
         suggested_item, confidence_score, state)
       VALUES ($1, $2, 'a@b.com', 'b.com', 'sub', '{"productName":"x"}'::jsonb, 0.1, 'pending')
       RETURNING id`,
      [userId, scanId],
    );
    await RealService.rejectReview(userId, insert.rows[0].id, 'spam');
    const after = await pool.query(
      'SELECT state, rejection_reason FROM email_scanner_review_queue WHERE id = $1',
      [insert.rows[0].id],
    );
    expect(after.rows[0].state).toBe('rejected');
    expect(after.rows[0].rejection_reason).toBe('spam');
  });

  it('performScan: low-confidence trusted sender goes to review, not items', async () => {
    // Stub scanGmail to return one trusted-domain receipt with low confidence.
    const restoreScan = (RealService as any).scanGmail;
    (RealService as any).scanGmail = jest.fn().mockResolvedValue([
      {
        productName: 'Samsung 55" TV',
        category: 'tv',
        emailSubject: 'Best Buy order',
        emailDate: new Date().toISOString(),
        senderAddress: 'orders@bestbuy.com',
        senderDomain: 'bestbuy.com',
        confidence: 0.4,
      },
    ]);

    try {
      await performScan(scanId, userId, 'gmail', 'unused', {});
    } finally {
      (RealService as any).scanGmail = restoreScan;
    }

    const items = await pool.query('SELECT id FROM items WHERE user_id = $1', [userId]);
    expect(items.rows.length).toBe(0);

    const queue = await pool.query(
      'SELECT id FROM email_scanner_review_queue WHERE user_id = $1 AND state = $2',
      [userId, 'pending'],
    );
    expect(queue.rows.length).toBe(1);
  });

  it('performScan: high-confidence trusted sender auto-creates the item', async () => {
    const restoreScan = (RealService as any).scanGmail;
    (RealService as any).scanGmail = jest.fn().mockResolvedValue([
      {
        productName: 'GE Profile Microwave',
        category: 'microwave',
        emailSubject: 'Home Depot Order',
        emailDate: new Date().toISOString(),
        senderAddress: 'orders@homedepot.com',
        senderDomain: 'homedepot.com',
        confidence: 0.97,
        // S-ME-07: trusted-domain + high confidence is necessary but not
        // sufficient for auto-import — DKIM must pass too.
        dkimPassed: true,
      },
    ]);

    try {
      await performScan(scanId, userId, 'gmail', 'unused', {});
    } finally {
      (RealService as any).scanGmail = restoreScan;
    }

    const items = await pool.query('SELECT name FROM items WHERE user_id = $1', [userId]);
    expect(items.rows.length).toBe(1);
    expect(items.rows[0].name).toBe('GE Profile Microwave');

    const queue = await pool.query(
      'SELECT COUNT(*)::int AS n FROM email_scanner_review_queue WHERE user_id = $1',
      [userId],
    );
    expect(queue.rows[0].n).toBe(0);
  });

  it('performScan: untrusted sender always goes to review even with high confidence', async () => {
    const restoreScan = (RealService as any).scanGmail;
    (RealService as any).scanGmail = jest.fn().mockResolvedValue([
      {
        productName: 'Mystery 4K TV',
        category: 'tv',
        emailSubject: 'Your order',
        emailDate: new Date().toISOString(),
        senderAddress: 'orders@notatrustedbrand.example',
        senderDomain: 'notatrustedbrand.example',
        confidence: 0.99,
      },
    ]);

    try {
      await performScan(scanId, userId, 'gmail', 'unused', {});
    } finally {
      (RealService as any).scanGmail = restoreScan;
    }

    const items = await pool.query('SELECT id FROM items WHERE user_id = $1', [userId]);
    expect(items.rows.length).toBe(0);

    const queue = await pool.query(
      'SELECT sender_domain FROM email_scanner_review_queue WHERE user_id = $1 AND state = $2',
      [userId, 'pending'],
    );
    expect(queue.rows.length).toBe(1);
    expect(queue.rows[0].sender_domain).toBe('notatrustedbrand.example');
  });

  it('revokeIntegration soft-deletes the user_oauth_integrations row and clears cached access token', async () => {
    const enc = encryptToken('refresh-token-abc');
    const accessEnc = encryptToken('access-token-xyz');
    await pool.query(
      `INSERT INTO user_oauth_integrations (
         user_id, provider, provider_email,
         refresh_token_ciphertext, refresh_token_iv, refresh_token_tag,
         access_token_ciphertext, access_token_iv, access_token_tag,
         access_token_expires_at, granted_scope
       ) VALUES ($1,'gmail','user@gmail.com',$2,$3,$4,$5,$6,$7,NOW() + INTERVAL '30 minutes',$8)`,
      [
        userId,
        enc.ciphertext,
        enc.iv,
        enc.tag,
        accessEnc.ciphertext,
        accessEnc.iv,
        accessEnc.tag,
        'https://www.googleapis.com/auth/gmail.readonly',
      ],
    );

    await RealService.revokeIntegration(userId);

    const after = await pool.query(
      `SELECT revoked_at, access_token_ciphertext
         FROM user_oauth_integrations WHERE user_id = $1`,
      [userId],
    );
    expect(after.rows[0].revoked_at).not.toBeNull();
    expect(after.rows[0].access_token_ciphertext).toBeNull();
  });
});

describe('OAuth token encryption round-trip', () => {
  it('encryptToken + decryptToken returns the original plaintext', () => {
    const plain = 'super-secret-refresh-token-1234567890';
    const enc = encryptToken(plain);
    expect(enc.ciphertext.length).toBeGreaterThan(0);
    // Base64 of 12-byte IV is 16 chars (no padding). The schema's CHAR(24)
    // column right-pads with spaces on store; decryptToken trims before
    // decode so the round-trip is lossless either way.
    expect(enc.iv.length).toBe(16);
    expect(enc.tag.length).toBe(24);
    expect(decryptToken(enc)).toBe(plain);
  });

  it('different inputs produce different ciphertexts (IV randomness)', () => {
    const a = encryptToken('foo');
    const b = encryptToken('foo');
    expect(a.iv).not.toBe(b.iv);
    expect(a.ciphertext).not.toBe(b.ciphertext);
  });
});
