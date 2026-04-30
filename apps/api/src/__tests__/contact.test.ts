import request from 'supertest';
import { cleanDatabase } from './setup';
import { getTestApp } from './helpers';

jest.mock('../middleware/rateLimiter', () => require('./test-rate-limiter-mock'));

// Mock SendGrid-backed EmailService so contact tests do not hit the real API
jest.mock('../services/email.service', () => ({
  EmailService: {
    sendContactNotificationEmail: jest.fn().mockResolvedValue(undefined),
    sendPartnerWelcomeEmail: jest.fn().mockResolvedValue(undefined),
    sendGiftEmail: jest.fn().mockResolvedValue(undefined),
    sendPasswordResetEmail: jest.fn().mockResolvedValue(undefined),
    sendEmailVerificationEmail: jest.fn().mockResolvedValue(undefined),
  },
}));

describe('Contact Routes', () => {
  let app: ReturnType<typeof getTestApp>;

  const validPayload = {
    name: 'Jane Smith',
    email: 'jane@example.com',
    subject: 'Technical Support',
    message: 'This is a valid test message with enough characters.',
  };

  beforeAll(() => {
    app = getTestApp();
  });

  beforeEach(async () => {
    await cleanDatabase();
  });

  describe('POST /api/v1/contact', () => {
    it('should submit a contact form successfully', async () => {
      const res = await request(app)
        .post('/api/v1/contact')
        .send(validPayload);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.message).toMatch(/message sent successfully/i);
    });

    it('should return 400 when required fields are missing', async () => {
      const res = await request(app)
        .post('/api/v1/contact')
        .send({ name: 'Jane Smith' }); // missing email, subject, message

      expect(res.status).toBe(400);
      expect(res.body.error).toBeDefined();
    });

    it('should return 400 for an invalid subject value', async () => {
      const res = await request(app)
        .post('/api/v1/contact')
        .send({ ...validPayload, subject: 'Nonsense Subject' });

      expect(res.status).toBe(400);
      expect(res.body.error).toBeDefined();
    });

    it('should return 400 when the message is too short (under 10 chars)', async () => {
      const res = await request(app)
        .post('/api/v1/contact')
        .send({ ...validPayload, message: 'Short' });

      expect(res.status).toBe(400);
      expect(res.body.error).toBeDefined();
    });

    it('should return 400 for an invalid email format', async () => {
      const res = await request(app)
        .post('/api/v1/contact')
        .send({ ...validPayload, email: 'not-a-valid-email' });

      expect(res.status).toBe(400);
      expect(res.body.error).toBeDefined();
    });

    it('should return 200 even when the email service throws an error', async () => {
      // Override the mock to simulate a SendGrid failure for this test
      const { EmailService } = require('../services/email.service');
      (EmailService.sendContactNotificationEmail as jest.Mock).mockRejectedValueOnce(
        new Error('SendGrid unavailable')
      );

      const res = await request(app)
        .post('/api/v1/contact')
        .send(validPayload);

      // Email failures are swallowed; the submission should still succeed
      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
    });
  });
});
