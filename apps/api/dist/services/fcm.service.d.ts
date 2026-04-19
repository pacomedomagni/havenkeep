export interface FcmPayload {
    title: string;
    body: string;
    data?: Record<string, string>;
}
export declare class FcmService {
    /**
     * Send a push notification to all FCM tokens registered for a user.
     * Silently ignores invalid/expired tokens (removes them from DB).
     * Returns the number of successful deliveries.
     */
    static sendToUser(userId: string, payload: FcmPayload): Promise<number>;
    /**
     * Check if FCM is available (Firebase config is set).
     */
    static isAvailable(): boolean;
}
//# sourceMappingURL=fcm.service.d.ts.map