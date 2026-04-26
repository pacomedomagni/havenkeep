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

const router = Router();

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
    const { name, email, subject, message, website } = req.body as {
      name: string;
      email: string;
      subject: string;
      message: string;
      // Honeypot — see contact.validator.ts.
      website?: string;
    };

    // Honeypot trip: silently 200 so a probing bot can't tell whether the
    // submission was rejected. We log so abuse triage can grep for it.
    if (website && website.trim().length > 0) {
      logger.warn(
        { ip: req.socket.remoteAddress, email },
        'Contact form honeypot tripped — silently dropping submission',
      );
      return sendMessage(
        res,
        'Message sent successfully. We will get back to you within 24 hours.',
      );
    }

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
