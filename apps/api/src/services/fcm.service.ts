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
}

export class FcmService {
  /**
   * Send a push notification to all FCM tokens registered for a user.
   * Silently ignores invalid/expired tokens (removes them from DB).
   * Returns the number of successful deliveries.
   */
  static async sendToUser(userId: string, payload: FcmPayload): Promise<number> {
    const app = getFirebaseApp();
    if (!app) return 0;

    const messaging = admin.messaging(app);

    // Fetch all tokens for the user
    const result = await pool.query(
      `SELECT fcm_token, platform FROM user_push_tokens WHERE user_id = $1`,
      [userId]
    );

    if (result.rows.length === 0) return 0;

    const tokens: string[] = result.rows.map((r: any) => r.fcm_token);
    const tokensToRemove: string[] = [];
    let successCount = 0;

    // Send to each token individually so we can handle per-token errors
    await Promise.all(
      tokens.map(async (token) => {
        try {
          await messaging.send({
            token,
            notification: {
              title: payload.title,
              body: payload.body,
            },
            data: payload.data,
            apns: {
              payload: {
                aps: {
                  sound: 'default',
                  badge: 1,
                },
              },
            },
            android: {
              notification: {
                sound: 'default',
                clickAction: 'FLUTTER_NOTIFICATION_CLICK',
              },
            },
          });
          successCount++;
        } catch (err: any) {
          // Remove stale tokens from DB
          if (
            err.code === 'messaging/invalid-registration-token' ||
            err.code === 'messaging/registration-token-not-registered'
          ) {
            tokensToRemove.push(token);
          } else {
            logger.error(
              { err, userId, token: token.substring(0, 20) + '...' },
              'FCM send error'
            );
          }
        }
      })
    );

    // Clean up stale tokens
    if (tokensToRemove.length > 0) {
      await pool.query(
        `DELETE FROM user_push_tokens WHERE user_id = $1 AND fcm_token = ANY($2)`,
        [userId, tokensToRemove]
      );
      logger.info(
        { userId, removed: tokensToRemove.length },
        'Removed stale FCM tokens'
      );
    }

    return successCount;
  }

  /**
   * Check if FCM is available (Firebase config is set).
   */
  static isAvailable(): boolean {
    return getFirebaseApp() !== null;
  }
}
