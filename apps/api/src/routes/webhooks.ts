import { Router, Request, Response, NextFunction } from 'express';
import crypto from 'crypto';
import { config } from '../config';
import { pool, query, getClient } from '../db';
import { logger } from '../utils/logger';
import { invalidateUserCache } from '../middleware/auth';
import { AuditService } from '../services/audit.service';
import { EmailService } from '../services/email.service';

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
  webhookSource: 'revenuecat';
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
 * Per-source ordering guard (Ch03-F009). RevenueCat delivers retries
 * out-of-order. We use an event-stream timestamp + a high-water table so a
 * stale event can't undo a fresher one's effect. Returns true if the caller
 * should proceed (this event is at least as recent as anything we've seen).
 *
 * `subjectId` scopes the order (per-user for RevenueCat events). A
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

export const revenueCatWebhookRouter = Router();

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
        // M-P9 (audit): audit-log PRODUCT_CHANGE plan transitions. The
        // typical free→premium / premium→premium-extended path was
        // missing forensic context.
        if (priorPlan !== 'premium') {
          auditWebhookPlanTransition({
            userId,
            fromPlan: priorPlan,
            toPlan: 'premium',
            webhookSource: 'revenuecat',
            webhookEventId: event.id,
            webhookEventType: event.type,
            reason: `product change to ${event.product_id ?? 'unknown'}`,
          });
        }
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
          // M-P8 (audit): capture the source's prior plan separately so
          // we can audit-log the demotion with accurate from→to.
          const sourcePriorResult = await query(
            `SELECT plan FROM users WHERE id = $1`,
            [originalId],
          );
          const sourcePriorPlan: string | null = sourcePriorResult.rows[0]?.plan ?? null;

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
            // M-P8: audit-log the TRANSFER source-side demotion.
            if (sourcePriorPlan === 'premium') {
              auditWebhookPlanTransition({
                userId: originalId,
                fromPlan: sourcePriorPlan,
                toPlan: 'free',
                webhookSource: 'revenuecat',
                webhookEventId: event.id,
                webhookEventType: 'TRANSFER (source)',
                reason: 'subscription transferred to another account',
              });
            }
          }
        }
        if (grantsPremium) {
          await query(
            `UPDATE users SET plan = 'premium', plan_expires_at = $1, updated_at = NOW()
              WHERE id = $2`,
            [expiresAt, userId],
          );
          await invalidateUserCache(userId);
          // M-P8: audit-log the TRANSFER destination-side upgrade.
          if (priorPlan !== 'premium') {
            auditWebhookPlanTransition({
              userId,
              fromPlan: priorPlan,
              toPlan: 'premium',
              webhookSource: 'revenuecat',
              webhookEventId: event.id,
              webhookEventType: 'TRANSFER (destination)',
              reason: 'subscription transferred from another account',
            });
          }
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

