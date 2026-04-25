-- ============================================
-- Migration 062: maintenance dedup + savings_feed anonymize on user delete
--   (Ch04-F006, F024)
-- Date: 2026-04-25
-- Description:
--   Two unrelated invariants share one migration to keep the file count down.
--
--   1. (Ch04-F024) maintenance_history allowed a user to log the same
--      schedule on the same date repeatedly to inflate `prevents_cost`.
--      Add a partial UNIQUE on (user_id, item_id, schedule_id, completed_date)
--      where schedule_id is set so two entries for the same scheduled task on
--      the same day are rejected at the DB layer.
--
--   2. (Ch04-F006) savings_feed retained the city/state of users who had
--      since deleted their account because the FK was ON DELETE CASCADE on
--      items, but the savings_feed.user_city / user_state were copied at
--      insert time. Convert any FK to user → SET NULL and null those fields
--      via a deferred update when a user is deleted.
-- ============================================

-- ── 1. maintenance_history dedup ───────────────────────────────────────
-- First sanitize existing duplicate rows: keep the earliest, delete the rest.
-- Only apply where schedule_id is non-null.
WITH ranked AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY user_id, item_id, schedule_id, completed_date
           ORDER BY created_at ASC, id ASC
         ) AS rn
    FROM maintenance_history
   WHERE schedule_id IS NOT NULL
)
DELETE FROM maintenance_history
 WHERE id IN (SELECT id FROM ranked WHERE rn > 1);

CREATE UNIQUE INDEX IF NOT EXISTS uniq_maintenance_history_dedup
  ON maintenance_history (user_id, item_id, schedule_id, completed_date)
  WHERE schedule_id IS NOT NULL;

-- ── 2. savings_feed user identity null on delete ───────────────────────
-- Add a user_id pointer (SET NULL on delete) so we can wipe the denormalized
-- city/state when the user is deleted. The column starts nullable since
-- existing rows pre-date this column.

ALTER TABLE savings_feed
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_savings_feed_user
  ON savings_feed (user_id);

-- The migration 002 schema declared user_city/state as nullable already, but
-- be defensive in case a downstream tightened them.
ALTER TABLE savings_feed ALTER COLUMN user_city DROP NOT NULL;
ALTER TABLE savings_feed ALTER COLUMN user_state DROP NOT NULL;

-- Trigger: when a user is deleted (soft or hard), null their identity
-- columns in savings_feed before the FK SET NULL fires. We can't anonymize
-- via SET NULL alone because user_city/user_state are denormalized strings.
CREATE OR REPLACE FUNCTION savings_feed_anonymize_on_user_delete()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE savings_feed
     SET user_city = NULL,
         user_state = NULL
   WHERE user_id = OLD.id;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_savings_feed_anonymize ON users;
CREATE TRIGGER trg_savings_feed_anonymize
  BEFORE DELETE ON users
  FOR EACH ROW EXECUTE FUNCTION savings_feed_anonymize_on_user_delete();

DO $$
BEGIN
  RAISE NOTICE 'Migration 062 complete: maintenance dedup + savings_feed anonymize';
END $$;
