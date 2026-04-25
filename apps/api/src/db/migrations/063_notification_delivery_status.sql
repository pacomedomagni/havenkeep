-- ============================================
-- Migration 063: notification_history.delivery_status (Ch04-F038)
-- Date: 2026-04-25
-- Description:
--   The user-facing notifications list surfaces every row regardless of
--   whether FCM accepted the push. After a token rotates we'd write a row,
--   FCM would reject, and the user would still see the notification in the
--   app inbox even though the system never actually delivered the message.
--   Tag rows with delivery_status so 'failed' rows can be excluded from the
--   user-facing list.
-- ============================================

ALTER TABLE notification_history
  ADD COLUMN IF NOT EXISTS delivery_status VARCHAR(16) NOT NULL DEFAULT 'pending';

ALTER TABLE notification_history
  DROP CONSTRAINT IF EXISTS chk_notification_delivery_status;
ALTER TABLE notification_history
  ADD CONSTRAINT chk_notification_delivery_status
  CHECK (delivery_status IN ('pending','delivered','failed','skipped'));

CREATE INDEX IF NOT EXISTS idx_notification_history_user_status
  ON notification_history (user_id, delivery_status, sent_at DESC)
  WHERE delivery_status IN ('pending','delivered');

-- Default the new flag retroactively: rows with delivered_at populated are
-- 'delivered'; everything else stays 'pending' and the route filter
-- continues to surface them while delivery races to settle.
UPDATE notification_history
   SET delivery_status = 'delivered'
 WHERE delivered_at IS NOT NULL AND delivery_status = 'pending';

-- ── warranty_offers default → FALSE (Ch04-F047) ────────────────────────
ALTER TABLE notification_preferences
  ALTER COLUMN warranty_offers_enabled SET DEFAULT FALSE;

-- ── quiet hours + timezone (Ch04-F033) ─────────────────────────────────
-- Server-side suppression window. NULL fields disable the check; both must
-- be non-null for a real window. timezone defaults to UTC so an unset user
-- still gets a deterministic window if quiet_hours_* are filled in.
ALTER TABLE notification_preferences
  ADD COLUMN IF NOT EXISTS quiet_hours_start VARCHAR(5),
  ADD COLUMN IF NOT EXISTS quiet_hours_end VARCHAR(5),
  ADD COLUMN IF NOT EXISTS timezone VARCHAR(64) NOT NULL DEFAULT 'UTC',
  ADD COLUMN IF NOT EXISTS digest_minutes INTEGER NOT NULL DEFAULT 0;

ALTER TABLE notification_preferences
  DROP CONSTRAINT IF EXISTS chk_notification_quiet_hours_format;
ALTER TABLE notification_preferences
  ADD CONSTRAINT chk_notification_quiet_hours_format
  CHECK (
    (quiet_hours_start IS NULL OR quiet_hours_start ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$')
    AND (quiet_hours_end IS NULL OR quiet_hours_end ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$')
  );

ALTER TABLE notification_preferences
  DROP CONSTRAINT IF EXISTS chk_notification_digest_minutes;
ALTER TABLE notification_preferences
  ADD CONSTRAINT chk_notification_digest_minutes
  CHECK (digest_minutes >= 0 AND digest_minutes <= 240);

DO $$
BEGIN
  RAISE NOTICE 'Migration 063 complete: notification delivery_status + warranty_offers default FALSE';
END $$;
