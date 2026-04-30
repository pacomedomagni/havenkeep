-- Migration 088: separate completion_message from error_message on email_scans.
--
-- Audit H-D7: the prior shape stored "X items skipped — free plan
-- limit reached" / "Y items pending review" strings in
-- email_scans.error_message when status='completed'. Monitoring queries
-- that filter `WHERE error_message IS NOT NULL AND status='completed'`
-- to count failed scans pick up the success-path completion notes as
-- noise, and any future alert that triggers on
-- error_message-not-null-rate would be permanently in alarm.
--
-- Adds completion_message TEXT alongside the existing error_message
-- column; the service writes the success notes to the new column and
-- leaves error_message strictly for failure paths.

ALTER TABLE email_scans
  ADD COLUMN IF NOT EXISTS completion_message TEXT;

DO $$
BEGIN
  RAISE NOTICE 'Migration 088 complete: email_scans.completion_message added (H-D7)';
END $$;
