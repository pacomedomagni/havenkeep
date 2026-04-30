import { Router, Request, Response, NextFunction } from 'express';
import Stripe from 'stripe';
import crypto from 'crypto';
import { config } from '../config';
import { pool, query, getClient } from '../db';
import { logger } from '../utils/logger';
import { invalidateUserCache } from '../middleware/auth';
import { createStripeClient } from '../utils/stripe-client';
import { AuditService } from '../services/audit.service';

/**
 * H-P2 (audit): every webhook-driven plan transition writes an audit
 * row tagged with the originating webhook source + event id. Without
 * this the hash-chain forensic trail (mig 065/082) couldn't answer
 * "why is this user on free tier?" — webhook handlers were updating
 * users.plan directly and the only signal was a Loki line.
 *
 * Best-effort: a transient AuditService failure must not roll back
 * the plan change. The plan UPDATE itself is the source of truth;
 * the audit row is the forensic breadcrumb.
 */
function auditWebhookPlanTransition(input: {
  userId: string;
  fromPlan: string | null;
  toPlan: string;
  webhookSource: 'stripe' | 'revenuecat';
  webhookEventId: string;
  webhookEventType: string;
  reason?: string;
}): void {
  const action: 'user.plan_upgrade' | 'user.plan_downgrade' =
    input.toPlan === 'premium' ? 'user.plan_upgrade' : 'user.plan_downgrade';
  AuditService.log({
    action,
    userId: input.userId,
    success: true,
    description: `Plan ${input.fromPlan ?? 'unknown'} → ${input.toPlan} via ${input.webhookSource} ${input.webhookEventType}${input.reason ? ` (${input.reason})` : ''}`,
    metadata: {
      previous_plan: input.fromPlan,
      new_plan: input.toPlan,
      webhook_source: input.webhookSource,
      webhook_event_id: input.webhookEventId,
      webhook_event_type: input.webhookEventType,
      ...(input.reason ? { reason: input.reason } : {}),
    },
  }).catch((err) => {
    logger.error(
      { err, userId: input.userId, webhookEventId: input.webhookEventId },
      'auditWebhookPlanTransition failed (best-effort)',
    );
  });
}

/**
 * C7: partner_gifts.stripe_charge_id stores PaymentIntent IDs (pi_*), not
 * Charge IDs (ch_*). Stripe `charge.*` event objects expose the underlying
 * intent via `charge.payment_intent` which can be either a string id or a
 * pre-expanded PaymentIntent object — normalise to the id string.
 */
function getChargePaymentIntentId(charge: Stripe.Charge): string | null {
  const pi = charge.payment_intent;
  if (typeof pi === 'string') return pi;
  if (pi && typeof pi === 'object' && 'id' in pi) return pi.id;
  return null;
}

/**
 * `charge.refunded` may fire on a charge that funded a partner gift whose
 * commission has already been marked `paid` and a Stripe transfer has fired
 * to the partner connected account. Cancelling the commission row in that
 * state would lose the audit trail for the original earning AND lie about
 * the partner having been paid. Instead we record a reversal: a new
 * partner_commissions row with status='reversed', a negative amount, and a
 * `reversal_of_commission_id` pointing back at the original. Pending or
 * approved commissions (not yet paid out) get cancelled in place.
 *
 * C8: takes an optional `proportion` (0..1] for partial refunds. Defaults to
 * 1.0 (full reversal). Partial refunds reverse a proportional slice of the
 * commission and don't expire the gift; full refunds use the original logic.
 */
async function clawbackCommissionForGift(
  client: import('pg').PoolClient,
  giftId: string,
  proportion = 1,
): Promise<void> {
  const original = await client.query(
    `SELECT id, partner_id, amount, status, stripe_transfer_id
       FROM partner_commissions
      WHERE reference_id = $1 AND reference_type = 'partner_gift'
        AND status NOT IN ('reversed', 'cancelled')
      FOR UPDATE`,
    [giftId],
  );
  for (const row of original.rows) {
    // For partial refunds the reversal is proportional; round to two decimals
    // so it stays inside DECIMAL(10,2) precision and matches the commission
    // column shape. Math.round avoids fractional-cent drift on odd splits.
    const reversalAmount =
      proportion >= 1
        ? -Number(row.amount)
        : -Math.round(Number(row.amount) * proportion * 100) / 100;
    const description =
      proportion >= 1
        ? 'Refund clawback for refunded gift'
        : `Partial refund clawback (${Math.round(proportion * 100)}%) for partially-refunded gift`;

    if (row.status === 'paid' && row.stripe_transfer_id) {
      // Money already left the platform balance — record a reversal so the
      // ledger sums to zero. The actual Stripe transfer reversal is initiated
      // by the operator (admin route), since automated reversal of partner
      // payouts is too dangerous to do in a webhook handler.
      await client.query(
        `INSERT INTO partner_commissions (
           partner_id, type, amount, commission_rate, status,
           reference_id, reference_type, reversal_of_commission_id, description
         ) VALUES ($1, 'gift', $2, 0, 'reversed', $3, 'partner_gift', $4, $5)`,
        [row.partner_id, reversalAmount, giftId, row.id, description],
      );
      logger.warn(
        { commissionId: row.id, giftId, amount: reversalAmount, proportion },
        'Recorded refund clawback against PAID commission — partner already paid; manual transfer reversal required',
      );
    } else if (proportion < 1) {
      // Partial refund against an unpaid commission: keep the original row
      // and add a partial reversal row alongside it. Don't cancel the
      // original — it represents the post-refund residual the partner is
      // still owed.
      await client.query(
        `INSERT INTO partner_commissions (
           partner_id, type, amount, commission_rate, status,
           reference_id, reference_type, reversal_of_commission_id, description
         ) VALUES ($1, 'gift', $2, 0, 'reversed', $3, 'partner_gift', $4, $5)`,
        [row.partner_id, reversalAmount, giftId, row.id, description],
      );
      logger.info(
        { commissionId: row.id, giftId, amount: reversalAmount, proportion },
        'Recorded partial refund clawback against unpaid commission',
      );
    } else {
      await client.query(
        `UPDATE partner_commissions SET status = 'cancelled', updated_at = NOW()
          WHERE id = $1`,
        [row.id],
      );
      logger.info(
        { commissionId: row.id, giftId, status: row.status },
        'Cancelled unpaid commission on charge.refunded',
      );
    }
  }
}

/**
 * Claim an event for processing. Returns:
 *  - 'claimed'    : first time we've seen this event, safe to process
 *  - 'retry'      : a prior attempt recorded it as pending/failed; we re-claim
 *  - 'processed'  : already processed, skip
 *  - 'dead_letter': retry budget exhausted; never re-process automatically
 *
 * Uses INSERT ... ON CONFLICT DO UPDATE so the check is atomic under
 * concurrent deliveries. Only when the row transitions to `status='pending'`
 * does the caller hold the right to process it. The `attempts` counter +
 * MAX_WEBHOOK_ATTEMPTS gate enforce the dead-letter cap (Ch03-F046).
 */
const MAX_WEBHOOK_ATTEMPTS = 8;

type ClaimOutcome = 'claimed' | 'retry' | 'processed' | 'dead_letter';

async function claimWebhookEvent(
  eventId: string,
  source: string,
  eventType: string,
  eventCreatedAt: Date,
  payloadDigest: string,
): Promise<ClaimOutcome> {
  // S1-G: under heavy parallel deliveries, the `attempts + 1 >= MAX` branch
  // could be evaluated by two transactions that each saw the same `attempts`
  // and both flipped to `dead_letter` (or, worse, neither did). Wrap the
  // claim in an explicit transaction and lock the existing row with
  // `SELECT … FOR UPDATE` before the upsert so the threshold check + status
  // transition are atomic against the row's committed state.
  const client = await getClient();
  try {
    await client.query('BEGIN');

    // Take the row lock if the row already exists. The first concurrent
    // caller takes it; the second waits until COMMIT, then sees the bumped
    // `attempts` when its own UPSERT evaluates the CASE expression.
    await client.query(
      `SELECT 1 FROM webhook_events
        WHERE source = $1 AND event_id = $2
        FOR UPDATE`,
      [source, eventId],
    );

    const result = await client.query(
      `INSERT INTO webhook_events (
         event_id, source, event_type, status, claimed_at,
         event_created_at, first_seen_at, last_seen_at, payload_digest, attempts
       )
       VALUES ($1, $2, $3, 'pending', NOW(), $4, NOW(), NOW(), $5, 1)
       ON CONFLICT (source, event_id) DO UPDATE
         SET status = CASE
                        WHEN webhook_events.status IN ('processed', 'dead_letter')
                          THEN webhook_events.status
                        WHEN webhook_events.attempts + 1 >= ${MAX_WEBHOOK_ATTEMPTS}
                          THEN 'dead_letter'
                        ELSE 'pending'
                      END,
             claimed_at = CASE
                            WHEN webhook_events.status IN ('processed', 'dead_letter')
                              THEN webhook_events.claimed_at
                            ELSE NOW()
                          END,
             last_seen_at = NOW(),
             attempts = CASE
                          WHEN webhook_events.status IN ('processed', 'dead_letter')
                            THEN webhook_events.attempts
                          ELSE webhook_events.attempts + 1
                        END
       RETURNING status, attempts, (xmax = 0) AS inserted`,
      [eventId, source, eventType, eventCreatedAt, payloadDigest],
    );

    await client.query('COMMIT');

    const row = result.rows[0];
    if (row.status === 'processed') return 'processed';
    if (row.status === 'dead_letter') return 'dead_letter';
    return row.inserted ? 'claimed' : 'retry';
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

async function markWebhookProcessed(eventId: string, source: string): Promise<void> {
  await query(
    `UPDATE webhook_events
        SET status = 'processed',
            processed_at = NOW(),
            last_seen_at = NOW(),
            last_error = NULL
      WHERE source = $1 AND event_id = $2`,
    [source, eventId],
  );
}

async function markWebhookFailed(eventId: string, source: string, err: unknown): Promise<void> {
  const message = err instanceof Error ? err.message : String(err);
  // Strip likely secrets before persisting (Ch03-F048): tokens, keys, JWT-ish.
  const safeMessage = message
    .replace(/(?:Bearer|api[_-]?key|sk_live_|sk_test_|whsec_)[\s=:]*[A-Za-z0-9._-]+/gi, '[redacted]')
    .replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, '[redacted-jwt]')
    .slice(0, 1000);
  await query(
    `UPDATE webhook_events
        SET status = CASE
                       WHEN attempts >= ${MAX_WEBHOOK_ATTEMPTS} THEN 'dead_letter'
                       ELSE 'failed'
                     END,
            last_error = $3,
            last_seen_at = NOW()
      WHERE source = $1 AND event_id = $2`,
    [source, eventId, safeMessage],
  );
}

/**
 * Per-source ordering guard (Ch03-F009). Stripe + RC both deliver retries
 * out-of-order. We use an event-stream timestamp + a high-water table so a
 * stale event can't undo a fresher one's effect. Returns true if the caller
 * should proceed (this event is at least as recent as anything we've seen).
 *
 * `subjectId` scopes the order: per-user for RC, per-charge for Stripe. A
 * tx-managed UPSERT under the unique key guarantees only one writer wins.
 */
async function isEventInOrder(
  source: string,
  subjectId: string,
  eventId: string,
  eventAt: Date,
): Promise<boolean> {
  const upsert = await query(
    `INSERT INTO webhook_event_high_water (source, subject_id, last_event_at, last_event_id)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (source, subject_id) DO UPDATE
       SET last_event_at = EXCLUDED.last_event_at,
           last_event_id = EXCLUDED.last_event_id,
           updated_at = NOW()
     WHERE webhook_event_high_water.last_event_at <= EXCLUDED.last_event_at
     RETURNING last_event_at`,
    [source, subjectId, eventAt, eventId],
  );
  return upsert.rowCount === 1;
}

function sha256(input: string | Buffer): string {
  return crypto.createHash('sha256').update(input).digest('hex');
}

// Two separate routers so each can be mounted with the body parser it needs:
//   - stripeWebhookRouter mounts under express.raw() (signature verification)
//   - revenueCatWebhookRouter mounts under express.json() (parsed body)
// app.ts wires both at their final paths. Splitting prevents the "JSON parser
// races the raw parser" failure mode that the old single-router setup had.
export const stripeWebhookRouter = Router();
export const revenueCatWebhookRouter = Router();

const stripe = createStripeClient();

/**
 * POST /  (mounted at /api/v1/webhooks/stripe)
 * Handle Stripe webhook events for partner gift billing.
 * Public (verified via Stripe signature).
 */
stripeWebhookRouter.post(
  '/',
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

    // Timestamp freshness: Stripe's signature check covers replay integrity,
    // but also reject events whose `created` is older than STRIPE_MAX_AGE_SEC
    // to limit replay windows if signing secret were ever leaked. Skip the
    // window if no DB row exists yet for this event — Ch03-F044: a freshly
    // delivered late retry shouldn't be silently dropped while we still have
    // the subject id to act on. The age check kicks in only on replays of
    // events we've seen before.
    const STRIPE_MAX_AGE_SEC = 5 * 60;
    const eventCreatedDate = new Date(event.created * 1000);
    const ageSec = Math.floor(Date.now() / 1000) - event.created;
    if (ageSec > STRIPE_MAX_AGE_SEC) {
      const seenBefore = await query(
        `SELECT 1 FROM webhook_events WHERE source = 'stripe' AND event_id = $1 LIMIT 1`,
        [event.id],
      );
      if (seenBefore.rows.length > 0) {
        logger.warn(
          { eventId: event.id, eventType: event.type, ageSec },
          'Stripe webhook event too old — rejecting as potential replay',
        );
        return res.status(400).json({ error: 'Event too old' });
      }
      logger.warn(
        { eventId: event.id, eventType: event.type, ageSec },
        'Stripe webhook event old but unseen — accepting first-time delivery',
      );
    }

    const payloadDigest = sha256(req.body as Buffer);
    const claim = await claimWebhookEvent(
      event.id,
      'stripe',
      event.type,
      eventCreatedDate,
      payloadDigest,
    );
    if (claim === 'processed') {
      logger.info(
        { eventId: event.id, eventType: event.type },
        'Stripe webhook event already processed — skipping',
      );
      return res.status(200).json({ received: true, duplicate: true });
    }
    if (claim === 'dead_letter') {
      // Stop the retry loop. Stripe will keep retrying for ~3 days; an op
      // engineer must inspect the dead-letter row and re-drive manually.
      logger.error(
        { eventId: event.id, eventType: event.type },
        'Stripe webhook event in dead-letter — acknowledging without processing',
      );
      return res.status(200).json({ received: true, deadLetter: true });
    }
    if (claim === 'retry') {
      logger.warn(
        { eventId: event.id, eventType: event.type },
        'Stripe webhook event re-claimed after prior failure',
      );
    }

    try {
      switch (event.type) {
        case 'charge.succeeded':
          await handleChargeSucceeded(event.data.object as Stripe.Charge);
          break;

        case 'charge.failed':
          await handleChargeFailed(event.data.object as Stripe.Charge);
          break;

        case 'charge.refunded':
          await handleChargeRefunded(event.data.object as Stripe.Charge, event.id);
          break;

        case 'payment_intent.canceled':
          await handlePaymentIntentCanceled(event.data.object as Stripe.PaymentIntent);
          break;

        case 'charge.dispute.created':
        case 'charge.dispute.updated':
        case 'charge.dispute.closed':
          // H-P1: pass event.created so the dispute handler can drop
          // out-of-order deliveries via isEventInOrder. event.created
          // is Stripe-side Unix seconds — convert to Date.
          await handleChargeDispute(
            event.data.object as Stripe.Dispute,
            event.id,
            new Date(event.created * 1000),
          );
          break;

        case 'account.updated':
          await handleAccountUpdated(event.data.object as Stripe.Account);
          break;

        case 'account.application.deauthorized':
          // Stripe types this event as Stripe.Application (the connected app),
          // not Stripe.Account. The deauthorized account id is on the parent
          // event under `event.account` — we read it directly from the Stripe
          // event envelope rather than from `event.data.object`.
          await handleAccountDeauthorized(event.account ?? null);
          break;

        // H-P3 (audit): explicitly observable handlers for events that
        // previously fell into the default branch silently.
        //
        // payout.failed is the most consequential: a partner payout
        // bounce (invalid bank account, frozen Connect account) left
        // commissions.status='paid' with stripe_transfer_id set while
        // the money never landed. Surface it loudly so on-call sees
        // the failure. Modern Stripe Connect emits payout.failed for
        // both top-up and connected-account bounces; the legacy
        // transfer.failed event is no longer in the SDK enum.
        case 'payout.failed': {
          const payout = event.data.object as Stripe.Payout;
          await handlePayoutFailed(payout.id, {
            amount: payout.amount,
            currency: payout.currency,
            failureCode: payout.failure_code,
            failureMessage: payout.failure_message,
          });
          break;
        }
        case 'payment_intent.payment_failed': {
          const intent = event.data.object as Stripe.PaymentIntent;
          logger.warn(
            {
              eventId: event.id,
              intentId: intent.id,
              amount: intent.amount,
              lastError: intent.last_payment_error?.message,
              code: intent.last_payment_error?.code,
            },
            'payment_intent.payment_failed — async card decline / SCA timeout',
          );
          break;
        }
        case 'customer.deleted': {
          const customer = event.data.object as Stripe.Customer;
          // A partner's stripe_customer_id becoming dangling means next
          // gift creation will fail. Don't auto-null it (the operator
          // may want forensic context); just log loudly so on-call
          // notices and can clean up via the admin UI.
          logger.error(
            { eventId: event.id, customerId: customer.id, deleted: customer.deleted ?? null },
            'customer.deleted — a HavenKeep partner/user may now have a dangling stripe_customer_id',
          );
          break;
        }
        case 'customer.updated': {
          // Default-payment-method changes etc. We don't mirror customer
          // state today; just log so a future feature has a hook.
          logger.info({ eventId: event.id }, 'customer.updated — ignoring (not mirrored)');
          break;
        }
        case 'radar.early_fraud_warning.created': {
          const warning = event.data.object as Stripe.Radar.EarlyFraudWarning;
          logger.error(
            {
              eventId: event.id,
              warningId: warning.id,
              chargeId: typeof warning.charge === 'string' ? warning.charge : warning.charge?.id,
              actionable: warning.actionable,
              reason: warning.fraud_type,
            },
            'radar.early_fraud_warning.created — pre-dispute alert; review manually',
          );
          break;
        }

        default:
          logger.info({ eventType: event.type }, 'Unhandled Stripe webhook event type — ignoring');
      }
      await markWebhookProcessed(event.id, 'stripe');
    } catch (err) {
      await markWebhookFailed(event.id, 'stripe', err);
      logger.error(
        { error: err, eventId: event.id, eventType: event.type },
        'Error processing Stripe webhook event'
      );
      return res.status(500).json({ error: 'Webhook processing failed' });
    }

    res.status(200).json({ received: true });
  }
);

/**
 * H-P3 (audit): handle payout.failed by flagging the matching
 * partner_commissions row and surfacing a loud ERROR log so on-call
 * sees the bounce. The prior "fall into default branch" path left
 * commissions.status='paid' / stripe_transfer_id set with the money
 * never having landed at the partner's bank.
 *
 * We don't auto-rollback the commission status — the partner may have
 * a recoverable payout method and an admin can re-trigger payout via
 * /admin/commissions/:id/pay. The ERROR log line is the on-call
 * signal; a future Phase 4 schema change adds a payout_failed_at
 * column for the admin UI to filter on.
 */
async function handlePayoutFailed(
  payoutId: string,
  context: Record<string, unknown>,
): Promise<void> {
  const result = await pool.query(
    `SELECT id, partner_id, amount FROM partner_commissions
      WHERE stripe_transfer_id = $1
      LIMIT 1`,
    [payoutId],
  );
  if (result.rows.length === 0) {
    logger.warn(
      { payoutId, ...context },
      'payout.failed: no matching partner_commissions row — orphan payout or pre-mig data',
    );
    return;
  }
  const commission = result.rows[0];
  logger.error(
    {
      payoutId,
      commissionId: commission.id,
      partnerId: commission.partner_id,
      amount: commission.amount,
      ...context,
    },
    'PARTNER PAYOUT FAILED — money did not land at partner; manual review + retransfer needed',
  );
}

/**
 * Handle charge.succeeded — mark partner gift as sent (if still created).
 * C7: match on payment_intent (partner_gifts.stripe_charge_id stores pi_*).
 */
async function handleChargeSucceeded(charge: Stripe.Charge): Promise<void> {
  const chargeId = charge.id;
  const paymentIntentId = getChargePaymentIntentId(charge);
  const partnerId = charge.metadata?.partner_id;

  if (!paymentIntentId) {
    logger.warn({ chargeId, partnerId }, 'charge.succeeded: event has no payment_intent — skipping');
    return;
  }

  const result = await pool.query(
    `UPDATE partner_gifts
     SET status = 'sent', updated_at = NOW()
     WHERE stripe_charge_id = $1 AND status = 'created'
     RETURNING id, partner_id, homebuyer_email`,
    [paymentIntentId]
  );

  if (result.rows.length === 0) {
    logger.warn(
      { chargeId, paymentIntentId, partnerId },
      'charge.succeeded: no matching partner_gift found with status "created"'
    );
    return;
  }

  const gift = result.rows[0];

  // No commission status change needed here; stays pending until payout

  logger.info(
    { chargeId, paymentIntentId, giftId: gift.id, partnerId: gift.partner_id, homebuyer: gift.homebuyer_email },
    'charge.succeeded: partner gift payment confirmed'
  );
}

/**
 * Handle charge.failed — cancel partner gift.
 * C7: match on payment_intent (partner_gifts.stripe_charge_id stores pi_*).
 */
async function handleChargeFailed(charge: Stripe.Charge): Promise<void> {
  const chargeId = charge.id;
  const paymentIntentId = getChargePaymentIntentId(charge);
  const failureMessage = charge.failure_message || 'Unknown failure';
  const partnerId = charge.metadata?.partner_id;

  if (!paymentIntentId) {
    logger.warn({ chargeId, partnerId }, 'charge.failed: event has no payment_intent — skipping');
    return;
  }

  const result = await pool.query(
    `UPDATE partner_gifts
     SET status = 'expired', updated_at = NOW()
     WHERE stripe_charge_id = $1 AND status = 'created'
     RETURNING id, partner_id, homebuyer_email`,
    [paymentIntentId]
  );

  if (result.rows.length === 0) {
    logger.warn(
      { chargeId, paymentIntentId, partnerId },
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
      paymentIntentId,
      giftId: gift.id,
      partnerId: gift.partner_id,
      homebuyer: gift.homebuyer_email,
      failureMessage,
    },
    'charge.failed: partner gift payment failed'
  );
}

/**
 * Handle charge.refunded — cancel partner gift and commission.
 *
 * C7: match on charge.payment_intent (partner_gifts.stripe_charge_id stores
 * pi_*, not ch_*).
 *
 * C8: distinguish full vs partial refunds via charge.amount_refunded vs
 * charge.amount. Partial refunds pro-rate the commission clawback and DO
 * NOT expire the gift or revoke premium — Stripe sends `charge.refunded`
 * for every partial too, and treating a $5 refund of a $99 gift as a full
 * reversal would silently destroy customer-friendly partial refunds.
 *
 * Replay-safe (full-refund path): the gift WHERE excludes rows already in
 * terminal refund state. Replay-safe (partial-refund path): the
 * partner_commissions WHERE inside clawbackCommissionForGift de-dupes via
 * `status NOT IN ('reversed','cancelled')` so a re-delivered partial
 * refund won't double-reverse — but a *different* partial after a previous
 * partial WILL produce another reversal row. That's correct: each partial
 * gets its own ledger entry.
 */
async function handleChargeRefunded(charge: Stripe.Charge, eventId: string): Promise<void> {
  const chargeId = charge.id;
  const paymentIntentId = getChargePaymentIntentId(charge);
  const partnerId = charge.metadata?.partner_id;

  if (!paymentIntentId) {
    logger.warn({ chargeId, partnerId }, 'charge.refunded: event has no payment_intent — skipping');
    return;
  }

  const amount = charge.amount;
  const amountRefunded = charge.amount_refunded;
  const fullyRefunded = amount > 0 && amountRefunded >= amount;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    if (!fullyRefunded) {
      // Partial refund: pro-rate commission clawback, leave gift status alone.
      const giftLookup = await client.query(
        `SELECT id, partner_id, homebuyer_email
           FROM partner_gifts
          WHERE stripe_charge_id = $1
          FOR UPDATE`,
        [paymentIntentId],
      );
      if (giftLookup.rows.length === 0) {
        await client.query('ROLLBACK').catch(() => {});
        logger.warn(
          { chargeId, paymentIntentId, partnerId },
          'charge.refunded (partial): no matching gift',
        );
        return;
      }
      const gift = giftLookup.rows[0];
      const proportion = amountRefunded / amount;
      await clawbackCommissionForGift(client, gift.id, proportion);
      await client.query('COMMIT');
      logger.info(
        {
          chargeId,
          paymentIntentId,
          giftId: gift.id,
          partnerId: gift.partner_id,
          amount,
          amountRefunded,
          proportion,
        },
        'charge.refunded (partial): pro-rated commission clawback recorded; gift not expired',
      );
      return;
    }

    // Full refund: expire the gift, clawback fully, revoke premium if last.
    const result = await client.query(
      `WITH old AS (
         SELECT id, partner_id, homebuyer_email, is_activated AS was_activated,
                activated_user_id, status AS old_status
         FROM partner_gifts
         WHERE stripe_charge_id = $1
           AND NOT (status = 'expired' AND is_activated = FALSE)
       )
       UPDATE partner_gifts pg
       SET status = 'expired', is_activated = FALSE, updated_at = NOW()
       FROM old
       WHERE pg.id = old.id
       RETURNING old.id, old.partner_id, old.homebuyer_email,
                 old.was_activated, old.activated_user_id, old.old_status`,
      [paymentIntentId]
    );

    if (result.rows.length === 0) {
      await client.query('ROLLBACK').catch(() => {});
      logger.info(
        { chargeId, paymentIntentId, partnerId },
        'charge.refunded: gift already in terminal refund state (replay) or no matching gift',
      );
      return;
    }

    const gift = result.rows[0];

    await clawbackCommissionForGift(client, gift.id);

    if (gift.was_activated && gift.activated_user_id) {
      const otherGifts = await client.query(
        `SELECT id FROM partner_gifts
         WHERE activated_user_id = $1 AND id != $2
           AND is_activated = TRUE AND status != 'expired'
           AND (expires_at IS NULL OR expires_at > NOW())`,
        [gift.activated_user_id, gift.id]
      );
      if (otherGifts.rows.length === 0) {
        await client.query(
          `UPDATE users SET plan = 'free', plan_expires_at = NULL, updated_at = NOW() WHERE id = $1`,
          [gift.activated_user_id]
        );
        // 2.3: revoke cache so the user's next call sees plan='free'
        // immediately instead of premium-for-up-to-10s.
        await invalidateUserCache(gift.activated_user_id);
        // H-P2: audit-log the webhook-driven plan downgrade.
        auditWebhookPlanTransition({
          userId: gift.activated_user_id,
          fromPlan: 'premium',
          toPlan: 'free',
          webhookSource: 'stripe',
          webhookEventId: eventId,
          webhookEventType: 'charge.refunded',
          reason: 'gift charge fully refunded',
        });
      } else {
        logger.info(
          { userId: gift.activated_user_id, otherActiveGifts: otherGifts.rows.length },
          'charge.refunded: user has other active gifts, keeping premium'
        );
      }
      logger.warn(
        { giftId: gift.id, partnerId: gift.partner_id },
        'charge.refunded: refunded an already-activated gift — premium revoked from activated user'
      );
    }

    await client.query('COMMIT');

    logger.info(
      { chargeId, paymentIntentId, giftId: gift.id, partnerId: gift.partner_id, homebuyer: gift.homebuyer_email },
      'charge.refunded: partner gift payment refunded'
    );
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Handle payment_intent.canceled — cancel any pending_payment gift bound
 * to this intent. We only act on rows that are still 'pending_payment' so a
 * later success path that flipped the row to 'created' isn't reverted.
 */
async function handlePaymentIntentCanceled(intent: Stripe.PaymentIntent): Promise<void> {
  const intentId = intent.id;
  const giftIdHint = (intent.metadata?.gift_id as string | undefined) ?? null;

  const result = await pool.query(
    `UPDATE partner_gifts
        SET status = 'expired', updated_at = NOW()
      WHERE (stripe_charge_id = $1 OR ($2::uuid IS NOT NULL AND id = $2::uuid))
        AND status = 'pending_payment'
      RETURNING id, partner_id`,
    [intentId, giftIdHint],
  );

  if (result.rows.length === 0) {
    logger.info(
      { intentId, giftIdHint },
      'payment_intent.canceled: no pending gift to expire',
    );
    return;
  }

  for (const row of result.rows) {
    await pool.query(
      `UPDATE partner_commissions
          SET status = 'cancelled', updated_at = NOW()
        WHERE reference_id = $1
          AND reference_type = 'partner_gift'
          AND status = 'pending'`,
      [row.id],
    );
  }

  logger.info(
    { intentId, giftIds: result.rows.map((r) => r.id) },
    'payment_intent.canceled: gifts expired',
  );
}

/**
 * Handle charge.dispute.* — record the chargeback on the gift, cancel any
 * unpaid commission, and warn loudly if the partner has already been paid.
 * The dispute outcome (won/lost) updates `chargeback_status`; on lost we
 * treat it like a refund (clawback + revoke premium).
 */
async function handleChargeDispute(
  dispute: Stripe.Dispute,
  eventId: string,
  eventAt: Date,
): Promise<void> {
  const chargeId = typeof dispute.charge === 'string' ? dispute.charge : dispute.charge?.id;
  // C7: partner_gifts.stripe_charge_id holds PaymentIntent IDs; the dispute
  // object exposes payment_intent directly (string id or expanded PI object).
  const paymentIntentId =
    typeof dispute.payment_intent === 'string'
      ? dispute.payment_intent
      : dispute.payment_intent?.id ?? null;
  if (!paymentIntentId) {
    logger.warn(
      { disputeId: dispute.id, chargeId },
      'dispute event missing payment_intent — ignoring',
    );
    return;
  }

  // H-P1 (audit): Stripe retries can be reordered. A
  // charge.dispute.closed (status='won') arriving before a delayed
  // charge.dispute.updated (status='under_review') would otherwise
  // leave chargeback_status='under_review' even though the dispute
  // is over. Use the same per-subject high-water table the RC
  // handler already uses. Subject: payment_intent (matches our gift
  // lookup column).
  const inOrder = await isEventInOrder('stripe', paymentIntentId, eventId, eventAt);
  if (!inOrder) {
    logger.info(
      { disputeId: dispute.id, paymentIntentId, eventId, eventAt: eventAt.toISOString() },
      'dispute event out of order — skipping',
    );
    return;
  }

  const status: string = dispute.status;
  // 'charge_refunded' isn't in the SDK enum but Stripe still returns it
  // for disputes whose underlying charge was refunded mid-dispute. Compare
  // as a string so the type check doesn't reject the literal.
  const lost = status === 'lost' || status === 'charge_refunded';

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const giftRes = await client.query(
      `UPDATE partner_gifts
          SET disputed_at = COALESCE(disputed_at, NOW()),
              chargeback_status = $2,
              updated_at = NOW()
        WHERE stripe_charge_id = $1
        RETURNING id, partner_id, is_activated, activated_user_id`,
      [paymentIntentId, status],
    );

    if (giftRes.rows.length === 0) {
      await client.query('ROLLBACK').catch(() => {});
      logger.warn(
        { chargeId, paymentIntentId, disputeId: dispute.id, status },
        'dispute: no matching partner gift',
      );
      return;
    }

    const gift = giftRes.rows[0];

    if (lost) {
      // Treat like a refund: clawback + revoke premium (replay-safe via the
      // existing clawback helper which excludes already-reversed/cancelled rows).
      await clawbackCommissionForGift(client, gift.id);

      if (gift.is_activated && gift.activated_user_id) {
        const others = await client.query(
          `SELECT id FROM partner_gifts
            WHERE activated_user_id = $1 AND id != $2
              AND is_activated = TRUE AND status != 'expired'
              AND (expires_at IS NULL OR expires_at > NOW())`,
          [gift.activated_user_id, gift.id],
        );
        if (others.rows.length === 0) {
          await client.query(
            `UPDATE users
                SET plan = 'free', plan_expires_at = NULL, updated_at = NOW()
              WHERE id = $1`,
            [gift.activated_user_id],
          );
          await invalidateUserCache(gift.activated_user_id);
          // H-P2: audit-log the dispute-lost plan downgrade.
          auditWebhookPlanTransition({
            userId: gift.activated_user_id,
            fromPlan: 'premium',
            toPlan: 'free',
            webhookSource: 'stripe',
            webhookEventId: eventId,
            webhookEventType: `charge.dispute.${status}`,
            reason: 'dispute lost — gift reversed',
          });
        }
      }

      await client.query(
        `UPDATE partner_gifts
            SET status = 'expired', is_activated = FALSE, updated_at = NOW()
          WHERE id = $1`,
        [gift.id],
      );
    }

    await client.query('COMMIT');
    logger.warn(
      { disputeId: dispute.id, chargeId, giftId: gift.id, status, lost },
      lost ? 'dispute lost — gift reversed' : 'dispute opened — gift flagged',
    );
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

/** Handle account.updated — refresh stripe_account_status from capabilities. */
async function handleAccountUpdated(account: Stripe.Account): Promise<void> {
  const accountId = account.id;
  const charges = account.charges_enabled ?? false;
  const payouts = account.payouts_enabled ?? false;
  const requirementsDisabled = account.requirements?.disabled_reason;

  let derived: string;
  if (requirementsDisabled === 'rejected.fraud' || requirementsDisabled === 'rejected.terms_of_service' || requirementsDisabled === 'rejected.listed' || requirementsDisabled === 'rejected.other') {
    derived = 'rejected';
  } else if (requirementsDisabled) {
    derived = 'restricted';
  } else if (charges && payouts) {
    derived = 'enabled';
  } else if (charges || payouts) {
    derived = 'restricted';
  } else {
    derived = 'pending';
  }

  await pool.query(
    `UPDATE partners
        SET stripe_account_status = $2,
            stripe_account_status_at = NOW(),
            stripe_onboarded = ($2 = 'enabled'),
            updated_at = NOW()
      WHERE stripe_account_id = $1`,
    [accountId, derived],
  );

  logger.info(
    { accountId, status: derived, charges, payouts },
    'account.updated: stripe_account_status refreshed',
  );
}

/** Handle account.application.deauthorized — partner revoked our access. */
async function handleAccountDeauthorized(accountId: string | null): Promise<void> {
  if (!accountId) {
    logger.warn('account.deauthorized: no account id on event envelope — skipping');
    return;
  }
  await pool.query(
    `UPDATE partners
        SET stripe_account_status = 'disabled',
            stripe_account_status_at = NOW(),
            stripe_onboarded = FALSE,
            stripe_account_id = NULL,
            updated_at = NOW()
      WHERE stripe_account_id = $1`,
    [accountId],
  );
  logger.warn({ accountId }, 'account.deauthorized: partner revoked Stripe access');
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
    /** Server time when RC fired the event — used as the ordering anchor. */
    event_timestamp_ms?: number;
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

  // S-ME-04: don't differentiate "secret not configured" from "auth failed"
  // via response code — both are unauthenticated states from the caller's
  // perspective. Returning 503 for one and 401 for the other lets a probe
  // discover whether the webhook is configured. Log the distinction
  // server-side; respond 401 either way.
  if (!webhookSecret) {
    logger.error('REVENUECAT_WEBHOOK_SECRET not configured');
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    logger.warn({ ip: req.ip }, 'RevenueCat webhook: missing authorization header');
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const token = authHeader.substring(7);
  const tokenHash = crypto.createHash('sha256').update(token).digest();
  const secretHash = crypto.createHash('sha256').update(webhookSecret).digest();
  if (!crypto.timingSafeEqual(tokenHash, secretHash)) {
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
  // The app_user_id should be the HavenKeep user UUID — try direct match
  // first. Filter `deleted_at IS NULL` so RevenueCat events for a
  // soft-deleted user can't provision premium against the tombstone row.
  const directResult = await query(
    `SELECT id FROM users WHERE id = $1 AND deleted_at IS NULL`,
    [appUserId]
  );

  if (directResult.rows.length > 0) {
    return directResult.rows[0].id;
  }

  // Check aliases (RevenueCat may send aliased IDs after transfers/merges)
  for (const alias of aliases) {
    const aliasResult = await query(
      `SELECT id FROM users WHERE id = $1 AND deleted_at IS NULL`,
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
revenueCatWebhookRouter.post('/', validateRevenueCatWebhookAuth, async (req: Request, res: Response) => {
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

    // SANDBOX gate. Sandbox events should never mutate production user state.
    // The flag (config.revenuecatAllowSandboxWebhooks) is true in dev/test
    // and false in production, so production silently acknowledges and drops
    // sandbox traffic instead of e.g. flipping a real user to premium.
    if (event.environment !== 'PRODUCTION' && !config.revenuecatAllowSandboxWebhooks) {
      logger.warn(
        { eventId: event.id, eventType: event.type, env: event.environment },
        'RevenueCat sandbox event ignored in production',
      );
      return res.status(200).json({ success: true, sandboxIgnored: true });
    }

    // Handle test events immediately
    if (event.type === 'TEST') {
      logger.info('RevenueCat webhook test event received');
      return res.status(200).json({ success: true });
    }

    // Event-stream ordering anchor. RC's `event_timestamp_ms` is the server
    // emission time; fall back to `purchased_at_ms` for older payloads.
    const eventAtMs = event.event_timestamp_ms ?? event.purchased_at_ms ?? Date.now();
    const eventCreatedDate = new Date(eventAtMs);
    const payloadDigest = sha256(JSON.stringify(req.body));

    const claim = await claimWebhookEvent(
      event.id,
      'revenuecat',
      event.type,
      eventCreatedDate,
      payloadDigest,
    );
    if (claim === 'processed') {
      logger.info({ eventId: event.id, eventType: event.type }, 'RevenueCat webhook event already processed — skipping');
      return res.status(200).json({ success: true, duplicate: true });
    }
    if (claim === 'dead_letter') {
      logger.error(
        { eventId: event.id, eventType: event.type },
        'RevenueCat webhook event in dead-letter — acknowledging without processing',
      );
      return res.status(200).json({ success: true, deadLetter: true });
    }
    if (claim === 'retry') {
      logger.warn({ eventId: event.id, eventType: event.type }, 'RevenueCat webhook event re-claimed after prior failure');
    }

    // Validate app_user_id format BEFORE handing it to a UUID column query;
    // a non-UUID app_user_id (Ch03-F007) used to throw "invalid uuid" against
    // pg, which then poisoned the retry by recording the event as failed.
    const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!UUID_RE.test(event.app_user_id) && !(event.aliases || []).some((a) => UUID_RE.test(a))) {
      logger.warn(
        { appUserId: event.app_user_id, aliases: event.aliases, eventType: event.type },
        'RevenueCat webhook: app_user_id is not a HavenKeep UUID — acknowledging',
      );
      await markWebhookProcessed(event.id, 'revenuecat');
      return res.status(200).json({ success: true, ignored: 'non-uuid-app-user-id' });
    }

    // Find the HavenKeep user
    const userId = await findUserByRevenueCatId(
      event.app_user_id,
      event.aliases || []
    );

    if (!userId) {
      // User not found — can happen for sandbox testing or deleted users.
      // Mark processed so the event isn't re-driven; acknowledge.
      logger.warn(
        {
          appUserId: event.app_user_id,
          aliases: event.aliases,
          eventType: event.type,
        },
        'RevenueCat webhook: user not found'
      );
      await markWebhookProcessed(event.id, 'revenuecat');
      return res.status(200).json({ success: true, message: 'User not found, event acknowledged' });
    }

    // Per-user ordering guard (Ch03-F009). A late-arriving stale event
    // (e.g. a delayed CANCELLATION arriving after a RENEWAL) must not undo
    // the fresher state. We only accept events whose stream timestamp is
    // >= the last applied event for this user.
    const inOrder = await isEventInOrder('revenuecat', userId, event.id, eventCreatedDate);
    if (!inOrder) {
      logger.warn(
        { eventId: event.id, eventType: event.type, userId, eventAt: eventCreatedDate.toISOString() },
        'RevenueCat webhook: out-of-order event ignored',
      );
      await markWebhookProcessed(event.id, 'revenuecat');
      return res.status(200).json({ success: true, outOfOrder: true });
    }

    // Calculate expiration date from millisecond timestamp. A purchase with
    // null expiration_at_ms is RC's way of signalling lifetime/non-expiring
    // entitlement (Ch03-F003). We persist it as a far-future sentinel so the
    // gate code that compares plan_expires_at < NOW() doesn't downgrade.
    const FAR_FUTURE = new Date(Date.UTC(9999, 0, 1)).toISOString();
    const expiresAt = event.expiration_at_ms
      ? new Date(event.expiration_at_ms).toISOString()
      : FAR_FUTURE;

    // Entitlement gate (Ch03-F005). Only a "premium"-bearing entitlement
    // upgrades the user. RC's `entitlement_ids` is an array of identifiers
    // configured in the RC dashboard; we treat the literal "premium" id as
    // the canonical premium entitlement. Empty/null means "no entitlement
    // granted on this event" — log and skip the upgrade.
    const grantsPremium =
      Array.isArray(event.entitlement_ids) &&
      event.entitlement_ids.some((eid) => eid.toLowerCase() === 'premium');

    // H-P2: capture the prior plan once so every plan-touching branch
    // below can stamp accurate from→to metadata into its audit row.
    const priorPlanResult = await query(
      `SELECT plan FROM users WHERE id = $1`,
      [userId],
    );
    const priorPlan: string | null = priorPlanResult.rows[0]?.plan ?? null;

    switch (event.type) {
      case 'INITIAL_PURCHASE':
      case 'RENEWAL':
      case 'UNCANCELLATION': {
        if (!grantsPremium) {
          logger.warn(
            { userId, productId: event.product_id, entitlements: event.entitlement_ids },
            'RC purchase event missing premium entitlement — not upgrading',
          );
          break;
        }
        await query(
          `UPDATE users SET
            plan = 'premium',
            plan_expires_at = $1,
            updated_at = NOW()
           WHERE id = $2`,
          [expiresAt, userId]
        );
        // 2.3: drop cache so all replicas reflect the new premium status now.
        await invalidateUserCache(userId);
        // H-P2: audit-log the upgrade with from→to + RC event id.
        if (priorPlan !== 'premium') {
          auditWebhookPlanTransition({
            userId,
            fromPlan: priorPlan,
            toPlan: 'premium',
            webhookSource: 'revenuecat',
            webhookEventId: event.id,
            webhookEventType: event.type,
          });
        }
        logger.info(
          {
            userId,
            plan: 'premium',
            expiresAt,
            eventType: event.type,
            periodType: event.period_type,
          },
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
        // Don't downgrade if the user still holds an active partner gift —
        // the gift is a separate premium grant from the RC subscription and
        // the test that codified the buggy behavior (Ch12-R001) lost paying
        // partner-gifted users on subscription expiry. Mirror the refund
        // path's check: any other un-expired, un-revoked gift keeps premium.
        const activeGiftCount = await query(
          `SELECT 1
             FROM partner_gifts
            WHERE activated_user_id = $1
              AND is_activated = TRUE
              AND status <> 'expired'
              AND (expires_at IS NULL OR expires_at > NOW())
            LIMIT 1`,
          [userId],
        );
        if (activeGiftCount.rows.length > 0) {
          logger.info(
            { userId, eventType: event.type },
            'EXPIRATION: keeping premium because user holds an active partner gift',
          );
        } else {
          await query(
            `UPDATE users SET
              plan = 'free',
              plan_expires_at = NULL,
              updated_at = NOW()
             WHERE id = $1`,
            [userId]
          );
          await invalidateUserCache(userId);
          // H-P2: audit-log subscription-expired downgrade.
          if (priorPlan === 'premium') {
            auditWebhookPlanTransition({
              userId,
              fromPlan: priorPlan,
              toPlan: 'free',
              webhookSource: 'revenuecat',
              webhookEventId: event.id,
              webhookEventType: event.type,
              reason: 'subscription expired',
            });
          }
          logger.info(
            { userId, eventType: event.type },
            'User plan downgraded to free (subscription expired)'
          );
        }
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
        // "premium" in HavenKeep, so just update the expiry — but only if
        // the new product still grants the premium entitlement (Ch03-F005).
        if (!grantsPremium) {
          logger.warn(
            { userId, productId: event.product_id, entitlements: event.entitlement_ids },
            'RC PRODUCT_CHANGE: new product missing premium entitlement — not extending plan',
          );
          break;
        }
        await query(
          `UPDATE users SET
            plan = 'premium',
            plan_expires_at = $1,
            updated_at = NOW()
           WHERE id = $2`,
          [expiresAt, userId]
        );
        await invalidateUserCache(userId);
        logger.info(
          { userId, productId: event.product_id, expiresAt, eventType: event.type },
          'User subscription product changed'
        );
        break;
      }

      case 'TRANSFER': {
        // Transfer must move premium from the original_app_user_id to the
        // new app_user_id (Ch03-F006). The original holder loses access.
        // Both ids are required; if either is missing or refers to a
        // non-existent HavenKeep user, log and skip.
        const originalId = event.original_app_user_id;
        if (!originalId || originalId === event.app_user_id) {
          logger.warn(
            { eventId: event.id, app: event.app_user_id, original: originalId },
            'RC TRANSFER: original_app_user_id missing or equal — no-op',
          );
          break;
        }
        if (UUID_RE.test(originalId)) {
          // Strip premium from the source account *unless* a partner gift
          // still keeps them on premium (mirror of EXPIRATION).
          const sourceGifts = await query(
            `SELECT 1 FROM partner_gifts
              WHERE activated_user_id = $1 AND is_activated = TRUE
                AND status <> 'expired'
                AND (expires_at IS NULL OR expires_at > NOW())
              LIMIT 1`,
            [originalId],
          );
          if (sourceGifts.rows.length === 0) {
            await query(
              `UPDATE users SET plan = 'free', plan_expires_at = NULL, updated_at = NOW()
                WHERE id = $1`,
              [originalId],
            );
            // 2.3: cache the source still has plan='premium' until the
            // 10s TTL expires; invalidate so the original owner is
            // demoted on every replica immediately.
            await invalidateUserCache(originalId);
          }
        }
        if (grantsPremium) {
          await query(
            `UPDATE users SET plan = 'premium', plan_expires_at = $1, updated_at = NOW()
              WHERE id = $2`,
            [expiresAt, userId],
          );
          await invalidateUserCache(userId);
        }
        logger.info(
          { newOwnerAppUserId: event.app_user_id, originalAppUserId: originalId },
          'RC TRANSFER applied',
        );
        break;
      }

      case 'SUBSCRIBER_ALIAS': {
        // Bind the alias so a subsequent event addressed to original_app_user_id
        // resolves to the same HavenKeep user (Ch03-F008). We don't have a
        // dedicated alias table; the userId resolution above already checks
        // aliases — so the binding here is to ensure the high-water row for
        // the alias exists and forwards to the same user.
        const original = event.original_app_user_id;
        if (original && UUID_RE.test(original) && original !== userId) {
          // Touch the high-water row for the alias so future out-of-order
          // events to that id are scoped to this user's stream.
          await isEventInOrder('revenuecat', original, event.id, eventCreatedDate);
        }
        logger.info(
          { appUserId: event.app_user_id, aliases: event.aliases, eventType: event.type },
          'RevenueCat subscriber alias bound',
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

    await markWebhookProcessed(event.id, 'revenuecat');
    res.status(200).json({ success: true });
  } catch (err) {
    // Best-effort: mark failed so retries are permitted.
    try {
      const eventId = (req.body as RevenueCatWebhookPayload | undefined)?.event?.id;
      if (eventId) await markWebhookFailed(eventId, 'revenuecat', err);
    } catch {
      /* ignore */
    }
    logger.error({ error: err }, 'Error processing RevenueCat webhook event');
    res.status(500).json({ error: 'Webhook processing failed' });
  }
});

