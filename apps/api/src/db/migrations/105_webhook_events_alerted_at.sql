-- Migration 105: webhook_events.alerted_at for H2 dead-letter alerting.
--
-- A row hits status='dead_letter' after MAX_WEBHOOK_ATTEMPTS retries
-- exhaust. Without an alerting cron the row sits there silently —
-- refunds, dispute notifications, plan transitions all stuck. The new
-- column lets the cron pick up unalerted dead-letter rows on each run
-- and stamp this so we don't spam the operator daily for the same row.

ALTER TABLE webhook_events
  ADD COLUMN IF NOT EXISTS alerted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_webhook_events_dead_letter_unalerted
  ON webhook_events (status, alerted_at)
  WHERE status = 'dead_letter' AND alerted_at IS NULL;
