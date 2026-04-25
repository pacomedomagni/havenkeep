-- ============================================
-- Migration 037: Newsletter double-opt-in (Ch04-F108)
-- Date: 2026-04-25
-- Description: POST /newsletter/subscribe immediately upserted with no email
--   verification, so anyone could subscribe a third party (or a list of
--   third parties) and the project would mail them. Add explicit subscription
--   states, a confirmation token table, and a partial unique index that only
--   blocks duplicates among confirmed rows.
-- ============================================

-- 1. Replace the absolute UNIQUE on email with a partial that scopes to
--    confirmed subscriptions, so a user who let confirmation expire can
--    re-subscribe.
ALTER TABLE newsletter_subscribers
  DROP CONSTRAINT IF EXISTS uq_newsletter_email;

ALTER TABLE newsletter_subscribers
  ADD COLUMN IF NOT EXISTS status VARCHAR(32) NOT NULL DEFAULT 'pending_confirmation',
  ADD COLUMN IF NOT EXISTS confirmation_token_hash CHAR(64),
  ADD COLUMN IF NOT EXISTS confirmation_sent_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS confirmed_at TIMESTAMPTZ;

ALTER TABLE newsletter_subscribers
  DROP CONSTRAINT IF EXISTS chk_newsletter_status;

ALTER TABLE newsletter_subscribers
  ADD CONSTRAINT chk_newsletter_status
  CHECK (status IN ('pending_confirmation', 'subscribed', 'unsubscribed'));

-- Mark any pre-existing rows as 'subscribed' so we don't email re-confirm
-- requests to people who legitimately signed up before double-opt-in shipped.
UPDATE newsletter_subscribers
SET status = 'subscribed',
    confirmed_at = COALESCE(confirmed_at, subscribed_at)
WHERE status = 'pending_confirmation'
  AND unsubscribed_at IS NULL
  AND subscribed_at IS NOT NULL;

UPDATE newsletter_subscribers
SET status = 'unsubscribed'
WHERE unsubscribed_at IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_newsletter_subscribed_email
  ON newsletter_subscribers(LOWER(email))
  WHERE status = 'subscribed';

CREATE UNIQUE INDEX IF NOT EXISTS idx_newsletter_confirmation_token_hash
  ON newsletter_subscribers(confirmation_token_hash)
  WHERE confirmation_token_hash IS NOT NULL;

-- 2. Composite index for IP rate-limiting (Ch00-DB052)
CREATE INDEX IF NOT EXISTS idx_newsletter_ip_created
  ON newsletter_subscribers(ip_address, created_at DESC);

DO $$
BEGIN
  RAISE NOTICE 'Migration 037 complete: newsletter double-opt-in columns added';
END $$;
