-- ============================================
-- Migration 029: webhook_events status default 'pending' (Ch08-WebhookEvent-D076)
-- Date: 2026-04-25
-- Description: Migration 027 added a `status` column with DEFAULT 'processed'.
--   That defeated 027's own intent: a row inserted before the handler runs is
--   already 'processed' so retry never picks it up. Flip the default to 'pending'
--   and add the 'dead_letter' state value that retry counters need.
-- ============================================

ALTER TABLE webhook_events
  ALTER COLUMN status SET DEFAULT 'pending';

ALTER TABLE webhook_events
  DROP CONSTRAINT IF EXISTS chk_webhook_events_status;

ALTER TABLE webhook_events
  ADD CONSTRAINT chk_webhook_events_status
  CHECK (status IN ('pending', 'processed', 'failed', 'dead_letter'));

ALTER TABLE webhook_events
  ADD COLUMN IF NOT EXISTS attempts INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS event_created_at TIMESTAMPTZ;

DO $$
BEGIN
  RAISE NOTICE 'Migration 029 complete: webhook_events default flipped to pending';
END $$;
