import * as admin from 'firebase-admin';
import { pool } from '../db';
import { config } from '../config';
import { logger } from '../utils/logger';

let _app: admin.app.App | null = null;
let _initialized = false;

function getFirebaseApp(): admin.app.App | null {
  if (_initialized) return _app;
  _initialized = true;

  const json = config.firebase.serviceAccountJson;
  if (!json) {
    logger.warn('FIREBASE_SERVICE_ACCOUNT_JSON is not set — FCM push delivery disabled');
    return null;
  }

  try {
    const serviceAccount = JSON.parse(json);
    _app = admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    logger.info('Firebase Admin SDK initialized');
    return _app;
  } catch (err) {
    logger.error({ err }, 'Failed to initialize Firebase Admin SDK — FCM disabled');
    return null;
  }
}

export interface FcmPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
  // F074: optional override; default 'havenkeep_default' channel which the
  // mobile client registers in MainActivity. Channel must exist on Android
  // 8+ for the OS to render the notification at all.
  androidChannelId?: string;
}

/**
 * F076: FCM error codes we treat as "this token is dead, drop it".
 *
 * C0-30: `messaging/invalid-argument` is intentionally NOT in this set.
 * Firebase overloads it for two very different failures: malformed
 * token OR malformed PAYLOAD. The prior shape treated both as "token
 * is bad" and deleted the row, so a single payload-too-large bug in
 * a notification template would silently delete every user's push
 * tokens on the next send. Surface invalid-argument as transient and
 * leave the token alone; the operator sees the spike and fixes the
 * template.
 */
const DEAD_TOKEN_CODES: ReadonlySet<string> = new Set<string>([
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered',
  'messaging/sender-id-mismatch',
]);

/** F076: codes that we should back off on but NOT drop the token. */
const TRANSIENT_CODES: ReadonlySet<string> = new Set<string>([
  'messaging/quota-exceeded',
  'messaging/server-unavailable',
  'messaging/internal-error',
  // C0-30: see comment above DEAD_TOKEN_CODES.
  'messaging/invalid-argument',
]);

/** F072: Firebase sendEachForMulticast caps per-call at 500 tokens. */
const MULTICAST_BATCH_SIZE = 500;

export class FcmService {
  /**
   * Send a push notification to all FCM tokens registered for a user.
   *
   * F072: tokens are batched into groups of 500 so a user with >500
   * registered devices doesn't hit the per-call cap.
   * F074: Android payload sets `channelId` + `priority='high'` so the OS
   * renders the notification on Android 8+ devices and treats it as a
   * user-visible (heads-up) push.
   * F076: dead tokens are deleted; transient (quota/internal) errors are
   * logged but the token is left in place for the next attempt.
   * F079: tokens that successfully delivered have `last_seen_at` bumped so
   * the cleanup job can purge anything older than 60 days.
   */
  static async sendToUser(userId: string, payload: FcmPayload): Promise<number> {
    const app = getFirebaseApp();
    if (!app) return 0;

    const messaging = admin.messaging(app);

    // Fetch all tokens for the user
    const result = await pool.query(
      `SELECT fcm_token FROM user_push_tokens WHERE user_id = $1`,
      [userId]
    );

    if (result.rows.length === 0) return 0;

    const tokens: string[] = result.rows.map((r: any) => r.fcm_token);
    const channelId = payload.androidChannelId || 'havenkeep_default';

    const message = (token: string): admin.messaging.Message => ({
      token,
      notification: { title: payload.title, body: payload.body },
      data: payload.data,
      apns: {
        payload: { aps: { sound: 'default', badge: 1 } },
      },
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId,
          clickAction: 'FLUTTER_NOTIFICATION_CLICK',
        },
      },
    });

    const tokensToRemove: string[] = [];
    const tokensDelivered: string[] = [];
    let successCount = 0;

    // F072: batch sends. Each batch is `sendAll`ed in parallel so a single
    // dead token doesn't poison the whole batch.
    for (let i = 0; i < tokens.length; i += MULTICAST_BATCH_SIZE) {
      const batch = tokens.slice(i, i + MULTICAST_BATCH_SIZE);
      const responses = await messaging.sendEach(batch.map(message));
      responses.responses.forEach((resp, idx) => {
        const token = batch[idx];
        if (resp.success) {
          successCount++;
          tokensDelivered.push(token);
          return;
        }
        const code = resp.error?.code;
        if (code && DEAD_TOKEN_CODES.has(code)) {
          tokensToRemove.push(token);
        } else if (code && TRANSIENT_CODES.has(code)) {
          logger.warn(
            { code, userId, token: token.substring(0, 20) + '...' },
            'FCM transient error — token retained',
          );
        } else {
          logger.error(
            { code, err: resp.error, userId, token: token.substring(0, 20) + '...' },
            'FCM send error',
          );
        }
      });
    }

    // Clean up dead tokens
    if (tokensToRemove.length > 0) {
      await pool.query(
        `DELETE FROM user_push_tokens WHERE user_id = $1 AND fcm_token = ANY($2)`,
        [userId, tokensToRemove]
      );
      logger.info(
        { userId, removed: tokensToRemove.length },
        'Removed dead FCM tokens',
      );
    }

    // F079: bump last_seen_at on tokens that just delivered so the cleanup
    // job leaves them alone.
    if (tokensDelivered.length > 0) {
      await pool.query(
        `UPDATE user_push_tokens
            SET last_seen_at = NOW()
          WHERE user_id = $1 AND fcm_token = ANY($2)`,
        [userId, tokensDelivered],
      );
    }

    return successCount;
  }

  /**
   * F079: cleanup tokens that haven't been seen for `staleDays`. Called by
   * the daily maintenance cron alongside expireOverdueWarranties.
   */
  static async cleanupStaleTokens(staleDays = 60): Promise<number> {
    const result = await pool.query(
      `DELETE FROM user_push_tokens
        WHERE last_seen_at < NOW() - ($1 || ' days')::interval
        RETURNING id`,
      [String(staleDays)],
    );
    const count = result.rowCount ?? 0;
    if (count > 0) {
      logger.info({ count, staleDays }, 'Cleaned up stale FCM tokens');
    }
    return count;
  }

  /**
   * Check if FCM is available (Firebase config is set).
   */
  static isAvailable(): boolean {
    return getFirebaseApp() !== null;
  }
}
