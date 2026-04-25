-- ============================================
-- Migration 044: notification_history user_id CASCADE → SET NULL (Ch00-DB030)
-- Date: 2026-04-25
-- Description: Deleting a user erased their entire push-notification history,
--   which made it impossible to investigate complaints or audit deliverability.
--   Convert user_id to SET NULL and denormalize the email so a deleted user's
--   history retains an identifier (mirrors audit_logs).
-- ============================================

ALTER TABLE notification_history
  DROP CONSTRAINT IF EXISTS notification_history_user_id_fkey;

ALTER TABLE notification_history
  ALTER COLUMN user_id DROP NOT NULL;

ALTER TABLE notification_history
  ADD CONSTRAINT notification_history_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE notification_history
  ADD COLUMN IF NOT EXISTS user_email_at_send VARCHAR(320);

CREATE INDEX IF NOT EXISTS idx_notification_history_user_email
  ON notification_history(user_email_at_send)
  WHERE user_email_at_send IS NOT NULL;

DO $$
BEGIN
  RAISE NOTICE 'Migration 044 complete: notification_history user_id is SET NULL + email denormalized';
END $$;
