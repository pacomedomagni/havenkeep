import { Router } from 'express';
import { pool } from '../db';
import { logger } from '../utils/logger';
import { validate } from '../middleware/validate';
import { asyncHandler } from '../utils/async-handler';
import { EmailService } from '../services/email.service';
import { contactRateLimiter, readRateLimiter } from '../middleware/rateLimiter';
import { sendSuccess, sendMessage } from '../utils/response';
import { submitContactSchema } from '../validators/contact.validator';
import { authenticate, requireAdmin } from '../middleware/auth';
import { config } from '../config';
import { AppError } from '../utils/errors';

const router = Router();

/**
 * F114: server-side Turnstile verification. Skipped (with a warning) when
 * the secret key isn't configured — keeps local dev unblocked but a prod
 * deploy that forgets to set TURNSTILE_SECRET_KEY surfaces in the logs on
 * every submission.
 */
async function verifyTurnstile(token: string | undefined, remoteIp: string): Promise<void> {
  if (!config.turnstile.secretKey) {
    logger.warn('TURNSTILE_SECRET_KEY not configured — contact form CAPTCHA disabled');
    return;
  }
  if (!token) {
    throw new AppError('Captcha token missing', 400);
  }
  const params = new URLSearchParams({
    secret: config.turnstile.secretKey,
    response: token,
    remoteip: remoteIp,
  });
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5000);
  try {
    const resp = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params.toString(),
      signal: controller.signal,
    });
    if (!resp.ok) {
      throw new AppError('Captcha verification service unavailable', 503);
    }
    const json = (await resp.json()) as { success?: boolean; 'error-codes'?: string[] };
    if (!json.success) {
      logger.warn({ codes: json['error-codes'] }, 'Turnstile verification failed');
      throw new AppError('Captcha verification failed', 400);
    }
  } catch (err: any) {
    if (err instanceof AppError) throw err;
    if (err.name === 'AbortError') {
      throw new AppError('Captcha verification timed out', 504);
    }
    logger.error({ err }, 'Turnstile verification error');
    throw new AppError('Captcha verification error', 503);
  } finally {
    clearTimeout(timeout);
  }
}

/**
 * @route   POST /api/v1/contact
 * @desc    Submit a contact form message
 * @access  Public (no authentication required)
 */
router.post(
  '/',
  contactRateLimiter,
  validate(submitContactSchema),
  asyncHandler(async (req, res) => {
    const { name, email, subject, message, turnstileToken } = req.body as {
      name: string; email: string; subject: string; message: string; turnstileToken?: string;
    };

    // F114: verify CAPTCHA before we touch the DB or fan out to SendGrid.
    await verifyTurnstile(turnstileToken, req.socket.remoteAddress || 'unknown');

    // F115: strip CR/LF from `name` so it can't inject extra headers when
    // it's interpolated into the email subject ("Contact Form: <subj> -
    // <name>"). The subject Joi enum already constrains the visible value;
    // this defends the trailing slot.
    const safeName = name.replace(/[\r\n]+/g, ' ').trim();

    // Store the submission in the database
    await pool.query(
      `INSERT INTO contact_submissions (name, email, subject, message, ip_address)
       VALUES ($1, $2, $3, $4, $5)`,
      [safeName, email, subject, message, req.socket.remoteAddress || null]
    );

    // Send notification email to support
    try {
      await EmailService.sendContactNotificationEmail({
        name: safeName,
        email,
        subject,
        message,
      });
    } catch (emailError) {
      // Log the email failure but don't fail the request --
      // the submission is already persisted in the database.
      logger.error({ error: emailError, email }, 'Failed to send contact notification email');
    }

    logger.info({ email, subject }, 'Contact form submission received');

    return sendMessage(res, 'Message sent successfully. We will get back to you within 24 hours.');
  })
);

/**
 * @route   GET /api/v1/contact/submissions
 * @desc    F117: admin-only listing of contact form submissions. Paginated
 *          + read-rate-limited; ip_address surfaced for abuse triage.
 * @access  Admin
 */
router.get(
  '/submissions',
  authenticate,
  requireAdmin,
  readRateLimiter,
  asyncHandler(async (req, res) => {
    const page = Math.max(1, parseInt(String(req.query.page ?? '1'), 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(String(req.query.limit ?? '50'), 10) || 50));
    const offset = (page - 1) * limit;

    const [rows, count] = await Promise.all([
      pool.query(
        `SELECT id, name, email, subject, message, ip_address, created_at
           FROM contact_submissions
          ORDER BY created_at DESC
          LIMIT $1 OFFSET $2`,
        [limit, offset],
      ),
      pool.query<{ count: string }>(`SELECT COUNT(*)::text AS count FROM contact_submissions`),
    ]);

    sendSuccess(res, rows.rows, {
      pagination: {
        page,
        limit,
        total: parseInt(count.rows[0].count, 10),
        total_pages: Math.ceil(parseInt(count.rows[0].count, 10) / limit),
      },
    });
  }),
);

export default router;
