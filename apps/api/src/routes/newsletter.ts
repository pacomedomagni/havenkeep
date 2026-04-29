import crypto from 'crypto';
import { Router } from 'express';
import { pool } from '../db';
import { config } from '../config';
import { logger } from '../utils/logger';
import { asyncHandler } from '../utils/async-handler';
import { newsletterRateLimiter } from '../middleware/rateLimiter';
import { sendMessage } from '../utils/response';
import { EmailService } from '../services/email.service';
import { validate } from '../middleware/validate';
import {
  subscribeNewsletterSchema,
  unsubscribeNewsletterBodySchema,
  confirmNewsletterQuerySchema,
  unsubscribeNewsletterQuerySchema,
} from '../validators/newsletter.validator';

/**
 * F110: full 256-bit HMAC token. The previous implementation truncated
 * to 128 bits ('hex'.slice(0,32)) which is still strong but loses half the
 * security margin for no operational reason. Hex digest is 64 chars.
 */
function unsubscribeToken(email: string): string {
  return crypto
    .createHmac('sha256', config.jwt.refreshSecret)
    .update(`newsletter:unsub:${email.toLowerCase()}`)
    .digest('hex');
}

export function newsletterUnsubscribeUrl(email: string): string {
  const base = config.app.apiUrl.replace(/\/$/, '');
  return `${base}/api/v1/newsletter/unsubscribe?email=${encodeURIComponent(email)}&t=${unsubscribeToken(email)}`;
}

/**
 * F112: derive client IP without trusting Express's `trust proxy` toggle.
 * Newsletter rate limiting needs a stable, hard-to-spoof identifier — the
 * socket address is the safest pre-LB value.
 */
function clientAddress(req: import('express').Request): string {
  return req.socket.remoteAddress || 'unknown';
}

function hashConfirmationToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}

const router = Router();

/**
 * @route   POST /api/v1/newsletter/subscribe
 * @desc    Step 1 of double-opt-in. Creates a pending_confirmation row and
 *          mails the address a confirmation link. Existing rows in the
 *          'subscribed' state are a no-op (we always return success to avoid
 *          leaking subscriber existence).
 * @access  Public
 */
router.post(
  '/subscribe',
  newsletterRateLimiter,
  validate(subscribeNewsletterSchema),
  asyncHandler(async (req, res) => {
    const { email, source } = req.body as { email: string; source: string };
    const trimmedEmail = email; // already lowercased by Joi

    try {
      // Generate single-use confirmation token. Stored hashed so a DB read
      // never exposes the live token. Plaintext is sent only via email.
      const confirmationToken = crypto.randomBytes(32).toString('base64url');
      const tokenHash = hashConfirmationToken(confirmationToken);

      // Insert (or replace any prior pending row). If the address is already
      // subscribed we silently no-op the email send.
      const upserted = await pool.query(
        `INSERT INTO newsletter_subscribers (
           email, ip_address, source, status,
           confirmation_token_hash, confirmation_sent_at, subscribed_at
         )
         VALUES ($1, $2, $3, 'pending_confirmation', $4, NOW(), NOW())
         ON CONFLICT (LOWER(email)) WHERE status = 'subscribed'
         DO NOTHING
         RETURNING id, status`,
        // F112: socket address, not req.ip (don't trust trust-proxy here).
        [trimmedEmail, clientAddress(req), source, tokenHash],
      );

      // No row returned = already subscribed -> just acknowledge.
      if (upserted.rows.length === 0) {
        return sendMessage(res, 'Check your inbox to confirm your subscription');
      }

      // Try to send the confirmation email. Don't 500 the user if SendGrid
      // hiccups — a polling job will retry pending confirmations.
      const confirmUrl = `${config.app.apiUrl.replace(/\/$/, '')}/api/v1/newsletter/confirm?token=${encodeURIComponent(confirmationToken)}`;
      EmailService.sendNewsletterConfirmation?.({ to: trimmedEmail, confirmUrl })
        .catch((err: unknown) => {
          logger.error({ err, email: trimmedEmail }, 'Failed to send newsletter confirmation email');
        });

      logger.info({ email: trimmedEmail }, 'Newsletter pending_confirmation row created');
      return sendMessage(res, 'Check your inbox to confirm your subscription');
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
 * @route   GET /api/v1/newsletter/confirm
 * @desc    Step 2 of double-opt-in. Confirms the subscription by hashing the
 *          token from the email link and matching it to the pending row.
 * @access  Public
 */
router.get(
  '/confirm',
  validate(confirmNewsletterQuerySchema, 'query'),
  asyncHandler(async (req, res) => {
    const { token } = req.query as { token: string };
    const tokenHash = hashConfirmationToken(token);
    const result = await pool.query(
      `UPDATE newsletter_subscribers
          SET status = 'subscribed',
              confirmed_at = NOW(),
              confirmation_token_hash = NULL
        WHERE confirmation_token_hash = $1
          AND status = 'pending_confirmation'
        RETURNING email`,
      [tokenHash],
    );

    if (result.rows.length === 0) {
      logger.warn('Newsletter confirm: invalid or expired token');
      return res.status(400).send('Invalid or expired confirmation link');
    }

    logger.info({ email: result.rows[0].email }, 'Newsletter subscription confirmed');
    return res.status(200).send(`
      <!DOCTYPE html>
      <html><head><title>Confirmed</title></head>
      <body style="font-family: sans-serif; text-align: center; padding: 60px 20px;">
        <h1>You're subscribed</h1>
        <p>Thanks for confirming. We'll be in touch.</p>
      </body></html>
    `);
  }),
);

/**
 * @route   POST /api/v1/newsletter/unsubscribe
 * @desc    Unsubscribe an email address from the newsletter
 * @access  Public (CAN-SPAM/GDPR one-click unsubscribe)
 */
router.post(
  '/unsubscribe',
  newsletterRateLimiter,
  validate(unsubscribeNewsletterBodySchema),
  asyncHandler(async (req, res) => {
    const { email, t } = req.body as { email: string; t: string };
    const trimmedEmail = email; // already lowercased by Joi

    // S-ME-09: require the same HMAC token the email-embedded GET path
    // requires. Without this, anyone who scrapes user emails can
    // unsubscribe arbitrary users in bulk.
    const expected = unsubscribeToken(trimmedEmail);
    const tokenBuf = Buffer.from(t, 'utf8');
    const expectedBuf = Buffer.from(expected, 'utf8');
    if (tokenBuf.length !== expectedBuf.length || !crypto.timingSafeEqual(tokenBuf, expectedBuf)) {
      logger.warn({ email: trimmedEmail }, 'Newsletter unsubscribe POST: invalid token');
      return res.status(400).json({ success: false, error: 'Invalid unsubscribe token' });
    }

    try {
      await pool.query(
        `UPDATE newsletter_subscribers
            SET status = 'unsubscribed',
                unsubscribed_at = NOW()
          WHERE LOWER(email) = $1
            AND status <> 'unsubscribed'`,
        [trimmedEmail],
      );

      logger.info({ email: trimmedEmail }, 'Newsletter unsubscribe');
      return sendMessage(res, 'Successfully unsubscribed from the newsletter');
    } catch (error) {
      logger.error({ error, email: trimmedEmail }, 'Newsletter unsubscribe failed');
      return res.status(500).json({
        success: false,
        error: 'Unsubscribe failed. Please try again later.',
      });
    }
  }),
);

/**
 * @route   GET /api/v1/newsletter/unsubscribe
 * @desc    One-click unsubscribe via email link (RFC 8058 List-Unsubscribe)
 * @access  Public
 */
router.get(
  '/unsubscribe',
  validate(unsubscribeNewsletterQuerySchema, 'query'),
  asyncHandler(async (req, res) => {
    const { email, t } = req.query as { email: string; t: string };
    const trimmedEmail = email; // already lowercased by Joi
    const expected = unsubscribeToken(trimmedEmail);
    const tokenBuf = Buffer.from(t, 'utf8');
    const expectedBuf = Buffer.from(expected, 'utf8');
    if (tokenBuf.length !== expectedBuf.length || !crypto.timingSafeEqual(tokenBuf, expectedBuf)) {
      logger.warn({ email: trimmedEmail }, 'Newsletter unsubscribe: invalid token');
      return res.status(400).send('Invalid unsubscribe link');
    }

    await pool.query(
      `UPDATE newsletter_subscribers
          SET status = 'unsubscribed',
              unsubscribed_at = NOW()
        WHERE LOWER(email) = $1
          AND status <> 'unsubscribed'`,
      [trimmedEmail],
    );

    logger.info({ email: trimmedEmail }, 'Newsletter one-click unsubscribe');

    res.status(200).send(`
      <!DOCTYPE html>
      <html><head><title>Unsubscribed</title></head>
      <body style="font-family: sans-serif; text-align: center; padding: 60px 20px;">
        <h1>You've been unsubscribed</h1>
        <p>You will no longer receive newsletter emails from HavenKeep.</p>
      </body></html>
    `);
  }),
);

/**
 * @route   POST /api/v1/newsletter/unsubscribe-one-click
 * @desc    F109: RFC 8058 List-Unsubscribe-Post target. Mail clients hit
 *          this URL with a body of `List-Unsubscribe=One-Click` when the
 *          user clicks "Unsubscribe" in Gmail / Apple Mail. We accept both
 *          token-bearing query params and a List-Unsubscribe form body.
 * @access  Public
 */
router.post(
  '/unsubscribe-one-click',
  validate(unsubscribeNewsletterQuerySchema, 'query'),
  asyncHandler(async (req, res) => {
    // Mail providers POST a tiny `List-Unsubscribe=One-Click` form body —
    // we don't actually need it for anything beyond presence detection, but
    // refuse the request when it's missing so a casual GET-converted-to-POST
    // can't toggle subscriber state.
    const body = (req.body || {}) as Record<string, string>;
    if (body['List-Unsubscribe'] !== 'One-Click') {
      return res.status(400).send('Missing List-Unsubscribe=One-Click body');
    }

    const { email, t } = req.query as { email: string; t: string };
    const trimmedEmail = email;
    const expected = unsubscribeToken(trimmedEmail);
    const tokenBuf = Buffer.from(t, 'utf8');
    const expectedBuf = Buffer.from(expected, 'utf8');
    if (tokenBuf.length !== expectedBuf.length || !crypto.timingSafeEqual(tokenBuf, expectedBuf)) {
      logger.warn({ email: trimmedEmail }, 'Newsletter one-click POST: invalid token');
      return res.status(400).send('Invalid unsubscribe link');
    }

    await pool.query(
      `UPDATE newsletter_subscribers
          SET status = 'unsubscribed',
              unsubscribed_at = NOW()
        WHERE LOWER(email) = $1
          AND status <> 'unsubscribed'`,
      [trimmedEmail],
    );

    logger.info({ email: trimmedEmail }, 'Newsletter unsubscribe (one-click POST)');
    return res.status(200).send('OK');
  }),
);

export default router;
