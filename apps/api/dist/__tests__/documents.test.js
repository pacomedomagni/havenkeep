"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const supertest_1 = __importDefault(require("supertest"));
const db_1 = require("../db");
const setup_1 = require("./setup");
const helpers_1 = require("./helpers");
jest.mock('../middleware/rateLimiter', () => {
    const pass = (_req, _res, next) => next();
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
// Mock MinIO so file-storage operations do not require a live MinIO instance
jest.mock('../config/minio', () => ({
    minioClient: {
        putObject: jest.fn().mockResolvedValue(undefined),
        removeObject: jest.fn().mockResolvedValue(undefined),
    },
    BUCKET_NAME: 'test-bucket',
    generateObjectKey: jest.fn((userId, itemId, filename) => `documents/${userId}/${itemId}/${filename}`),
    getPublicUrl: jest.fn((key) => `http://localhost:9000/test-bucket/${key}`),
}));
// Mock sharp — image processing is unavailable without real binary files in tests
jest.mock('sharp', () => {
    const chain = {
        resize: jest.fn().mockReturnThis(),
        webp: jest.fn().mockReturnThis(),
        toBuffer: jest.fn().mockResolvedValue(Buffer.from('fake-image-data')),
        cover: jest.fn().mockReturnThis(),
        fit: jest.fn().mockReturnThis(),
    };
    const sharpMock = jest.fn(() => chain);
    return sharpMock;
});
// ------------------------------------------------------------------
// Helper: insert a document row directly into the DB (bypasses upload)
// ------------------------------------------------------------------
async function insertDocument(userId, itemId, overrides = {}) {
    const result = await db_1.pool.query(`INSERT INTO documents (user_id, item_id, type, file_url, file_name, file_size, mime_type)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     RETURNING *`, [
        userId,
        itemId,
        overrides.type || 'receipt',
        overrides.file_url || `http://localhost:9000/test-bucket/documents/${userId}/${itemId}/test.pdf`,
        overrides.file_name || 'test.pdf',
        overrides.file_size || 1024,
        overrides.mime_type || 'application/pdf',
    ]);
    return result.rows[0];
}
describe('Documents Routes', () => {
    let app;
    let token;
    let userId;
    let homeId;
    let itemId;
    let otherToken;
    beforeAll(() => {
        app = (0, helpers_1.getTestApp)();
    });
    beforeEach(async () => {
        await (0, setup_1.cleanDatabase)();
        const { user, token: t } = await (0, helpers_1.createTestUser)();
        userId = user.id;
        token = t;
        const home = await (0, helpers_1.createTestHome)(userId);
        homeId = home.id;
        const item = await (0, helpers_1.createTestItem)(userId, homeId);
        itemId = item.id;
        const other = await (0, helpers_1.createTestUser)();
        otherToken = other.token;
    });
    describe('GET /api/v1/documents', () => {
        it('should return 401 when no auth token is provided', async () => {
            const res = await (0, supertest_1.default)(app).get('/api/v1/documents');
            expect(res.status).toBe(401);
        });
        it('should return an empty array when the user has no documents', async () => {
            const res = await (0, supertest_1.default)(app)
                .get('/api/v1/documents')
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(Array.isArray(res.body.data)).toBe(true);
            expect(res.body.data).toHaveLength(0);
        });
        it('should return documents filtered by item_id', async () => {
            // Insert two documents for the same item and one for a different item
            const otherItem = await (0, helpers_1.createTestItem)(userId, homeId, { name: 'Other Item' });
            await insertDocument(userId, itemId);
            await insertDocument(userId, itemId);
            await insertDocument(userId, otherItem.id);
            const res = await (0, supertest_1.default)(app)
                .get(`/api/v1/documents?item_id=${itemId}`)
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data).toHaveLength(2);
            expect(res.body.data.every((d) => d.item_id === itemId)).toBe(true);
        });
    });
    describe('GET /api/v1/documents/:id', () => {
        it('should return a single document by ID', async () => {
            const doc = await insertDocument(userId, itemId);
            const res = await (0, supertest_1.default)(app)
                .get(`/api/v1/documents/${doc.id}`)
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.id).toBe(doc.id);
        });
        it('should return 404 when accessing another user\'s document', async () => {
            const doc = await insertDocument(userId, itemId);
            const res = await (0, supertest_1.default)(app)
                .get(`/api/v1/documents/${doc.id}`)
                .set('Authorization', `Bearer ${otherToken}`);
            expect(res.status).toBe(404);
        });
    });
    describe('DELETE /api/v1/documents/:id', () => {
        it('should delete a document owned by the authenticated user', async () => {
            const doc = await insertDocument(userId, itemId);
            const res = await (0, supertest_1.default)(app)
                .delete(`/api/v1/documents/${doc.id}`)
                .set('Authorization', `Bearer ${token}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            // Confirm the record is gone
            const check = await db_1.pool.query('SELECT id FROM documents WHERE id = $1', [doc.id]);
            expect(check.rows).toHaveLength(0);
        });
        it('should return 404 when deleting another user\'s document', async () => {
            const doc = await insertDocument(userId, itemId);
            const res = await (0, supertest_1.default)(app)
                .delete(`/api/v1/documents/${doc.id}`)
                .set('Authorization', `Bearer ${otherToken}`);
            expect(res.status).toBe(404);
        });
    });
    describe('POST /api/v1/documents/upload', () => {
        it('should return 401 when no auth token is provided', async () => {
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/documents/upload')
                .field('itemId', itemId);
            expect(res.status).toBe(401);
        });
        it('should return 400 when no files are attached', async () => {
            // Send a valid multipart request with an item_id but no file
            const res = await (0, supertest_1.default)(app)
                .post('/api/v1/documents/upload')
                .set('Authorization', `Bearer ${token}`)
                .field('itemId', itemId);
            expect(res.status).toBe(400);
        });
    });
});
//# sourceMappingURL=documents.test.js.map