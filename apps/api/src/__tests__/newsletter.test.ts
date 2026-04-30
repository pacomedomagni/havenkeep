import request from 'supertest';
import { cleanDatabase } from './setup';
import { getTestApp } from './helpers';

jest.mock('../middleware/rateLimiter', () => require('./test-rate-limiter-mock'));

describe('Newsletter Routes', () => {
  let app: ReturnType<typeof getTestApp>;

  beforeAll(() => {
    app = getTestApp();
  });

  beforeEach(async () => {
    await cleanDatabase();
  });

  describe('POST /api/v1/newsletter/subscribe', () => {
    it('should subscribe a valid email successfully', async () => {
      const res = await request(app)
        .post('/api/v1/newsletter/subscribe')
        .send({ email: 'newsletter@example.com' });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      // Double-opt-in: response no longer says "subscribed" until the user
      // confirms via the link we email them.
      expect(res.body.message).toMatch(/check your inbox/i);
    });

    it('should return 400 when email is missing', async () => {
      const res = await request(app)
        .post('/api/v1/newsletter/subscribe')
        .send({});

      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
    });

    it('should return 400 for an invalid email format', async () => {
      const res = await request(app)
        .post('/api/v1/newsletter/subscribe')
        .send({ email: 'not-an-email' });

      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
    });

    it('should succeed (upsert) when subscribing with a duplicate email', async () => {
      const email = 'duplicate@example.com';

      // First subscription
      const first = await request(app)
        .post('/api/v1/newsletter/subscribe')
        .send({ email });

      expect(first.status).toBe(200);

      // Duplicate subscription — should still succeed
      const second = await request(app)
        .post('/api/v1/newsletter/subscribe')
        .send({ email });

      expect(second.status).toBe(200);
      expect(second.body.success).toBe(true);
    });

    it('should include a success message in the response body', async () => {
      const res = await request(app)
        .post('/api/v1/newsletter/subscribe')
        .send({ email: 'msg-check@example.com' });

      expect(res.status).toBe(200);
      expect(typeof res.body.message).toBe('string');
      expect(res.body.message.length).toBeGreaterThan(0);
    });
  });
});
