-- Migration 111: H78 — track when we sent the day-25 grace reminder.
--
-- DELETE /me schedules a hard-delete 30 days out. A user who initiated
-- deletion in a moment of frustration (or by accident) might forget
-- they did and miss the recovery window. Add a single "5 days left"
-- nudge near the end of the grace period. The column prevents the
-- daily cron from re-sending — once stamped, the row is done.

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS last_grace_reminder_sent_at TIMESTAMPTZ;

-- Partial index because most users will never have this column set;
-- the cron scans `deletion_scheduled_for - NOW() BETWEEN 4d AND 5d`
-- with a NULL-only filter, so a partial index keyed on those rows
-- keeps the scan small.
CREATE INDEX IF NOT EXISTS idx_users_grace_reminder_pending
  ON users (deletion_scheduled_for)
  WHERE deleted_at IS NOT NULL
    AND last_grace_reminder_sent_at IS NULL;
