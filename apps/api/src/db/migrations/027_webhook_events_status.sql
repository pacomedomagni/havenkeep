-- ============================================
-- Migration 027: Webhook events status tracking
-- Date: 2026-04-19
-- Description: Adds status column so webhook events can be claimed
--   atomically, processed, and only marked 'processed' on success.
--   Previously: recording an event's id pre-processing meant a mid-
--   flight failure would skip the retry (event appeared already done).
-- ============================================

ALTER TABLE webhook_events
  ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'processed',
  ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_error TEXT;

ALTER TABLE webhook_events
  DROP CONSTRAINT IF EXISTS chk_webhook_events_status;
ALTER TABLE webhook_events
  ADD CONSTRAINT chk_webhook_events_status
  CHECK (status IN ('pending', 'processed', 'failed'));

CREATE INDEX IF NOT EXISTS idx_webhook_events_status ON webhook_events (status, processed_at);
