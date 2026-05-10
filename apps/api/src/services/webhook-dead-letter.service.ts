import { pool } from '../db';
import { logger } from '../utils/logger';
import { EmailService } from './email.service';

interface DeadLetterRow {
  id: number | string;
  source: string;
  event_id: string;
  event_type: string | null;
  created_at: Date;
}

/**
 * H2: daily sweep of webhook_events.status = 'dead_letter' rows that
 * haven't been alerted on yet. Sends one email per batch, stamps
 * alerted_at on each row so the next day's run only picks up new
 * dead-letters.
 */
export async function alertOnDeadLetterWebhooks(): Promise<{
  newDeadLetters: number;
}> {
  const result = await pool.query<DeadLetterRow>(
    `SELECT id, source, event_id, event_type, created_at
       FROM webhook_events
      WHERE status = 'dead_letter'
        AND alerted_at IS NULL
      ORDER BY created_at ASC
      LIMIT 100`,
  );
  if (result.rows.length === 0) {
    return { newDeadLetters: 0 };
  }
  await EmailService.sendWebhookDeadLetterAlert({ rows: result.rows });
  await pool.query(
    `UPDATE webhook_events
        SET alerted_at = NOW()
      WHERE id = ANY($1::bigint[])`,
    [result.rows.map((r) => r.id)],
  );
  logger.warn({ count: result.rows.length }, 'webhook dead-letter alert dispatched');
  return { newDeadLetters: result.rows.length };
}

/**
 * H2: admin re-drive. Flips a dead-letter row back to pending and zeros
 * the attempt counter so the next webhook re-delivery from the provider
 * (or a manual replay) will reprocess it. Operator's responsibility to
 * fix the underlying handler first.
 *
 * Returns the previous status / attempts so the audit log captures
 * what state the row was in before the re-drive.
 */
export async function redriveDeadLetterWebhook(id: number | string): Promise<{
  previousStatus: string;
  previousAttempts: number;
} | null> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const before = await client.query<{ status: string; attempts: number }>(
      `SELECT status, attempts FROM webhook_events WHERE id = $1 FOR UPDATE`,
      [id],
    );
    if (before.rows.length === 0 || before.rows[0].status !== 'dead_letter') {
      await client.query('ROLLBACK');
      return null;
    }
    await client.query(
      `UPDATE webhook_events
          SET status     = 'pending',
              attempts   = 0,
              alerted_at = NULL,
              last_error = NULL
        WHERE id = $1`,
      [id],
    );
    await client.query('COMMIT');
    return {
      previousStatus: before.rows[0].status,
      previousAttempts: before.rows[0].attempts,
    };
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}
