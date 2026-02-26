import { Router } from 'express';
import { pool } from '../db';
import { logger } from '../utils/logger';
import { asyncHandler } from '../utils/async-handler';

const router = Router();

/**
 * @route   POST /api/v1/newsletter/subscribe
 * @desc    Subscribe an email address to the newsletter
 * @access  Public (no authentication required)
 */
router.post(
  '/subscribe',
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

      return res.status(200).json({
        success: true,
        message: 'Successfully subscribed to the newsletter',
      });
    } catch (error) {
      logger.error({ error, email: trimmedEmail }, 'Newsletter subscription failed');
      return res.status(500).json({
        success: false,
        error: 'Subscription failed. Please try again later.',
      });
    }
  })
);

export default router;
