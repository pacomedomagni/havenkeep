import { pool } from '../db';
import { logger } from '../utils/logger';
import { AppError } from '../utils/errors';
import { EmailService } from './email.service';

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
   * Get notifications for a user with pagination and optional filters
   */
  static async getUserNotifications(
    userId: string,
    options: {
      limit?: number;
      offset?: number;
      type?: NotificationType;
      unread?: boolean;
    } = {}
  ): Promise<{ notifications: NotificationHistoryRow[]; total: number }> {
    const { limit = 50, offset = 0, type, unread } = options;

    try {
      let query = `
        SELECT nh.*,
               nt.name as template_name,
               i.name as item_name
        FROM notification_history nh
        LEFT JOIN notification_templates nt ON nt.id = nh.template_id
        LEFT JOIN items i ON i.id = nh.item_id
        WHERE nh.user_id = $1
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

      query += ` ORDER BY nh.sent_at DESC, nh.created_at DESC`;
      query += ` LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
      params.push(limit, offset);

      const result = await pool.query(query, params);

      // Get total count with same filters
      let countQuery = `SELECT COUNT(*) FROM notification_history WHERE user_id = $1`;
      const countParams: any[] = [userId];

      if (type) {
        countQuery += ` AND type = $${countParams.length + 1}`;
        countParams.push(type);
      }

      if (unread === true) {
        countQuery += ` AND opened_at IS NULL`;
      } else if (unread === false) {
        countQuery += ` AND opened_at IS NOT NULL`;
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
      const result = await pool.query(
        `SELECT COUNT(*) FROM notification_history
         WHERE user_id = $1 AND opened_at IS NULL`,
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
        const existing = await pool.query(
          `SELECT nh.*, nt.name as template_name, i.name as item_name
           FROM notification_history nh
           LEFT JOIN notification_templates nt ON nt.id = nh.template_id
           LEFT JOIN items i ON i.id = nh.item_id
           WHERE nh.id = $1`,
          [notificationId]
        );

        return existing.rows[0];
      }

      logger.info({ notificationId, userId }, 'Notification marked as read');

      return result.rows[0];
    } catch (error) {
      logger.error({ error, notificationId, userId }, 'Error marking notification as read');
      throw error;
    }
  }

  /**
   * Mark all notifications as read for a user
   */
  static async markAllAsRead(userId: string): Promise<number> {
    try {
      const result = await pool.query(
        `UPDATE notification_history
         SET opened_at = NOW()
         WHERE user_id = $1 AND opened_at IS NULL`,
        [userId]
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
   * Create a notification directly
   */
  static async createNotification(data: CreateNotificationData): Promise<NotificationHistoryRow> {
    try {
      const result = await pool.query(
        `INSERT INTO notification_history (
          user_id, template_id, item_id, gift_id, type, title, body,
          data, platform, fcm_message_id, sent_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW())
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
        ]
      );

      logger.info(
        { notificationId: result.rows[0].id, userId: data.user_id, type: data.type },
        'Notification created'
      );

      return result.rows[0];
    } catch (error) {
      logger.error({ error, data }, 'Error creating notification');
      throw error;
    }
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

      for (const [key, value] of Object.entries(vars)) {
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
      await client.query('ROLLBACK');
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
          prefs.reminders_enabled !== undefined ? prefs.reminders_enabled : null,
          prefs.first_reminder_days !== undefined ? prefs.first_reminder_days : null,
          prefs.reminder_time !== undefined ? prefs.reminder_time : null,
          prefs.warranty_offers_enabled !== undefined ? prefs.warranty_offers_enabled : null,
          prefs.tips_enabled !== undefined ? prefs.tips_enabled : null,
          prefs.push_enabled !== undefined ? prefs.push_enabled : null,
          prefs.email_enabled !== undefined ? prefs.email_enabled : null,
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
               COALESCE(np.email_enabled, FALSE) as email_enabled
        FROM items i
        JOIN users u ON u.id = i.user_id
        LEFT JOIN notification_preferences np ON np.user_id = u.id
        LEFT JOIN notification_history nh ON nh.item_id = i.id
          AND nh.type = 'warranty_expiring'
          AND nh.sent_at > NOW() - INTERVAL '1 day'
        WHERE i.is_archived = FALSE
          AND i.warranty_end_date BETWEEN CURRENT_DATE
            AND CURRENT_DATE + make_interval(days => COALESCE(np.first_reminder_days, 30))
          AND nh.id IS NULL
      `);

      let notifiedCount = 0;
      for (const row of result.rows) {
        try {
          const itemLabel = row.brand ? `${row.brand} ${row.item_name}` : row.item_name;
          // Format date in UTC to avoid timezone off-by-one from DB DATE column
          const d = new Date(row.warranty_end_date);
          const expiryDate = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;

          await NotificationsService.createNotification({
            user_id: row.user_id,
            item_id: row.item_id,
            type: 'warranty_expiring',
            title: 'Warranty Expiring Soon',
            body: `Your warranty for ${itemLabel} expires on ${expiryDate}.`,
          });

          // Send email if user has email notifications enabled
          if (row.email_enabled) {
            try {
              const daysRemaining = Math.ceil(
                (new Date(row.warranty_end_date).getTime() - Date.now()) / (1000 * 60 * 60 * 24)
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
}
