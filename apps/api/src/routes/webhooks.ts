import { Router, Request, Response, NextFunction } from 'express';
import Stripe from 'stripe';
import { config } from '../config';
import { pool, query } from '../db';
import { logger } from '../utils/logger';

const router = Router();

const stripe = new Stripe(config.stripe.secretKey, {
  apiVersion: '2023-10-16',
});

/**
 * @route   POST /api/v1/webhooks/stripe
 * @desc    Handle Stripe webhook events for partner gift billing
 * @access  Public (verified via Stripe signature)
 */
router.post(
  '/stripe',
  async (req: Request, res: Response) => {
    const signature = req.headers['stripe-signature'];

    if (!signature) {
      logger.warn('Stripe webhook received without signature header');
      return res.status(400).json({ error: 'Missing stripe-signature header' });
    }

    let event: Stripe.Event;

    try {
      event = stripe.webhooks.constructEvent(
        req.body, // raw body buffer — must NOT be JSON-parsed
        signature,
        config.stripe.webhookSecret
      );
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      logger.error({ error: message }, 'Stripe webhook signature verification failed');
      return res.status(400).json({ error: 'Webhook signature verification failed' });
    }

    logger.info({ eventId: event.id, eventType: event.type }, 'Stripe webhook event received');

    try {
      switch (event.type) {
        case 'charge.succeeded':
          await handleChargeSucceeded(event.data.object as Stripe.Charge);
          break;

        case 'charge.failed':
          await handleChargeFailed(event.data.object as Stripe.Charge);
          break;

        case 'charge.refunded':
          await handleChargeRefunded(event.data.object as Stripe.Charge);
          break;

        default:
          logger.info({ eventType: event.type }, 'Unhandled Stripe webhook event type — ignoring');
      }
    } catch (err) {
      logger.error(
        { error: err, eventId: event.id, eventType: event.type },
        'Error processing Stripe webhook event'
      );
      // Return 500 so Stripe retries the webhook
      return res.status(500).json({ error: 'Webhook processing failed' });
    }

    // Acknowledge receipt — Stripe expects a 2xx within 20 seconds
    res.status(200).json({ received: true });
  }
);

/**
 * Handle charge.succeeded — mark partner gift as sent (if still created)
 */
async function handleChargeSucceeded(charge: Stripe.Charge): Promise<void> {
  const chargeId = charge.id;
  const partnerId = charge.metadata?.partner_id;

  const result = await pool.query(
    `UPDATE partner_gifts
     SET status = 'sent', updated_at = NOW()
     WHERE stripe_charge_id = $1 AND status = 'created'
     RETURNING id, partner_id, homebuyer_email`,
    [chargeId]
  );

  if (result.rows.length === 0) {
    logger.warn(
      { chargeId, partnerId },
      'charge.succeeded: no matching partner_gift found with status "created"'
    );
    return;
  }

  const gift = result.rows[0];

  // No commission status change needed here; stays pending until payout

  logger.info(
    { chargeId, giftId: gift.id, partnerId: gift.partner_id, homebuyer: gift.homebuyer_email },
    'charge.succeeded: partner gift payment confirmed'
  );
}

/**
 * Handle charge.failed — cancel partner gift
 */
async function handleChargeFailed(charge: Stripe.Charge): Promise<void> {
  const chargeId = charge.id;
  const failureMessage = charge.failure_message || 'Unknown failure';
  const partnerId = charge.metadata?.partner_id;

  const result = await pool.query(
    `UPDATE partner_gifts
     SET status = 'expired', updated_at = NOW()
     WHERE stripe_charge_id = $1 AND status = 'created'
     RETURNING id, partner_id, homebuyer_email`,
    [chargeId]
  );

  if (result.rows.length === 0) {
    logger.warn(
      { chargeId, partnerId },
      'charge.failed: no matching partner_gift found with status "created"'
    );
    return;
  }

  const gift = result.rows[0];

  // Mark the commission as cancelled
  await pool.query(
    `UPDATE partner_commissions
     SET status = 'cancelled', updated_at = NOW()
     WHERE reference_id = $1 AND reference_type = 'partner_gift' AND status = 'pending'`,
    [gift.id]
  );

  logger.info(
    {
      chargeId,
      giftId: gift.id,
      partnerId: gift.partner_id,
      homebuyer: gift.homebuyer_email,
      failureMessage,
    },
    'charge.failed: partner gift payment failed'
  );
}

/**
 * Handle charge.refunded — cancel partner gift and commission
 */
async function handleChargeRefunded(charge: Stripe.Charge): Promise<void> {
  const chargeId = charge.id;
  const partnerId = charge.metadata?.partner_id;

  const result = await pool.query(
    `UPDATE partner_gifts
     SET status = 'expired', updated_at = NOW()
     WHERE stripe_charge_id = $1 AND status IN ('created', 'sent', 'activated', 'expired')
     RETURNING id, partner_id, homebuyer_email, is_activated`,
    [chargeId]
  );

  if (result.rows.length === 0) {
    logger.warn(
      { chargeId, partnerId },
      'charge.refunded: no matching partner_gift found for refund'
    );
    return;
  }

  const gift = result.rows[0];

  // Mark the commission as cancelled
  await pool.query(
    `UPDATE partner_commissions
     SET status = 'cancelled', updated_at = NOW()
     WHERE reference_id = $1 AND reference_type = 'partner_gift'`,
    [gift.id]
  );

  // If the gift was already activated, revoke the premium upgrade
  if (gift.is_activated) {
    await pool.query(
      `UPDATE partner_gifts
       SET is_activated = FALSE, status = 'expired', updated_at = NOW()
       WHERE id = $1`,
      [gift.id]
    );

    logger.warn(
      { giftId: gift.id, partnerId: gift.partner_id },
      'charge.refunded: refunded an already-activated gift — premium may need manual review'
    );
  }

  logger.info(
    { chargeId, giftId: gift.id, partnerId: gift.partner_id, homebuyer: gift.homebuyer_email },
    'charge.refunded: partner gift payment refunded'
  );
}

// ============================================
// RevenueCat Webhook
// ============================================

/** RevenueCat webhook event types. */
type RevenueCatEventType =
  | 'INITIAL_PURCHASE'
  | 'RENEWAL'
  | 'CANCELLATION'
  | 'UNCANCELLATION'
  | 'EXPIRATION'
  | 'BILLING_ISSUE'
  | 'PRODUCT_CHANGE'
  | 'SUBSCRIBER_ALIAS'
  | 'TRANSFER'
  | 'TEST';

interface RevenueCatWebhookPayload {
  api_version: string;
  event: {
    type: RevenueCatEventType;
    id: string;
    app_user_id: string;
    original_app_user_id: string;
    aliases: string[];
    product_id: string;
    entitlement_ids: string[] | null;
    period_type: 'TRIAL' | 'INTRO' | 'NORMAL';
    purchased_at_ms: number;
    expiration_at_ms: number | null;
    store: 'APP_STORE' | 'PLAY_STORE' | 'STRIPE' | 'PROMOTIONAL';
    environment: 'PRODUCTION' | 'SANDBOX';
    is_family_share: boolean;
    currency: string;
    price_in_purchased_currency: number;
    subscriber_attributes: Record<string, { value: string; updated_at_ms: number }>;
    transaction_id: string;
    original_transaction_id: string;
  };
}

/**
 * Validate the RevenueCat webhook authorization header.
 *
 * RevenueCat sends the webhook secret in the Authorization header as a Bearer token.
 */
function validateRevenueCatWebhookAuth(req: Request, res: Response, next: NextFunction) {
  const webhookSecret = config.revenuecat.webhookSecret;

  if (!webhookSecret) {
    logger.error('REVENUECAT_WEBHOOK_SECRET not configured');
    return res.status(503).json({ error: 'Webhook not configured' });
  }

  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    logger.warn({ ip: req.ip }, 'RevenueCat webhook: missing authorization header');
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const token = authHeader.substring(7);
  if (token !== webhookSecret) {
    logger.warn({ ip: req.ip }, 'RevenueCat webhook: invalid authorization token');
    return res.status(401).json({ error: 'Unauthorized' });
  }

  next();
}

/**
 * Find a HavenKeep user by their RevenueCat app_user_id.
 *
 * RevenueCat sends the app_user_id which we set to the HavenKeep user UUID
 * during SDK initialization. Also checks aliases for account transfers.
 */
async function findUserByRevenueCatId(appUserId: string, aliases: string[]): Promise<string | null> {
  // The app_user_id should be the HavenKeep user UUID — try direct match first
  const directResult = await query(
    `SELECT id FROM users WHERE id = $1`,
    [appUserId]
  );

  if (directResult.rows.length > 0) {
    return directResult.rows[0].id;
  }

  // Check aliases (RevenueCat may send aliased IDs after transfers/merges)
  for (const alias of aliases) {
    const aliasResult = await query(
      `SELECT id FROM users WHERE id = $1`,
      [alias]
    );
    if (aliasResult.rows.length > 0) {
      return aliasResult.rows[0].id;
    }
  }

  return null;
}

/**
 * @route   POST /api/v1/webhooks/revenuecat
 * @desc    Handle RevenueCat server-to-server notifications for subscription events
 * @access  Public (verified via shared webhook secret in Authorization header)
 *
 * Events handled:
 * - INITIAL_PURCHASE: New subscription -> set plan to premium
 * - RENEWAL: Subscription renewed -> extend premium with new expiry
 * - UNCANCELLATION: User re-enabled auto-renew -> set plan to premium
 * - CANCELLATION: User cancelled (access continues until expiry) -> log, keep premium
 * - EXPIRATION: Subscription expired -> downgrade to free
 * - BILLING_ISSUE: Payment failed -> log warning, keep premium during grace period
 * - PRODUCT_CHANGE: Changed tiers -> update premium expiry
 * - TRANSFER / SUBSCRIBER_ALIAS: Account management -> log for audit
 * - TEST: Webhook test event -> acknowledge
 */
router.post('/revenuecat', validateRevenueCatWebhookAuth, async (req: Request, res: Response) => {
  try {
    const payload = req.body as RevenueCatWebhookPayload;

    if (!payload?.event?.type) {
      logger.warn('RevenueCat webhook: invalid payload (missing event.type)');
      return res.status(400).json({ error: 'Invalid webhook payload' });
    }

    const { event } = payload;

    logger.info(
      {
        eventType: event.type,
        eventId: event.id,
        appUserId: event.app_user_id,
        productId: event.product_id,
        store: event.store,
        rcEnvironment: event.environment,
      },
      'RevenueCat webhook received'
    );

    // Handle test events immediately
    if (event.type === 'TEST') {
      logger.info('RevenueCat webhook test event received');
      return res.status(200).json({ success: true });
    }

    // Find the HavenKeep user
    const userId = await findUserByRevenueCatId(
      event.app_user_id,
      event.aliases || []
    );

    if (!userId) {
      // User not found — can happen for sandbox testing or deleted users.
      // Acknowledge so RevenueCat doesn't retry indefinitely.
      logger.warn(
        {
          appUserId: event.app_user_id,
          aliases: event.aliases,
          eventType: event.type,
        },
        'RevenueCat webhook: user not found'
      );
      return res.status(200).json({ success: true, message: 'User not found, event acknowledged' });
    }

    // Calculate expiration date from millisecond timestamp
    const expiresAt = event.expiration_at_ms
      ? new Date(event.expiration_at_ms).toISOString()
      : null;

    switch (event.type) {
      case 'INITIAL_PURCHASE':
      case 'RENEWAL':
      case 'UNCANCELLATION': {
        await query(
          `UPDATE users SET
            plan = 'premium',
            plan_expires_at = $1,
            updated_at = NOW()
           WHERE id = $2`,
          [expiresAt, userId]
        );
        logger.info(
          { userId, plan: 'premium', expiresAt, eventType: event.type },
          'User plan updated to premium'
        );
        break;
      }

      case 'CANCELLATION': {
        // User cancelled but still has access until expiry.
        // Keep plan as premium — EXPIRATION event will downgrade when it actually expires.
        logger.info(
          { userId, expiresAt, eventType: event.type },
          'User cancelled subscription (access continues until expiry)'
        );
        break;
      }

      case 'EXPIRATION': {
        await query(
          `UPDATE users SET
            plan = 'free',
            plan_expires_at = NULL,
            updated_at = NOW()
           WHERE id = $1`,
          [userId]
        );
        logger.info(
          { userId, eventType: event.type },
          'User plan downgraded to free (subscription expired)'
        );
        break;
      }

      case 'BILLING_ISSUE': {
        // Payment failed — keep premium for now. RevenueCat sends EXPIRATION
        // if the billing issue is not resolved within the grace period.
        logger.warn(
          { userId, productId: event.product_id, eventType: event.type },
          'Billing issue detected for user subscription'
        );
        break;
      }

      case 'PRODUCT_CHANGE': {
        // User changed between subscription tiers. All paid plans map to
        // "premium" in HavenKeep, so just update the expiry.
        await query(
          `UPDATE users SET
            plan = 'premium',
            plan_expires_at = $1,
            updated_at = NOW()
           WHERE id = $2`,
          [expiresAt, userId]
        );
        logger.info(
          { userId, productId: event.product_id, expiresAt, eventType: event.type },
          'User subscription product changed'
        );
        break;
      }

      case 'TRANSFER': {
        logger.info(
          {
            newOwnerAppUserId: event.app_user_id,
            originalAppUserId: event.original_app_user_id,
            eventType: event.type,
          },
          'Subscription transferred between accounts'
        );
        break;
      }

      case 'SUBSCRIBER_ALIAS': {
        logger.info(
          { appUserId: event.app_user_id, aliases: event.aliases, eventType: event.type },
          'RevenueCat subscriber alias created'
        );
        break;
      }

      default: {
        logger.info(
          { eventType: event.type, appUserId: event.app_user_id },
          'Unhandled RevenueCat webhook event type'
        );
      }
    }

    // Always return 200 to acknowledge — otherwise RevenueCat retries
    res.status(200).json({ success: true });
  } catch (err) {
    logger.error(
      { error: err },
      'Error processing RevenueCat webhook event'
    );
    // Return 500 so RevenueCat retries
    res.status(500).json({ error: 'Webhook processing failed' });
  }
});

export default router;
