import request from 'supertest';
import { cleanDatabase } from './setup';
import { getTestApp } from './helpers';

// Audit Ch12-T028 — exercises the REAL contact rate limiter so we can prove
// 429 surfaces after burst. Globally mocking the rate limiter (as every
// other test file does) hid this regression.
//
// This file deliberately does NOT mock `../middleware/rateLimiter`.

describe('Contact spam protection (audit Ch12-T028)', () => {
  let app: ReturnType<typeof getTestApp>;

  beforeEach(async () => {
    app = getTestApp();
    await cleanDatabase();
  });

  it('rate-limits the contact endpoint to fewer than 11 requests in a window', async () => {
    const sendOne = (i: number) =>
      request(app)
        .post('/api/v1/contact')
        .set('X-Forwarded-For', '198.51.100.42')
        .send({
          name: `Spam Bot ${i}`,
          email: `spam${i}@test.com`,
          subject: 'Other',
          message: `This is a spam attempt number ${i} with enough characters.`,
        });

    let limited = false;
    for (let i = 0; i < 11; i++) {
      // eslint-disable-next-line no-await-in-loop
      const res = await sendOne(i);
      if (res.status === 429) {
        limited = true;
        break;
      }
    }
    expect(limited).toBe(true);
  });
});
