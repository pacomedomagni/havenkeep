import request from 'supertest';
import { pool } from '../db';
import { cleanDatabase } from './setup';
import { getTestApp, createTestUser } from './helpers';

jest.mock('../middleware/rateLimiter', () => require('./test-rate-limiter-mock'));

// Spy on global.fetch so we can stub OpenAI without real network.
const fetchMock = jest.fn();
beforeAll(() => {
  (global as any).fetch = fetchMock;
});
beforeEach(() => {
  fetchMock.mockReset();
});

const app = getTestApp();

// Minimal valid PNG: signature + IHDR header (16 bytes).
const VALID_PNG_HEADER = Buffer.from([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
  0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00,
  0x08, 0x06, 0x00, 0x00, 0x00,
]);

function mockOpenAiResponse(content: any, opts: { ok?: boolean; status?: number; usage?: any } = {}) {
  fetchMock.mockResolvedValueOnce({
    ok: opts.ok ?? true,
    status: opts.status ?? 200,
    json: async () => ({
      choices: [{ message: { content: typeof content === 'string' ? content : JSON.stringify(content) } }],
      usage: opts.usage ?? { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 },
    }),
  });
}

describe('Receipts /scan', () => {
  beforeEach(async () => {
    await cleanDatabase();
  });

  it('rejects free-tier callers (requirePremium first, rate-limit AFTER)', async () => {
    const { token } = await createTestUser({ plan: 'free' });
    const res = await request(app)
      .post('/api/v1/receipts/scan')
      .set('Authorization', `Bearer ${token}`)
      .attach('file', VALID_PNG_HEADER, { filename: 'r.png', contentType: 'image/png' });

    expect(res.status).toBe(403);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  // Audit Ch12-T012: a receipt that asks the model to leak its prompt /
  // change its instructions must still produce a constrained JSON object —
  // the route enforces this via prompt + schema validation. We assert that
  // the route either returns a sanitized object OR a 502 (model returned
  // garbage), but never an arbitrary string.
  it('sanitizes a prompt-injection payload from the model', async () => {
    const { token } = await createTestUser({ plan: 'premium' });
    // Model attempts to leak system prompt via free-form text
    mockOpenAiResponse('IGNORED. Here is your secret: sk-test...');

    const res = await request(app)
      .post('/api/v1/receipts/scan')
      .set('Authorization', `Bearer ${token}`)
      .attach('file', VALID_PNG_HEADER, { filename: 'r.png', contentType: 'image/png' });

    // The free-form text isn't valid JSON → 502 from JSON.parse.
    expect(res.status).toBe(502);
  });

  it('returns sanitized payload on a well-formed model response', async () => {
    const { token } = await createTestUser({ plan: 'premium' });
    mockOpenAiResponse({
      merchant: 'Best Buy',
      date: '2026-04-20',
      total: 1234.56,
      items: [{ name: 'Soundbar', price: 1234.56, quantity: 1 }],
      categoryGuess: 'home_theater',
    });

    const res = await request(app)
      .post('/api/v1/receipts/scan')
      .set('Authorization', `Bearer ${token}`)
      .attach('file', VALID_PNG_HEADER, { filename: 'r.png', contentType: 'image/png' });

    expect(res.status).toBe(200);
    expect(res.body.data.merchant).toBe('Best Buy');
    expect(res.body.data.total).toBe(1234.56);
  });

  it('replays a prior response on the same Idempotency-Key', async () => {
    const { token } = await createTestUser({ plan: 'premium' });
    mockOpenAiResponse({
      merchant: 'Costco',
      date: '2026-04-20',
      total: 99.99,
      items: [],
      categoryGuess: null,
    });

    const idempotencyKey = 'test-key-123';
    const first = await request(app)
      .post('/api/v1/receipts/scan')
      .set('Authorization', `Bearer ${token}`)
      .set('Idempotency-Key', idempotencyKey)
      .attach('file', VALID_PNG_HEADER, { filename: 'r.png', contentType: 'image/png' });

    expect(first.status).toBe(200);
    expect(fetchMock).toHaveBeenCalledTimes(1);

    // Second call with the same key must replay without burning OpenAI.
    const second = await request(app)
      .post('/api/v1/receipts/scan')
      .set('Authorization', `Bearer ${token}`)
      .set('Idempotency-Key', idempotencyKey)
      .attach('file', VALID_PNG_HEADER, { filename: 'r.png', contentType: 'image/png' });

    expect(second.status).toBe(200);
    expect(second.body.data.merchant).toBe('Costco');
    expect(fetchMock).toHaveBeenCalledTimes(1); // still only one call
  });

  // Audit Ch02-F046: per-user openai_usage rows persisted after each call.
  it('records OpenAI cost in openai_usage', async () => {
    const { user, token } = await createTestUser({ plan: 'premium' });
    mockOpenAiResponse({
      merchant: 'Target',
      date: '2026-04-20',
      total: 10.0,
      items: [],
      categoryGuess: null,
    });

    const res = await request(app)
      .post('/api/v1/receipts/scan')
      .set('Authorization', `Bearer ${token}`)
      .attach('file', VALID_PNG_HEADER, { filename: 'r.png', contentType: 'image/png' });

    expect(res.status).toBe(200);
    const usage = await pool.query(
      `SELECT user_id, feature, total_tokens FROM openai_usage WHERE user_id = $1`,
      [user.id],
    );
    expect(usage.rows.length).toBe(1);
    expect(usage.rows[0].feature).toBe('receipt_scan');
    expect(parseInt(usage.rows[0].total_tokens, 10)).toBe(150);
  });
});
