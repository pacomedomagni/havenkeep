"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.FcmService = void 0;
const admin = __importStar(require("firebase-admin"));
const db_1 = require("../db");
const config_1 = require("../config");
const logger_1 = require("../utils/logger");
let _app = null;
let _initialized = false;
function getFirebaseApp() {
    if (_initialized)
        return _app;
    _initialized = true;
    const json = config_1.config.firebase.serviceAccountJson;
    if (!json) {
        logger_1.logger.warn('FIREBASE_SERVICE_ACCOUNT_JSON is not set — FCM push delivery disabled');
        return null;
    }
    try {
        const serviceAccount = JSON.parse(json);
        _app = admin.initializeApp({
            credential: admin.credential.cert(serviceAccount),
        });
        logger_1.logger.info('Firebase Admin SDK initialized');
        return _app;
    }
    catch (err) {
        logger_1.logger.error({ err }, 'Failed to initialize Firebase Admin SDK — FCM disabled');
        return null;
    }
}
class FcmService {
    /**
     * Send a push notification to all FCM tokens registered for a user.
     * Silently ignores invalid/expired tokens (removes them from DB).
     * Returns the number of successful deliveries.
     */
    static async sendToUser(userId, payload) {
        const app = getFirebaseApp();
        if (!app)
            return 0;
        const messaging = admin.messaging(app);
        // Fetch all tokens for the user
        const result = await db_1.pool.query(`SELECT fcm_token, platform FROM user_push_tokens WHERE user_id = $1`, [userId]);
        if (result.rows.length === 0)
            return 0;
        const tokens = result.rows.map((r) => r.fcm_token);
        const tokensToRemove = [];
        let successCount = 0;
        // Send to each token individually so we can handle per-token errors
        await Promise.all(tokens.map(async (token) => {
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
            }
            catch (err) {
                // Remove stale tokens from DB
                if (err.code === 'messaging/invalid-registration-token' ||
                    err.code === 'messaging/registration-token-not-registered') {
                    tokensToRemove.push(token);
                }
                else {
                    logger_1.logger.error({ err, userId, token: token.substring(0, 20) + '...' }, 'FCM send error');
                }
            }
        }));
        // Clean up stale tokens
        if (tokensToRemove.length > 0) {
            await db_1.pool.query(`DELETE FROM user_push_tokens WHERE user_id = $1 AND fcm_token = ANY($2)`, [userId, tokensToRemove]);
            logger_1.logger.info({ userId, removed: tokensToRemove.length }, 'Removed stale FCM tokens');
        }
        return successCount;
    }
    /**
     * Check if FCM is available (Firebase config is set).
     */
    static isAvailable() {
        return getFirebaseApp() !== null;
    }
}
exports.FcmService = FcmService;
//# sourceMappingURL=fcm.service.js.map