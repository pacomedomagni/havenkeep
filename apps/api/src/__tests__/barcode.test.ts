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
// Helpers for building mock fetch responses
// ------------------------------------------------------------------
function makeFetchResponse(status: number, body: unknown): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
    text: async () => JSON.stringify(body),
  } as unknown as Response;
}

const SAMPLE_PRODUCT_RESPONSE = {
  items: [
    {
      title: 'Samsung 65" 4K TV',
      brand: 'Samsung',
      category: 'Electronics',
      description: 'A great 4K television',
      images: ['https://example.com/tv.jpg'],
    },
  ],
};

describe('Barcode Routes', () => {
  let app: ReturnType<typeof getTestApp>;
  let premiumToken: string;
  let freeToken: string;
  let fetchSpy: jest.SpyInstance;

  beforeAll(() => {
    app = getTestApp();
  });

  beforeEach(async () => {
    await cleanDatabase();

    // Create a premium user and a free user for auth checks
    const premiumUser = await createTestUser({ plan: 'premium' });
    premiumToken = premiumUser.token;

    const freeUser = await createTestUser({ plan: 'free' });
    freeToken = freeUser.token;

    // Spy on the global fetch used by the barcode route
    fetchSpy = jest.spyOn(global, 'fetch');
  });

  afterEach(() => {
    fetchSpy.mockRestore();
  });

  describe('POST /api/v1/barcode/lookup', () => {
    it('should return 401 when no auth token is provided', async () => {
      const res = await request(app)
        .post('/api/v1/barcode/lookup')
        .send({ barcode: '012345678905' });

      expect(res.status).toBe(401);
    });

    it('should return 403 for a non-premium (free) user', async () => {
      const res = await request(app)
        .post('/api/v1/barcode/lookup')
        .set('Authorization', `Bearer ${freeToken}`)
        .send({ barcode: '012345678905' });

      expect(res.status).toBe(403);
    });

    it('should return product data on a successful barcode lookup', async () => {
      fetchSpy.mockResolvedValueOnce(makeFetchResponse(200, SAMPLE_PRODUCT_RESPONSE));

      const res = await request(app)
        .post('/api/v1/barcode/lookup')
        .set('Authorization', `Bearer ${premiumToken}`)
        .send({ barcode: '012345678905' });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toMatchObject({
        barcode: '012345678905',
        brand: 'Samsung',
        product_name: 'Samsung 65" 4K TV',
      });
    });

    it('should return null product fields when the barcode is not found (API 404)', async () => {
      fetchSpy.mockResolvedValueOnce(makeFetchResponse(404, { message: 'Not found' }));

      const res = await request(app)
        .post('/api/v1/barcode/lookup')
        .set('Authorization', `Bearer ${premiumToken}`)
        .send({ barcode: '012345678905' });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toMatchObject({
        barcode: '012345678905',
        brand: null,
        product_name: null,
      });
    });

    it('should return 400 for an invalid barcode format', async () => {
      const res = await request(app)
        .post('/api/v1/barcode/lookup')
        .set('Authorization', `Bearer ${premiumToken}`)
        .send({ barcode: 'INVALID' });

      expect(res.status).toBe(400);
    });

    it('should serve a cached result on the second lookup without hitting fetch again', async () => {
      // First call — prime the Redis cache
      fetchSpy.mockResolvedValueOnce(makeFetchResponse(200, SAMPLE_PRODUCT_RESPONSE));

      await request(app)
        .post('/api/v1/barcode/lookup')
        .set('Authorization', `Bearer ${premiumToken}`)
        .send({ barcode: '012345678905' });

      expect(fetchSpy).toHaveBeenCalledTimes(1);

      // Second call — should hit the Redis cache; fetch must NOT be called again
      const res = await request(app)
        .post('/api/v1/barcode/lookup')
        .set('Authorization', `Bearer ${premiumToken}`)
        .send({ barcode: '012345678905' });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.barcode).toBe('012345678905');
      // fetch was not called a second time because the result was cached
      expect(fetchSpy).toHaveBeenCalledTimes(1);
    });
  });
});
