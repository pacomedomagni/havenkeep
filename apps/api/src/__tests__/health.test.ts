import request from 'supertest';
import { cleanDatabase } from './setup';
import { getTestApp } from './helpers';

const app = getTestApp();

describe('Health endpoint', () => {
  beforeEach(async () => {
    await cleanDatabase();
  });

  describe('GET /health', () => {
    it('should return 200 with status ok', async () => {
      const res = await request(app).get('/health');

      expect(res.status).toBe(200);
      expect(res.body.status).toBe('ok');
      expect(res.body).toHaveProperty('timestamp');
      expect(res.body).toHaveProperty('uptime');
      expect(res.body).toHaveProperty('environment');
    });
  });
});
