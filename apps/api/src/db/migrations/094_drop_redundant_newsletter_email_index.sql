-- Migration 094: drop redundant idx_newsletter_subscribers_email.
--
-- Audit M-NEW-6: mig 013 added an unconditional INDEX on
-- newsletter_subscribers(email). Mig 037 added the canonical partial
-- UNIQUE on LOWER(email) WHERE status = 'subscribed' — which is what
-- every active-subscriber lookup uses (LOWER-coerced) and which
-- enforces the actual uniqueness rule (only one ACTIVE subscriber
-- per email, but unsubscribed rows can re-appear if the user
-- re-subscribes).
--
-- The mig 013 index is duplicate weight on every INSERT and helps no
-- query — every subscriber-list lookup goes through LOWER(email).
-- Drop it.

DROP INDEX IF EXISTS idx_newsletter_subscribers_email;

DO $$
BEGIN
  RAISE NOTICE 'Migration 094 complete: dropped redundant idx_newsletter_subscribers_email (M-NEW-6)';
END $$;
