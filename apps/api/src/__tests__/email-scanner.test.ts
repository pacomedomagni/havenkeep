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

// ------------------------------------------------------------------
// Mock EmailScannerService to avoid real Gmail/Outlook/OpenAI calls
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
  },
}));

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

    // Use a fixed UUID as the scan ID returned by the mock
    scanId = mockScan.id;
  });

  describe('POST /api/v1/email-scanner/scan', () => {
    it('should return 401 when no auth token is provided', async () => {
      const res = await request(app)
        .post('/api/v1/email-scanner/scan')
        .send({ provider: 'gmail', access_token: 'tok' });

      expect(res.status).toBe(401);
    });

    it('should return 403 for a non-premium user', async () => {
      const res = await request(app)
        .post('/api/v1/email-scanner/scan')
        .set('Authorization', `Bearer ${freeToken}`)
        .send({ provider: 'gmail', access_token: 'tok' });

      expect(res.status).toBe(403);
    });

    it('should return 400 when required fields are missing', async () => {
      const res = await request(app)
        .post('/api/v1/email-scanner/scan')
        .set('Authorization', `Bearer ${premiumToken}`)
        .send({}); // missing provider and access_token

      expect(res.status).toBe(400);
    });

    it('should initiate a scan and return 202 for a premium user', async () => {
      const res = await request(app)
        .post('/api/v1/email-scanner/scan')
        .set('Authorization', `Bearer ${premiumToken}`)
        .send({ provider: 'gmail', access_token: 'valid-token' });

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
});
