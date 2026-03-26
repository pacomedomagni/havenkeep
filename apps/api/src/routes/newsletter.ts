import { Router } from 'express';
import { pool } from '../db';
import { logger } from '../utils/logger';
import { asyncHandler } from '../utils/async-handler';
import { newsletterRateLimiter } from '../middleware/rateLimiter';
import { sendMessage } from '../utils/response';

const router = Router();

/**
 * @route   POST /api/v1/newsletter/subscribe
 * @desc    Subscribe an email address to the newsletter
 * @access  Public (no authentication required)
 */
router.post(
  '/subscribe',
  newsletterRateLimiter,
  asyncHandler(async (req, res) => {
    const { email } = req.body;

    // Basic email validation
    if (!email || typeof email !== 'string') {
      return res.status(400).json({
        success: false,
        error: 'Email address is required',
      });
    }

    const trimmedEmail = email.trim().toLowerCase();
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(trimmedEmail)) {
      return res.status(400).json({
        success: false,
        error: 'Please provide a valid email address',
      });
    }

    try {
      // Upsert: if the email already exists, update subscribed_at and clear
      // any previous unsubscribed_at (re-subscribe). If it's new, insert it.
      await pool.query(
        `INSERT INTO newsletter_subscribers (email, ip_address, source)
         VALUES ($1, $2, $3)
         ON CONFLICT (email)
         DO UPDATE SET
           subscribed_at = NOW(),
           unsubscribed_at = NULL,
           ip_address = EXCLUDED.ip_address`,
        [trimmedEmail, req.ip || null, 'blog']
      );

      logger.info({ email: trimmedEmail }, 'Newsletter subscription');

      return sendMessage(res, 'Successfully subscribed to the newsletter');
    } catch (error) {
      logger.error({ error, email: trimmedEmail }, 'Newsletter subscription failed');
      return res.status(500).json({
        success: false,
        error: 'Subscription failed. Please try again later.',
      });
    }
  })
);

/**
 * @route   POST /api/v1/newsletter/unsubscribe
 * @desc    Unsubscribe an email address from the newsletter
 * @access  Public (no authentication required — CAN-SPAM/GDPR one-click unsubscribe)
 */
router.post(
  '/unsubscribe',
  newsletterRateLimiter,
  asyncHandler(async (req, res) => {
    const { email } = req.body;

    if (!email || typeof email !== 'string') {
      return res.status(400).json({
        success: false,
        error: 'Email address is required',
      });
    }

    const trimmedEmail = email.trim().toLowerCase();
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(trimmedEmail)) {
      return res.status(400).json({
        success: false,
        error: 'Please provide a valid email address',
      });
    }

    try {
      await pool.query(
        `UPDATE newsletter_subscribers
         SET unsubscribed_at = NOW()
         WHERE email = $1 AND unsubscribed_at IS NULL`,
        [trimmedEmail]
      );

      logger.info({ email: trimmedEmail }, 'Newsletter unsubscribe');

      // Always return success to prevent email enumeration
      return sendMessage(res, 'Successfully unsubscribed from the newsletter');
    } catch (error) {
      logger.error({ error, email: trimmedEmail }, 'Newsletter unsubscribe failed');
      return res.status(500).json({
        success: false,
        error: 'Unsubscribe failed. Please try again later.',
      });
    }
  })
);

/**
 * @route   GET /api/v1/newsletter/unsubscribe
 * @desc    One-click unsubscribe via email link (RFC 8058 List-Unsubscribe)
 * @access  Public
 */
router.get(
  '/unsubscribe',
  asyncHandler(async (req, res) => {
    const { email } = req.query;

    if (!email || typeof email !== 'string') {
      return res.status(400).send('Invalid unsubscribe link');
    }

    const trimmedEmail = email.trim().toLowerCase();

    await pool.query(
      `UPDATE newsletter_subscribers
       SET unsubscribed_at = NOW()
       WHERE email = $1 AND unsubscribed_at IS NULL`,
      [trimmedEmail]
    );

    logger.info({ email: trimmedEmail }, 'Newsletter one-click unsubscribe');

    // Return a simple HTML confirmation page
    res.status(200).send(`
      <!DOCTYPE html>
      <html><head><title>Unsubscribed</title></head>
      <body style="font-family: sans-serif; text-align: center; padding: 60px 20px;">
        <h1>You've been unsubscribed</h1>
        <p>You will no longer receive newsletter emails from HavenKeep.</p>
      </body></html>
    `);
  })
);

export default router;
