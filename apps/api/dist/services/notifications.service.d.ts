type NotificationType = 'warranty_expiring' | 'warranty_expired' | 'item_added' | 'warranty_extended' | 'maintenance_due' | 'claim_update' | 'claim_opportunity' | 'health_score_update' | 'gift_received' | 'gift_activated' | 'partner_commission' | 'promotional' | 'tip' | 'system';
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
export declare class NotificationsService {
    /**
     * Get notifications for a user with pagination and optional filters
     */
    static getUserNotifications(userId: string, options?: {
        limit?: number;
        offset?: number;
        type?: NotificationType;
        unread?: boolean;
    }): Promise<{
        notifications: NotificationHistoryRow[];
        total: number;
    }>;
    /**
     * Get unread notification count for a user
     */
    static getUnreadCount(userId: string): Promise<number>;
    /**
     * Mark a single notification as read (set opened_at)
     */
    static markAsRead(notificationId: string, userId: string): Promise<NotificationHistoryRow>;
    /**
     * Mark all notifications as read for a user
     */
    static markAllAsRead(userId: string): Promise<number>;
    /**
     * Record a user action on a notification
     */
    static recordAction(notificationId: string, userId: string, action: string): Promise<NotificationHistoryRow>;
    /**
     * Create a notification directly
     */
    static createNotification(data: CreateNotificationData): Promise<NotificationHistoryRow>;
    /**
     * Create a notification from a template with variable interpolation
     */
    static createFromTemplate(templateName: string, userId: string, vars?: Record<string, string>): Promise<NotificationHistoryRow>;
    /**
     * Get notification preferences for a user
     */
    static getPreferences(userId: string): Promise<Record<string, any> | null>;
    /**
     * Create or update notification preferences for a user
     */
    static upsertPreferences(userId: string, prefs: Record<string, any>): Promise<Record<string, any>>;
    /**
     * Delete a notification
     */
    static deleteNotification(notificationId: string, userId: string): Promise<void>;
    /**
     * Check for items with expiring warranties and create notifications.
     *
     * Scheduled daily by the API process (see index.ts).
     * Checks for items expiring within each user's configured reminder window
     * and creates notifications for them. Skips items that already received
     * a notification in the last 24 hours to prevent duplicates.
     */
    static checkAndNotifyExpirations(): Promise<number>;
}
export {};
//# sourceMappingURL=notifications.service.d.ts.map