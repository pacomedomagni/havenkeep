-- Migration 110: H77 — newsletter confirmation tokens get a TTL.
--
-- The prior shape (mig 037) added `confirmation_token_hash` + a
-- `confirmation_sent_at` timestamp but never enforced expiry. A token
-- minted months ago could still be redeemed — useful for newsletter
-- list-poisoning (an attacker collects pending-confirmation rows,
-- then redeems them later from a different IP to confirm subscriptions
-- the original owner abandoned).
--
-- Fix: add `confirmation_expires_at` defaulted to 7 days from the
-- existing `confirmation_sent_at` for any in-flight pending rows.
-- Mint paths set it to NOW() + 7 days. The /confirm route gates on
-- expires_at > NOW().

ALTER TABLE newsletter_subscribers
  ADD COLUMN IF NOT EXISTS confirmation_expires_at TIMESTAMPTZ;

-- Backfill: rows in pending_confirmation get a 7-day window measured
-- from when they were sent (or NOW() if confirmation_sent_at is null,
-- which would be a malformed row).
UPDATE newsletter_subscribers
SET confirmation_expires_at = COALESCE(confirmation_sent_at, NOW()) + INTERVAL '7 days'
WHERE status = 'pending_confirmation' AND confirmation_expires_at IS NULL;
