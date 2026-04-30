import { pool } from '../db';
import { logger } from '../utils/logger';
import { config } from '../config';
import { AppError } from '../utils/errors';
import { EmailService } from './email.service';
import { FcmService } from './fcm.service';

// F035: only these actions can be recorded against a notification — anything
// else gets rejected. Keep the set tight; growth lives in the validator.
const ALLOWED_NOTIFICATION_ACTIONS: ReadonlySet<string> = new Set<string>([
  'opened',
  'dismissed',
  'snoozed',
  'cta_clicked',
  'cta_dismissed',
  'unsubscribed',
]);

/**
 * F033: server-side quiet-hours check. Returns true when `now` falls inside
 * the user's [quiet_start, quiet_end] window in their reported timezone.
 * Wraps over midnight when end < start.
 */
function isInQuietHours(
  now: Date,
  prefs: { quiet_hours_start?: string | null; quiet_hours_end?: string | null; timezone?: string | null },
): boolean {
  const start = prefs.quiet_hours_start;
  const end = prefs.quiet_hours_end;
  if (!start || !end) return false;
  const [sh, sm] = start.split(':').map(Number);
  const [eh, em] = end.split(':').map(Number);
  if (!Number.isFinite(sh) || !Number.isFinite(eh)) return false;

  const tz = prefs.timezone || 'UTC';
  let nowH = now.getUTCHours();
  let nowM = now.getUTCMinutes();
  try {
    const fmt = new Intl.DateTimeFormat('en-US', {
      timeZone: tz, hour: '2-digit', minute: '2-digit', hour12: false,
    });
    const parts = fmt.formatToParts(now);
    nowH = Number(parts.find((p) => p.type === 'hour')?.value ?? nowH);
    nowM = Number(parts.find((p) => p.type === 'minute')?.value ?? nowM);
  } catch {
    // Bad timezone string → fall back to UTC, already initialized.
  }

  const cur = nowH * 60 + nowM;
  const startMin = sh * 60 + (sm || 0);
  const endMin = eh * 60 + (em || 0);
  if (startMin === endMin) return false;
  if (startMin < endMin) {
    return cur >= startMin && cur < endMin;
  }
  // Wraps midnight: e.g. 22:00 → 07:00.
  return cur >= startMin || cur < endMin;
}

/**
 * F037 / F045: day-of-year computed in UTC so a server in a non-UTC zone
 * can't tip the rotation an extra day across DST.
 */
function dayOfYearUTC(d: Date): number {
  const start = Date.UTC(d.getUTCFullYear(), 0, 0);
  const diff = d.getTime() - start;
  return Math.floor(diff / 86_400_000);
}

/**
 * H-B2 (audit): days between two dates, both rounded to UTC midnight.
 * The naive `Math.ceil(deltaMs / 86_400_000)` is wrong by ±1 hour
 * across DST and ±1 day around the boundary; with `Math.ceil` the
 * one-hour delta tips an entire day's count.
 *
 * Both inputs are normalized to UTC year/month/day before subtraction
 * so the result is stable regardless of the server's local TZ.
 */
function daysBetweenUtc(from: Date, to: Date): number {
  const fromUtc = Date.UTC(from.getUTCFullYear(), from.getUTCMonth(), from.getUTCDate());
  const toUtc = Date.UTC(to.getUTCFullYear(), to.getUTCMonth(), to.getUTCDate());
  return Math.round((toUtc - fromUtc) / 86_400_000);
}

/**
 * F034: bucket the current minute into 5-minute slots so digest sends are
 * batched. Used by the cron path to coalesce sub-minute repeated triggers.
 */
function digestBucket(d: Date, bucketMinutes = 5): number {
  return Math.floor((d.getUTCHours() * 60 + d.getUTCMinutes()) / bucketMinutes);
}

type NotificationType =
  | 'warranty_expiring'
  | 'warranty_expired'
  | 'item_added'
  | 'warranty_extended'
  | 'maintenance_due'
  | 'claim_update'
  | 'claim_opportunity'
  | 'health_score_update'
  | 'gift_received'
  | 'gift_activated'
  | 'partner_commission'
  | 'promotional'
  | 'tip'
  | 'system';

interface CreateNotificationData {
  user_id: string;
  template_id?: string;
  item_id?: string;
  gift_id?: string;
  type: NotificationType;
  title: string;
  body: string;
  data?: Record<string, any>;
  platform?: string;
  fcm_message_id?: string;
}

interface NotificationHistoryRow {
  id: string;
  user_id: string;
  template_id: string | null;
  item_id: string | null;
  gift_id: string | null;
  type: NotificationType;
  title: string;
  body: string;
  data: Record<string, any>;
  sent_at: string;
  delivered_at: string | null;
  opened_at: string | null;
  action_taken: string | null;
  action_taken_at: string | null;
  platform: string | null;
  fcm_message_id: string | null;
  created_at: string;
}

export class NotificationsService {
  /**
   * Get notifications for a user with pagination and optional filters.
   *
   * 2.13: optional [homeId] scopes item-bound notifications to a single
   * home. Account-level alerts (no item_id) are always shown.
   */
  static async getUserNotifications(
    userId: string,
    options: {
      limit?: number;
      offset?: number;
      type?: NotificationType;
      unread?: boolean;
      homeId?: string;
    } = {}
  ): Promise<{ notifications: NotificationHistoryRow[]; total: number }> {
    const { limit = 50, offset = 0, type, unread, homeId } = options;

    try {
      // F038: hide rows that FCM/email rejected — the user should never see
      // a notification we couldn't actually deliver. 'pending' + 'delivered'
      // are surfaced; 'failed' + 'skipped' are not.
      //
      // S3-J: hide notifications whose item has since been archived. The
      // join is LEFT so notifications with no item (account-level alerts)
      // are still surfaced — only the rows that *do* point at an item
      // require the item to be active.
      let query = `
        SELECT nh.*,
               nt.name as template_name,
               i.name as item_name
        FROM notification_history nh
        LEFT JOIN notification_templates nt ON nt.id = nh.template_id
        LEFT JOIN items i ON i.id = nh.item_id
        WHERE nh.user_id = $1
          AND nh.delivery_status IN ('pending', 'delivered')
          AND (nh.item_id IS NULL OR i.is_archived = FALSE)
      `;
      const params: any[] = [userId];

      if (type) {
        query += ` AND nh.type = $${params.length + 1}`;
        params.push(type);
      }

      if (unread === true) {
        query += ` AND nh.opened_at IS NULL`;
      } else if (unread === false) {
        query += ` AND nh.opened_at IS NOT NULL`;
      }

      if (homeId) {
        // Account-level alerts (no item_id) bypass the home filter.
        query += ` AND (nh.item_id IS NULL OR i.home_id = $${params.length + 1})`;
        params.push(homeId);
      }

      query += ` ORDER BY nh.sent_at DESC, nh.created_at DESC`;
      query += ` LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
      params.push(limit, offset);

      const result = await pool.query(query, params);

      // 2.10: total count must mirror the LEFT JOIN + archived filter
      // applied above — otherwise pagination.total stays inflated when a
      // user archives an item, the mobile total_pages overshoots, and
      // the user navigates onto empty tail pages.
      let countQuery = `
        SELECT COUNT(*)
          FROM notification_history nh
          LEFT JOIN items i ON i.id = nh.item_id
         WHERE nh.user_id = $1
           AND nh.delivery_status IN ('pending', 'delivered')
           AND (nh.item_id IS NULL OR i.is_archived = FALSE)
      `;
      const countParams: any[] = [userId];

      if (type) {
        countQuery += ` AND nh.type = $${countParams.length + 1}`;
        countParams.push(type);
      }

      if (unread === true) {
        countQuery += ` AND nh.opened_at IS NULL`;
      } else if (unread === false) {
        countQuery += ` AND nh.opened_at IS NOT NULL`;
      }

      if (homeId) {
        countQuery += ` AND (nh.item_id IS NULL OR i.home_id = $${countParams.length + 1})`;
        countParams.push(homeId);
      }

      const countResult = await pool.query(countQuery, countParams);

      return {
        notifications: result.rows,
        total: parseInt(countResult.rows[0].count, 10),
      };
    } catch (error) {
      logger.error({ error, userId, options }, 'Error fetching user notifications');
      throw error;
    }
  }

  /**
   * Get unread notification count for a user
   */
  static async getUnreadCount(userId: string): Promise<number> {
    try {
      // F038: only count notifications that were actually delivered (or are
      // still pending delivery) — failed sends shouldn't dirty the badge.
      const result = await pool.query(
        `SELECT COUNT(*) FROM notification_history
         WHERE user_id = $1
           AND opened_at IS NULL
           AND delivery_status IN ('pending', 'delivered')`,
        [userId]
      );

      return parseInt(result.rows[0].count, 10);
    } catch (error) {
      logger.error({ error, userId }, 'Error fetching unread notification count');
      throw error;
    }
  }

  /**
   * Mark a single notification as read (set opened_at)
   */
  static async markAsRead(notificationId: string, userId: string): Promise<NotificationHistoryRow> {
    try {
      const result = await pool.query(
        `UPDATE notification_history
         SET opened_at = NOW()
         WHERE id = $1 AND user_id = $2 AND opened_at IS NULL
         RETURNING *`,
        [notificationId, userId]
      );

      if (result.rows.length === 0) {
        // Check if notification exists at all
        const existsCheck = await pool.query(
          `SELECT id, opened_at FROM notification_history WHERE id = $1 AND user_id = $2`,
          [notificationId, userId]
        );

        if (existsCheck.rows.length === 0) {
          throw new AppError('Notification not found', 404);
        }

        // Already read, return existing record
        // MED-5: Include user_id in the WHERE clause to enforce ownership
        const existing = await pool.query(
          `SELECT nh.*, nt.name as template_name, i.name as item_name
           FROM notification_history nh
           LEFT JOIN notification_templates nt ON nt.id = nh.template_id
           LEFT JOIN items i ON i.id = nh.item_id
           WHERE nh.id = $1 AND nh.user_id = $2`,
          [notificationId, userId]
        );

        return existing.rows[0];
      }

      logger.info({ notificationId, userId }, 'Notification marked as read');

      // Re-fetch with JOINs for consistent response shape
      const full = await pool.query(
        `SELECT nh.*, nt.name as template_name, i.name as item_name
         FROM notification_history nh
         LEFT JOIN notification_templates nt ON nt.id = nh.template_id
         LEFT JOIN items i ON i.id = nh.item_id
         WHERE nh.id = $1 AND nh.user_id = $2`,
        [notificationId, userId]
      );

      return full.rows[0] || result.rows[0];
    } catch (error) {
      logger.error({ error, notificationId, userId }, 'Error marking notification as read');
      throw error;
    }
  }

  /**
   * Mark all notifications as read for a user.
   *
   * 2.8: bounded to the most-recent MARK_ALL_LIMIT unread rows per call.
   * An unbounded `UPDATE … WHERE user_id = $1 AND opened_at IS NULL`
   * over a 100k-row notification history hangs the route long enough to
   * stall every other write under contention. The mobile UI calls this
   * after a list refresh, so capping at 5k still clears the visible
   * inbox; older rows fall under the 90-day retention sweep anyway.
   */
  static async markAllAsRead(userId: string): Promise<number> {
    const MARK_ALL_LIMIT = 5_000;
    try {
      const result = await pool.query(
        `WITH targets AS (
           SELECT id FROM notification_history
            WHERE user_id = $1 AND opened_at IS NULL
            ORDER BY created_at DESC
            LIMIT $2
         )
         UPDATE notification_history nh
            SET opened_at = NOW()
           FROM targets
          WHERE nh.id = targets.id`,
        [userId, MARK_ALL_LIMIT],
      );

      const count = result.rowCount || 0;

      logger.info({ userId, count }, 'All notifications marked as read');

      return count;
    } catch (error) {
      logger.error({ error, userId }, 'Error marking all notifications as read');
      throw error;
    }
  }

  /**
   * Record a user action on a notification
   */
  static async recordAction(
    notificationId: string,
    userId: string,
    action: string
  ): Promise<NotificationHistoryRow> {
    // F035: enforce the allowlist server-side so a tampered client can't
    // stamp arbitrary `action_taken` strings into the audit/analytics path.
    if (!ALLOWED_NOTIFICATION_ACTIONS.has(action)) {
      throw new AppError(`Unsupported notification action: ${action}`, 400);
    }
    try {
      // Mark as read if not already, and record action
      const result = await pool.query(
        `UPDATE notification_history
         SET action_taken = $3,
             action_taken_at = NOW(),
             opened_at = COALESCE(opened_at, NOW())
         WHERE id = $1 AND user_id = $2
         RETURNING *`,
        [notificationId, userId, action]
      );

      if (result.rows.length === 0) {
        throw new AppError('Notification not found', 404);
      }

      logger.info({ notificationId, userId, action }, 'Notification action recorded');

      return result.rows[0];
    } catch (error) {
      logger.error({ error, notificationId, userId, action }, 'Error recording notification action');
      throw error;
    }
  }

  /**
   * Create a notification directly.
   *
   * F040: respects user notification_preferences. A 'tip' arriving for a
   * user who turned tips off, or a 'claim_opportunity' for one who turned
   * warranty offers off, is recorded with delivery_status='skipped' rather
   * than silently muted (the audit trail is preserved).
   *
   * F034: when the user's prefs carry `digest_minutes > 0`, the notification
   * is parked in `notification_outbox` (mig 072) and coalesced by the
   * cron tick into a single push per user per bucket. The outbox row is
   * the eventual source for the notification_history row written at flush
   * time.
   */
  static async createNotification(data: CreateNotificationData): Promise<NotificationHistoryRow> {
    try {
      const prefsResult = await pool.query(
        `SELECT reminders_enabled, warranty_offers_enabled, tips_enabled, digest_minutes
           FROM notification_preferences WHERE user_id = $1`,
        [data.user_id],
      );
      const prefs = prefsResult.rows[0] || null;

      // Map type → enabled-flag. Defaults to TRUE when prefs row missing
      // (the upsert path defaults reminders_enabled = TRUE).
      const allowed = (() => {
        if (!prefs) return true;
        switch (data.type) {
          case 'tip':                return prefs.tips_enabled !== false;
          case 'claim_opportunity':
          case 'promotional':        return prefs.warranty_offers_enabled !== false;
          case 'maintenance_due':
          case 'warranty_expiring':
          case 'warranty_expired':   return prefs.reminders_enabled !== false;
          default:                   return true;
        }
      })();

      const status = allowed ? 'pending' : 'skipped';

      // F034 digest path: only takes effect when the notification was
      // *allowed* (skipped notifications still go to history immediately so
      // the audit trail isn't deferred) AND the user has a positive
      // digest_minutes. Outbox rows have flush_at = NOW() + digest_minutes;
      // the cron tick coalesces them per-user.
      const digestMinutes = Number(prefs?.digest_minutes ?? 0);
      if (allowed && digestMinutes > 0) {
        await pool.query(
          `INSERT INTO notification_outbox (
             user_id, type, title, body, data, flush_at
           ) VALUES ($1, $2, $3, $4, $5::jsonb, NOW() + ($6 || ' minutes')::interval)`,
          [
            data.user_id,
            data.type,
            data.title,
            data.body,
            JSON.stringify(data.data || {}),
            String(digestMinutes),
          ],
        );
        // Return a synthetic row shape compatible with the call sites that
        // only inspect id + type. Real history row lands at flush time.
        const synthetic = await pool.query(
          `SELECT id, user_id, type, title, body, data, NOW() AS sent_at,
                  'queued'::text AS delivery_status
             FROM notification_outbox
            WHERE user_id = $1
            ORDER BY created_at DESC
            LIMIT 1`,
          [data.user_id],
        );
        logger.info(
          { outboxId: synthetic.rows[0]?.id, userId: data.user_id, type: data.type, digestMinutes },
          'Notification queued for digest flush',
        );
        return synthetic.rows[0];
      }

      const result = await pool.query(
        `INSERT INTO notification_history (
          user_id, template_id, item_id, gift_id, type, title, body,
          data, platform, fcm_message_id, delivery_status, sent_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW())
        RETURNING *`,
        [
          data.user_id,
          data.template_id || null,
          data.item_id || null,
          data.gift_id || null,
          data.type,
          data.title,
          data.body,
          JSON.stringify(data.data || {}),
          data.platform || null,
          data.fcm_message_id || null,
          status,
        ]
      );

      logger.info(
        { notificationId: result.rows[0].id, userId: data.user_id, type: data.type, status },
        'Notification created'
      );

      return result.rows[0];
    } catch (error) {
      logger.error({ error, data }, 'Error creating notification');
      throw error;
    }
  }

  /**
   * F034 cron tick: claim due outbox rows, coalesce per user, write a single
   * notification_history row per user that summarises the batch, and send
   * the FCM push.
   *
   * C2 (audit): the prior implementation inserted notification_history rows
   * with delivery_status='pending' and never sent FCM. Anyone with
   * digest_minutes > 0 saw in-app cards but received zero pushes. We now
   * call FcmService.sendToUser inside the loop and flip delivery_status
   * to 'delivered' / 'failed' based on the result.
   *
   * C3 (audit): the prior CTE filtered on `claimed_at IS NULL OR
   * claimed_at < $1 - INTERVAL '30 seconds'` but the per-user INSERT and
   * the flushed_into_id UPDATE were unconditional, so two replicas could
   * each compute `due` from the same snapshot, both UPDATE the
   * claimed_at, and both insert duplicate notification_history rows.
   * Now we wrap claim+insert in a single transaction with FOR UPDATE
   * SKIP LOCKED at the outbox row level, so only one runner ever sees a
   * given row, and we guard the flushed_into_id UPDATE with
   * `WHERE flushed_into_id IS NULL` defensively.
   *
   * Quiet-hours and push_enabled honored to match the immediate-push paths.
   *
   * Returns the number of users that received a (non-skipped) digest.
   */
  static async flushDigestOutbox(now: Date = new Date()): Promise<number> {
    type Pending = {
      userId: string;
      historyId: string;
      title: string;
      body: string;
      count: number;
    };
    const pendings: Pending[] = [];

    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      // Lock the due-but-unflushed outbox rows; SKIP LOCKED so concurrent
      // replicas don't race on the same rows. Any crash mid-loop rolls
      // back the transaction (no orphan claims) and the next cron tick
      // re-locks the same rows cleanly.
      const lockResult = await client.query(
        `SELECT id, user_id, type, title
           FROM notification_outbox
          WHERE flush_at <= $1
            AND flushed_into_id IS NULL
          ORDER BY flush_at ASC
          LIMIT 500
          FOR UPDATE SKIP LOCKED`,
        [now],
      );
      if (lockResult.rows.length === 0) {
        await client.query('COMMIT');
        return 0;
      }

      // Group by user in JS — at LIMIT 500 this is microseconds.
      type OutboxRow = { id: string; user_id: string; type: string; title: string | null };
      const byUser = new Map<string, OutboxRow[]>();
      for (const row of lockResult.rows as OutboxRow[]) {
        const arr = byUser.get(row.user_id) ?? [];
        arr.push(row);
        byUser.set(row.user_id, arr);
      }

      for (const [userId, rows] of byUser) {
        const count = rows.length;
        const outboxIds = rows.map((r) => r.id);
        const types = Array.from(new Set(rows.map((r) => r.type)));
        const sampleTitle = rows.find((r) => r.title)?.title ?? null;

        const title =
          count === 1 ? (sampleTitle ?? 'You have a new update') : `You have ${count} new updates`;
        const body =
          count === 1 && sampleTitle
            ? sampleTitle
            : `${types.slice(0, 3).join(', ')}${types.length > 3 ? `, +${types.length - 3} more` : ''}`;

        // Reuse 'system' since notification_type enum was kept minimal.
        const inserted = await client.query(
          `INSERT INTO notification_history (
             user_id, type, title, body, data, delivery_status, sent_at
           ) VALUES ($1, 'system', $2, $3, $4::jsonb, 'pending', NOW())
           RETURNING id`,
          [
            userId,
            title,
            body,
            JSON.stringify({ digest: true, count, types, outbox_ids: outboxIds }),
          ],
        );
        const historyId: string = inserted.rows[0].id;

        // Defensive: FOR UPDATE SKIP LOCKED already prevents duplicate
        // writers, but the WHERE flushed_into_id IS NULL guard makes
        // intent explicit + catches a future bug that removes the lock.
        await client.query(
          `UPDATE notification_outbox
              SET flushed_into_id = $1
            WHERE id = ANY($2::uuid[]) AND flushed_into_id IS NULL`,
          [historyId, outboxIds],
        );

        pendings.push({ userId, historyId, title, body, count });
      }

      // Commit the claim BEFORE the FCM round-trip. External IO must not
      // run inside an open transaction (audit Pass 1 H-B4): it pins a
      // pool client and a COMMIT failure after a successful push leaves
      // a phantom notification_history row.
      //
      // Trade-off: a process kill between COMMIT and the FCM send leaves
      // a row with delivery_status='pending' the user sees in-app but
      // never received as a push. Acceptable; the row stays, and a
      // future retention sweep (M-D6) can collect orphan 'pending' rows.
      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      throw err;
    } finally {
      client.release();
    }

    if (pendings.length === 0) return 0;

    // Phase 2: send FCM for each pending batch, honoring push_enabled +
    // quiet_hours just like the immediate-push paths (see warranty
    // expiring at line ~825 of this file).
    const userIds = pendings.map((p) => p.userId);
    const prefsResult = await pool.query(
      `SELECT user_id, COALESCE(push_enabled, TRUE) AS push_enabled
         FROM notification_preferences
        WHERE user_id = ANY($1::uuid[])`,
      [userIds],
    );
    const pushEnabledByUser = new Map<string, boolean>();
    for (const r of prefsResult.rows) pushEnabledByUser.set(r.user_id, r.push_enabled !== false);

    let delivered = 0;
    for (const p of pendings) {
      const pushEnabled = pushEnabledByUser.get(p.userId) ?? true;
      if (!pushEnabled) {
        await pool.query(
          `UPDATE notification_history SET delivery_status = 'failed' WHERE id = $1`,
          [p.historyId],
        );
        continue;
      }
      if (await NotificationsService.isUserInQuietHours(p.userId, now)) {
        // Leave 'pending'; the next cron tick will retry once the user is
        // out of quiet hours. (We don't flip to 'failed' here — that would
        // permanently lose the digest.)
        continue;
      }
      try {
        const sent = await FcmService.sendToUser(p.userId, {
          title: p.title,
          body: p.body,
          data: { type: 'digest', count: String(p.count), history_id: p.historyId },
        });
        if (sent > 0) {
          await pool.query(
            `UPDATE notification_history
                SET delivered_at = NOW(), delivery_status = 'delivered'
              WHERE id = $1`,
            [p.historyId],
          );
          delivered += 1;
        } else {
          // F038 parity: zero live tokens.
          await pool.query(
            `UPDATE notification_history SET delivery_status = 'failed' WHERE id = $1`,
            [p.historyId],
          );
        }
      } catch (fcmError) {
        logger.error(
          { error: fcmError, userId: p.userId, historyId: p.historyId },
          'FCM digest push failed',
        );
        await pool.query(
          `UPDATE notification_history SET delivery_status = 'failed' WHERE id = $1`,
          [p.historyId],
        );
      }
    }

    logger.info(
      { claimed: pendings.length, delivered },
      'Notification digest outbox flushed',
    );
    return delivered;
  }

  /**
   * F033: returns true when the user is currently in their quiet-hours
   * window. Caller should skip push (and optionally email) delivery while
   * this is true. Safe to call without a preferences row — returns false.
   */
  static async isUserInQuietHours(userId: string, now: Date = new Date()): Promise<boolean> {
    const result = await pool.query(
      `SELECT quiet_hours_start, quiet_hours_end, timezone
         FROM notification_preferences WHERE user_id = $1`,
      [userId],
    );
    const row = result.rows[0];
    if (!row) return false;
    return isInQuietHours(now, row);
  }

  /**
   * Create a notification from a template with variable interpolation
   */
  static async createFromTemplate(
    templateName: string,
    userId: string,
    vars: Record<string, string> = {}
  ): Promise<NotificationHistoryRow> {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // Fetch the template
      const templateResult = await client.query(
        `SELECT * FROM notification_templates
         WHERE name = $1 AND is_active = TRUE`,
        [templateName]
      );

      if (templateResult.rows.length === 0) {
        throw new AppError('Notification template not found or inactive', 404);
      }

      const template = templateResult.rows[0];

      // Interpolate variables into title and body
      let title = template.title_template;
      let body = template.body_template;

      // MED-10: Whitelist of allowed variable names to prevent template injection.
      // Only these known variable names can be interpolated into templates.
      const ALLOWED_TEMPLATE_VARS = new Set([
        'userName', 'userEmail', 'fullName',
        'itemName', 'itemBrand', 'itemCategory', 'itemModel',
        'daysRemaining', 'expiryDate', 'warrantyEndDate',
        'claimNumber', 'claimStatus', 'amountSaved',
        'giftSenderName', 'giftMessage',
        'partnerName', 'commissionAmount',
        'planName', 'tipTitle', 'tipBody',
        'item_id', 'gift_id',
      ]);

      for (const [key, value] of Object.entries(vars)) {
        // Only interpolate whitelisted variable names
        if (!ALLOWED_TEMPLATE_VARS.has(key)) {
          logger.warn({ key, templateName }, 'Skipping non-whitelisted template variable');
          continue;
        }
        // Sanitize value to prevent template injection
        const safeValue = String(value).replace(/\{\{/g, '{ {').replace(/\}\}/g, '} }');
        const placeholder = new RegExp(`\\{\\{${key}\\}\\}`, 'g');
        title = title.replace(placeholder, safeValue);
        body = body.replace(placeholder, safeValue);
      }

      // Create the notification
      const result = await client.query(
        `INSERT INTO notification_history (
          user_id, template_id, item_id, gift_id, type, title, body,
          data, sent_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
        RETURNING *`,
        [
          userId,
          template.id,
          vars.item_id || null,
          vars.gift_id || null,
          template.type,
          title,
          body,
          JSON.stringify({ template_name: templateName, vars }),
        ]
      );

      await client.query('COMMIT');

      logger.info(
        { notificationId: result.rows[0].id, userId, templateName },
        'Notification created from template'
      );

      return result.rows[0];
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      logger.error({ error, templateName, userId, vars }, 'Error creating notification from template');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Get notification preferences for a user
   */
  static async getPreferences(userId: string): Promise<Record<string, any> | null> {
    try {
      const result = await pool.query(
        `SELECT * FROM notification_preferences WHERE user_id = $1`,
        [userId]
      );

      return result.rows.length > 0 ? result.rows[0] : null;
    } catch (error) {
      logger.error({ error, userId }, 'Error fetching notification preferences');
      throw error;
    }
  }

  /**
   * Create or update notification preferences for a user
   */
  static async upsertPreferences(
    userId: string,
    prefs: Record<string, any>
  ): Promise<Record<string, any>> {
    try {
      const result = await pool.query(
        `INSERT INTO notification_preferences (user_id, reminders_enabled, first_reminder_days, reminder_time, warranty_offers_enabled, tips_enabled, push_enabled, email_enabled)
         VALUES ($1, COALESCE($2, TRUE), COALESCE($3, 30), COALESCE($4, '09:00'), COALESCE($5, TRUE), COALESCE($6, TRUE), COALESCE($7, TRUE), COALESCE($8, FALSE))
         ON CONFLICT (user_id)
         DO UPDATE SET
           reminders_enabled = COALESCE($2, notification_preferences.reminders_enabled),
           first_reminder_days = COALESCE($3, notification_preferences.first_reminder_days),
           reminder_time = COALESCE($4, notification_preferences.reminder_time),
           warranty_offers_enabled = COALESCE($5, notification_preferences.warranty_offers_enabled),
           tips_enabled = COALESCE($6, notification_preferences.tips_enabled),
           push_enabled = COALESCE($7, notification_preferences.push_enabled),
           email_enabled = COALESCE($8, notification_preferences.email_enabled)
         RETURNING *`,
        [
          userId,
          prefs.remindersEnabled !== undefined ? prefs.remindersEnabled : null,
          prefs.firstReminderDays !== undefined ? prefs.firstReminderDays : null,
          prefs.reminderTime !== undefined ? prefs.reminderTime : null,
          prefs.warrantyOffersEnabled !== undefined ? prefs.warrantyOffersEnabled : null,
          prefs.tipsEnabled !== undefined ? prefs.tipsEnabled : null,
          prefs.pushEnabled !== undefined ? prefs.pushEnabled : null,
          prefs.emailEnabled !== undefined ? prefs.emailEnabled : null,
        ]
      );

      logger.info({ userId }, 'Notification preferences updated');

      return result.rows[0];
    } catch (error) {
      logger.error({ error, userId }, 'Error upserting notification preferences');
      throw error;
    }
  }

  /**
   * Delete a notification
   */
  static async deleteNotification(notificationId: string, userId: string): Promise<void> {
    try {
      const result = await pool.query(
        `DELETE FROM notification_history
         WHERE id = $1 AND user_id = $2`,
        [notificationId, userId]
      );

      if (result.rowCount === 0) {
        throw new AppError('Notification not found', 404);
      }

      logger.info({ notificationId, userId }, 'Notification deleted');
    } catch (error) {
      logger.error({ error, notificationId, userId }, 'Error deleting notification');
      throw error;
    }
  }

  /**
   * Check for items with expiring warranties and create notifications.
   *
   * Scheduled daily by the API process (see index.ts).
   * Checks for items expiring within each user's configured reminder window
   * and creates notifications for them. Skips items that already received
   * a notification in the last 24 hours to prevent duplicates.
   *
   * Idempotency: The 24-hour dedup window (nh.sent_at > NOW() - INTERVAL '1 day')
   * ensures that re-running this method within the same day is safe and will not
   * produce duplicate notifications for the same item.
   *
   * Individual notification failures are caught and logged so that one bad row
   * does not prevent notifications for remaining items.
   */
  static async checkAndNotifyExpirations(): Promise<number> {
    const client = await pool.connect();
    try {
      // Find items expiring within each user's first_reminder_days window
      // that haven't already been notified in the last 24 hours
      const result = await client.query(`
        SELECT i.id as item_id, i.name as item_name, i.brand,
               i.warranty_end_date, i.user_id,
               u.email, u.full_name,
               COALESCE(np.first_reminder_days, 30) as reminder_days,
               COALESCE(np.email_enabled, FALSE) as email_enabled,
               COALESCE(np.push_enabled, TRUE) as push_enabled
        FROM items i
        JOIN users u ON u.id = i.user_id
        LEFT JOIN notification_preferences np ON np.user_id = u.id
        WHERE i.is_archived = FALSE
          AND i.warranty_end_date BETWEEN (NOW() AT TIME ZONE 'UTC')::date
            AND (NOW() AT TIME ZONE 'UTC')::date + make_interval(days => COALESCE(np.first_reminder_days, 30))
          AND NOT EXISTS (
            SELECT 1 FROM notification_history nh
            WHERE nh.item_id = i.id
              AND nh.type = 'warranty_expiring'
              AND nh.sent_at > NOW() - INTERVAL '1 day'
          )
      `);

      let notifiedCount = 0;
      for (const row of result.rows) {
        try {
          const itemLabel = row.brand ? `${row.brand} ${row.item_name}` : row.item_name;
          // Format date in UTC to avoid timezone off-by-one from DB DATE column
          const d = new Date(row.warranty_end_date);
          const expiryDate = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;

          const notification = await NotificationsService.createNotification({
            user_id: row.user_id,
            item_id: row.item_id,
            type: 'warranty_expiring',
            title: 'Warranty Expiring Soon',
            body: `Your warranty for ${itemLabel} expires on ${expiryDate}.`,
          });

          // Send FCM push notification (only if push enabled AND not in
          // quiet hours — F033). Notification row stays in 'pending'
          // delivery_status when we skip; the cron re-runs daily and the
          // NOT EXISTS dedup keeps it from re-emitting within 24h.
          if (row.push_enabled !== false && !(await NotificationsService.isUserInQuietHours(row.user_id))) {
            try {
              const sent = await FcmService.sendToUser(row.user_id, {
                title: 'Warranty Expiring Soon',
                body: `Your warranty for ${itemLabel} expires on ${expiryDate}.`,
                data: { type: 'warranty_expiring', item_id: row.item_id },
              });
              if (sent > 0) {
                await pool.query(
                  `UPDATE notification_history
                      SET delivered_at = NOW(), delivery_status = 'delivered'
                    WHERE id = $1`,
                  [notification.id]
                );
              } else {
                // F038: zero successes = no live tokens; tag as failed so
                // the user doesn't see an "undelivered" notification.
                await pool.query(
                  `UPDATE notification_history SET delivery_status = 'failed' WHERE id = $1`,
                  [notification.id]
                );
              }
            } catch (fcmError) {
              logger.error({ error: fcmError, userId: row.user_id }, 'FCM push failed (warranty_expiring)');
              await pool.query(
                `UPDATE notification_history SET delivery_status = 'failed' WHERE id = $1`,
                [notification.id]
              );
            }
          }

          // Send email if user has email notifications enabled
          if (row.email_enabled) {
            try {
              // H-B2: UTC-aware day-count. The prior shape divided ms by
              // 86_400_000 and Math.ceil'd, which tips an entire day on
              // DST transition or a non-UTC server.
              const daysRemaining = daysBetweenUtc(
                new Date(),
                new Date(row.warranty_end_date),
              );
              await EmailService.sendWarrantyExpirationEmail({
                to: row.email,
                user_name: row.full_name || 'there',
                item_name: row.item_name,
                brand: row.brand,
                expiry_date: expiryDate,
                days_remaining: Math.max(daysRemaining, 0),
                item_id: row.item_id,
              });
            } catch (emailError) {
              logger.error({ error: emailError, itemId: row.item_id, userId: row.user_id }, 'Failed to send expiration email (notification still created)');
            }
          }

          notifiedCount++;
        } catch (itemError) {
          logger.error({ error: itemError, itemId: row.item_id }, 'Failed to send expiration notification');
        }
      }

      logger.info({ count: notifiedCount }, 'Expiration notifications sent');
      return notifiedCount;
    } finally {
      client.release();
    }
  }

  /**
   * Check for items with maintenance tasks due and create notifications.
   *
   * Scheduled daily alongside the warranty expiration job.
   * For each active item with matching maintenance schedules, we find tasks
   * where the last completion date + frequency is on or before today.
   * Items that have never had a task logged are notified if the item's
   * purchase_date + frequency is on or before today.
   *
   * Idempotency: The 7-day dedup window prevents re-sending the same
   * maintenance_due notification for the same item+task within a week.
   */
  static async checkAndNotifyMaintenanceDue(): Promise<number> {
    const client = await pool.connect();
    try {
      // Find maintenance tasks that are due:
      // - Join items → maintenance_schedules (by category)
      // - Left join most-recent maintenance_history entry (per item+schedule)
      // - Due when: last_completed + frequency_months <= today (or never done and purchase_date + frequency_months <= today)
      // - Dedup: skip if a maintenance_due notification for this item was sent in the last 7 days
      const result = await client.query(`
        SELECT
          i.id              AS item_id,
          i.name            AS item_name,
          i.brand,
          i.user_id,
          u.email,
          u.full_name,
          ms.id             AS schedule_id,
          ms.task_name,
          ms.frequency_months,
          COALESCE(last_done.completed_date, i.purchase_date::DATE) AS reference_date,
          COALESCE(np.push_enabled, TRUE) AS push_enabled,
          COALESCE(np.email_enabled, FALSE) AS email_enabled
        FROM items i
        JOIN users u ON u.id = i.user_id
        JOIN maintenance_schedules ms ON ms.category = i.category
        LEFT JOIN LATERAL (
          SELECT completed_date
          FROM maintenance_history mh
          WHERE mh.item_id = i.id
            AND mh.schedule_id = ms.id
            AND mh.user_id = i.user_id
          ORDER BY completed_date DESC
          LIMIT 1
        ) last_done ON TRUE
        LEFT JOIN notification_preferences np ON np.user_id = i.user_id
        WHERE i.is_archived = FALSE
          AND i.purchase_date IS NOT NULL
          AND (COALESCE(last_done.completed_date, i.purchase_date::DATE) + make_interval(months => ms.frequency_months)) <= (NOW() AT TIME ZONE 'UTC')::date
          AND NOT EXISTS (
            SELECT 1
            FROM notification_history nh
            WHERE nh.item_id = i.id
              AND nh.type = 'maintenance_due'
              AND (nh.data->>'schedule_id') = ms.id::text
              AND nh.sent_at > NOW() - INTERVAL '7 days'
          )
        ORDER BY i.user_id, i.id
      `);

      let notifiedCount = 0;
      for (const row of result.rows) {
        try {
          const itemLabel = row.brand ? `${row.brand} ${row.item_name}` : row.item_name;
          const notification = await NotificationsService.createNotification({
            user_id: row.user_id,
            item_id: row.item_id,
            type: 'maintenance_due',
            title: 'Maintenance Due',
            body: `Time to: ${row.task_name} for your ${itemLabel}.`,
            data: { schedule_id: row.schedule_id, task_name: row.task_name },
          });

          // F033: skip push during quiet hours; F038: tag delivery_status.
          if (row.push_enabled !== false && !(await NotificationsService.isUserInQuietHours(row.user_id))) {
            try {
              const sent = await FcmService.sendToUser(row.user_id, {
                title: 'Maintenance Due',
                body: `Time to: ${row.task_name} for your ${itemLabel}.`,
                data: { type: 'maintenance_due', item_id: row.item_id, schedule_id: row.schedule_id },
              });
              if (sent > 0) {
                await pool.query(
                  `UPDATE notification_history
                      SET delivered_at = NOW(), delivery_status = 'delivered'
                    WHERE id = $1`,
                  [notification.id]
                );
              } else {
                await pool.query(
                  `UPDATE notification_history SET delivery_status = 'failed' WHERE id = $1`,
                  [notification.id]
                );
              }
            } catch (fcmError) {
              logger.error({ error: fcmError, userId: row.user_id }, 'FCM push failed (maintenance_due)');
              await pool.query(
                `UPDATE notification_history SET delivery_status = 'failed' WHERE id = $1`,
                [notification.id]
              );
            }
          }

          // Send email if user has email notifications enabled
          if (row.email_enabled) {
            try {
              const itemUrl = `${config.app.frontendUrl}/items/${row.item_id}`;
              await EmailService.sendMaintenanceDueEmail({
                to: row.email,
                user_name: row.full_name || 'there',
                item_name: itemLabel,
                task_name: row.task_name,
                item_url: itemUrl,
              });
            } catch (emailError) {
              logger.error({ error: emailError, itemId: row.item_id, userId: row.user_id }, 'Failed to send maintenance due email (notification still created)');
            }
          }

          notifiedCount++;
        } catch (itemError) {
          logger.error(
            { error: itemError, itemId: row.item_id, taskName: row.task_name },
            'Failed to send maintenance_due notification'
          );
        }
      }

      logger.info({ count: notifiedCount }, 'Maintenance due notifications sent');
      return notifiedCount;
    } finally {
      client.release();
    }
  }

  /**
   * Check for items with expired manufacturer warranties that qualify for
   * extended warranty offers, and create claim_opportunity notifications.
   *
   * Scheduled daily alongside other notification jobs.
   * Only targets items valued above $200 that do not already have an active
   * extended warranty purchase, and limits to 3 notifications per batch per user
   * to avoid overwhelming them.
   *
   * Idempotency: The 30-day dedup window prevents re-sending a claim_opportunity
   * notification for the same item within that period.
   */
  static async checkAndNotifyWarrantyOffers(): Promise<number> {
    const client = await pool.connect();
    try {
      // Find high-value items where manufacturer warranty has expired,
      // no active extended warranty purchase exists, and no claim_opportunity
      // notification was sent for this item in the last 30 days.
      // Use ROW_NUMBER() to limit to 3 items per user per batch.
      const result = await client.query(`
        WITH eligible_items AS (
          SELECT
            i.id              AS item_id,
            i.name            AS item_name,
            i.brand,
            i.price,
            i.user_id,
            u.email,
            u.full_name,
            COALESCE(np.push_enabled, TRUE) AS push_enabled,
            COALESCE(np.email_enabled, FALSE) AS email_enabled,
            COALESCE(np.warranty_offers_enabled, TRUE) AS warranty_offers_enabled,
            ROW_NUMBER() OVER (PARTITION BY i.user_id ORDER BY i.price DESC) AS rn
          FROM items i
          JOIN users u ON u.id = i.user_id
          LEFT JOIN notification_preferences np ON np.user_id = u.id
          WHERE i.is_archived = FALSE
            AND i.warranty_end_date < (NOW() AT TIME ZONE 'UTC')::date
            AND i.price > 200
            AND NOT EXISTS (
              SELECT 1 FROM warranty_purchases wp
              WHERE wp.item_id = i.id
                AND wp.status = 'active'
            )
            AND NOT EXISTS (
              SELECT 1 FROM notification_history nh
              WHERE nh.item_id = i.id
                AND nh.type = 'claim_opportunity'
                AND nh.sent_at > NOW() - INTERVAL '30 days'
            )
        )
        SELECT * FROM eligible_items
        WHERE rn <= 3
          AND warranty_offers_enabled = TRUE
        ORDER BY user_id, rn
      `);

      let notifiedCount = 0;
      for (const row of result.rows) {
        try {
          const notification = await NotificationsService.createNotification({
            user_id: row.user_id,
            item_id: row.item_id,
            type: 'claim_opportunity',
            title: `Protect your ${row.item_name}`,
            body: 'Your manufacturer warranty has expired. Consider extended protection.',
            data: { price: row.price, brand: row.brand },
          });

          // F033: respect quiet hours; F038: persist delivery_status.
          if (row.push_enabled !== false && !(await NotificationsService.isUserInQuietHours(row.user_id))) {
            try {
              const sent = await FcmService.sendToUser(row.user_id, {
                title: `Protect your ${row.item_name}`,
                body: 'Your manufacturer warranty has expired. Consider extended protection.',
                data: { type: 'claim_opportunity', item_id: row.item_id },
              });
              if (sent > 0) {
                await pool.query(
                  `UPDATE notification_history
                      SET delivered_at = NOW(), delivery_status = 'delivered'
                    WHERE id = $1`,
                  [notification.id]
                );
              } else {
                await pool.query(
                  `UPDATE notification_history SET delivery_status = 'failed' WHERE id = $1`,
                  [notification.id]
                );
              }
            } catch (fcmError) {
              logger.error({ error: fcmError, userId: row.user_id }, 'FCM push failed (claim_opportunity)');
              await pool.query(
                `UPDATE notification_history SET delivery_status = 'failed' WHERE id = $1`,
                [notification.id]
              );
            }
          }

          // Send email if user has email notifications enabled
          if (row.email_enabled === true && row.email) {
            try {
              await EmailService.sendWarrantyExpirationEmail({
                to: row.email,
                user_name: row.full_name,
                item_name: row.item_name,
                brand: row.brand,
                expiry_date: 'Expired',
                days_remaining: 0,
                item_id: row.item_id,
              });
            } catch (emailError) {
              logger.error({ error: emailError, userId: row.user_id }, 'Email send failed (claim_opportunity)');
            }
          }

          notifiedCount++;
        } catch (itemError) {
          logger.error(
            { error: itemError, itemId: row.item_id },
            'Failed to send claim_opportunity notification'
          );
        }
      }

      logger.info({ count: notifiedCount }, 'Warranty offer notifications sent');
      return notifiedCount;
    } finally {
      client.release();
    }
  }
}
