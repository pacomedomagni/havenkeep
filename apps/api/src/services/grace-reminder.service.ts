import { pool } from '../db';
import { logger } from '../utils/logger';
import { EmailService } from './email.service';

/**
 * H78: nudge users 5 days before their soft-deletion grace window
 * closes. Daily cron. Each row is sent at most once (we stamp
 * `last_grace_reminder_sent_at`) and the partial index on the column
 * keeps the scan cheap.
 *
 * The window is `deletion_scheduled_for - NOW() BETWEEN 4d AND 5d`
 * rather than exactly 5 days so a cron run delayed by an hour
 * doesn't slip the window — every row gets one daily chance to be
 * picked up over a 24h band.
 */
export async function sendDay25GraceReminders(): Promise<{
  candidates: number;
  sent: number;
  failed: number;
}> {
  const result: { candidates: number; sent: number; failed: number } = {
    candidates: 0,
    sent: 0,
    failed: 0,
  };

  const candidates = await pool.query<{
    id: string;
    email: string;
    full_name: string | null;
    deletion_scheduled_for: Date;
  }>(
    `SELECT id, email, full_name, deletion_scheduled_for
       FROM users
      WHERE deleted_at IS NOT NULL
        AND last_grace_reminder_sent_at IS NULL
        AND deletion_scheduled_for IS NOT NULL
        AND deletion_scheduled_for > NOW() + INTERVAL '4 days'
        AND deletion_scheduled_for < NOW() + INTERVAL '5 days'
      ORDER BY deletion_scheduled_for ASC
      LIMIT 200`,
  );
  result.candidates = candidates.rows.length;

  for (const row of candidates.rows) {
    try {
      await EmailService.sendGraceReminderEmail({
        to: row.email,
        userName: row.full_name ?? '',
        deletionScheduledFor: row.deletion_scheduled_for,
      });
      // Stamp only after a successful send so a SendGrid blip causes a
      // retry tomorrow, not a silent miss.
      await pool.query(
        `UPDATE users SET last_grace_reminder_sent_at = NOW() WHERE id = $1`,
        [row.id],
      );
      result.sent += 1;
    } catch (err) {
      result.failed += 1;
      logger.warn({ err, userId: row.id }, 'Day-25 grace reminder send failed (will retry next run)');
    }
  }

  return result;
}
