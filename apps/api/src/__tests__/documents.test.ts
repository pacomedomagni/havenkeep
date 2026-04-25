import request from 'supertest';
import { pool } from '../db';
import { cleanDatabase } from './setup';
import { getTestApp, createTestUser, createTestHome, createTestItem } from './helpers';

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

// Mock MinIO so file-storage operations do not require a live MinIO instance
jest.mock('../config/minio', () => ({
  minioClient: {
    putObject: jest.fn().mockResolvedValue(undefined),
    removeObject: jest.fn().mockResolvedValue(undefined),
  },
  BUCKET_NAME: 'test-bucket',
  generateObjectKey: jest.fn(
    (userId: string, itemId: string, filename: string) =>
      `documents/${userId}/${itemId}/${filename}`
  ),
  generateAvatarKey: jest.fn(
    (userId: string, ext: string) => `avatars/${userId}/test.${ext}`,
  ),
  generateItemImageKey: jest.fn(
    (userId: string, itemId: string, ext: string) =>
      `item-images/${userId}/${itemId}/test.${ext}`,
  ),
  getPublicUrl: jest.fn(
    (key: string) => `http://localhost:9000/test-bucket/${key}`
  ),
}));

// Mock sharp — image processing is unavailable without real binary files in tests.
// Phase 6 added module-level `sharp.cache(false)` + `sharp.concurrency(1)` calls
// that the bare jest.fn() doesn't expose, so we wire those as no-ops too.
jest.mock('sharp', () => {
  const chain = {
    resize: jest.fn().mockReturnThis(),
    webp: jest.fn().mockReturnThis(),
    toBuffer: jest.fn().mockResolvedValue(Buffer.from('fake-image-data')),
    cover: jest.fn().mockReturnThis(),
    fit: jest.fn().mockReturnThis(),
  };
  const sharpMock: any = jest.fn(() => chain);
  sharpMock.cache = jest.fn();
  sharpMock.concurrency = jest.fn();
  return sharpMock;
});

// ------------------------------------------------------------------
// Helper: insert a document row directly into the DB (bypasses upload)
// ------------------------------------------------------------------
async function insertDocument(
  userId: string,
  itemId: string,
  overrides: Record<string, any> = {}
) {
  const result = await pool.query(
    `INSERT INTO documents (user_id, item_id, type, object_key, file_name, file_size, mime_type)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     RETURNING *`,
    [
      userId,
      itemId,
      overrides.type || 'receipt',
      overrides.object_key || `documents/${userId}/${itemId}/test.pdf`,
      overrides.file_name || 'test.pdf',
      overrides.file_size || 1024,
      overrides.mime_type || 'application/pdf',
    ]
  );
  return result.rows[0];
}

describe('Documents Routes', () => {
  let app: ReturnType<typeof getTestApp>;
  let token: string;
  let userId: string;
  let homeId: string;
  let itemId: string;

  let otherToken: string;

  beforeAll(() => {
    app = getTestApp();
  });

  beforeEach(async () => {
    await cleanDatabase();

    const { user, token: t } = await createTestUser();
    userId = user.id;
    token = t;

    const home = await createTestHome(userId);
    homeId = home.id;

    const item = await createTestItem(userId, homeId);
    itemId = item.id;

    const other = await createTestUser();
    otherToken = other.token;
  });

  describe('GET /api/v1/documents', () => {
    it('should return 401 when no auth token is provided', async () => {
      const res = await request(app).get('/api/v1/documents');
      expect(res.status).toBe(401);
    });

    it('should return an empty array when the user has no documents', async () => {
      const res = await request(app)
        .get('/api/v1/documents')
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(Array.isArray(res.body.data)).toBe(true);
      expect(res.body.data).toHaveLength(0);
    });

    it('should return documents filtered by item_id', async () => {
      // Insert two documents for the same item and one for a different item
      const otherItem = await createTestItem(userId, homeId, { name: 'Other Item' });

      await insertDocument(userId, itemId);
      await insertDocument(userId, itemId);
      await insertDocument(userId, otherItem.id);

      const res = await request(app)
        .get(`/api/v1/documents?item_id=${itemId}`)
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toHaveLength(2);
      expect(res.body.data.every((d: any) => d.item_id === itemId)).toBe(true);
    });
  });

  describe('GET /api/v1/documents/:id', () => {
    it('should return a single document by ID', async () => {
      const doc = await insertDocument(userId, itemId);

      const res = await request(app)
        .get(`/api/v1/documents/${doc.id}`)
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.id).toBe(doc.id);
    });

    it('should return 404 when accessing another user\'s document', async () => {
      const doc = await insertDocument(userId, itemId);

      const res = await request(app)
        .get(`/api/v1/documents/${doc.id}`)
        .set('Authorization', `Bearer ${otherToken}`);

      expect(res.status).toBe(404);
    });
  });

  describe('DELETE /api/v1/documents/:id', () => {
    it('should delete a document owned by the authenticated user', async () => {
      const doc = await insertDocument(userId, itemId);

      const res = await request(app)
        .delete(`/api/v1/documents/${doc.id}`)
        .set('Authorization', `Bearer ${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);

      // Confirm the record is gone
      const check = await pool.query('SELECT id FROM documents WHERE id = $1', [doc.id]);
      expect(check.rows).toHaveLength(0);
    });

    it('should return 404 when deleting another user\'s document', async () => {
      const doc = await insertDocument(userId, itemId);

      const res = await request(app)
        .delete(`/api/v1/documents/${doc.id}`)
        .set('Authorization', `Bearer ${otherToken}`);

      expect(res.status).toBe(404);
    });
  });

  describe('POST /api/v1/documents/upload', () => {
    it('should return 401 when no auth token is provided', async () => {
      const res = await request(app)
        .post('/api/v1/documents/upload')
        .field('itemId', itemId);

      expect(res.status).toBe(401);
    });

    it('should return 400 when no files are attached', async () => {
      // Send a valid multipart request with an item_id but no file
      const res = await request(app)
        .post('/api/v1/documents/upload')
        .set('Authorization', `Bearer ${token}`)
        .field('itemId', itemId);

      expect(res.status).toBe(400);
    });

    // Audit Ch12-T010: bytes are PDF, MIME claimed as image/png — must 400.
    it('should reject magic-byte mismatch (PDF posted as image/png)', async () => {
      const pdfBytes = Buffer.from('%PDF-1.4\n%fake-bytes', 'utf8');
      const res = await request(app)
        .post('/api/v1/documents/upload')
        .set('Authorization', `Bearer ${token}`)
        .field('itemId', itemId)
        .attach('files', pdfBytes, { filename: 'fake.png', contentType: 'image/png' });

      expect(res.status).toBe(400);
    });

    // Audit Ch12-T011: oversized + bad MIME — multer fileFilter rejects.
    it('should reject oversized file with disallowed MIME', async () => {
      const big = Buffer.alloc(11 * 1024 * 1024, 0); // 11MB
      const res = await request(app)
        .post('/api/v1/documents/upload')
        .set('Authorization', `Bearer ${token}`)
        .field('itemId', itemId)
        .attach('files', big, { filename: 'big.exe', contentType: 'application/octet-stream' });

      // 400 (fileFilter) or 413 (size) or 500 (multer wrap). Either way: not 2xx.
      expect(res.status).toBeGreaterThanOrEqual(400);
    });

    // Audit Ch12-T053: cross-user upload to A's itemId must 404.
    it('should not allow user B to upload to user A item', async () => {
      const png = Buffer.from([
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
        0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
      ]);
      const res = await request(app)
        .post('/api/v1/documents/upload')
        .set('Authorization', `Bearer ${otherToken}`)
        .field('itemId', itemId)
        .attach('files', png, { filename: 'p.png', contentType: 'image/png' });

      expect(res.status).toBe(404);
    });
  });
});
