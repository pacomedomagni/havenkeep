-- Migration 089: replace chargeback_status enum allowlist with a regex CHECK.
--
-- Audit H-D8: mig 050 added a tight CHECK enumerating the 8 Stripe
-- dispute statuses Stripe defined at the time. Stripe occasionally
-- introduces new statuses (the API dispute enum has changed twice in
-- the past two years — `expired`, `under_review_external`, etc.). Any
-- new status crashes handleChargeDispute with 23514, the webhook is
-- retried, attempts climbs, eventually dead-letters at attempt 8.
--
-- Trade-off: a tight allowlist catches typos but Stripe is the upstream
-- source of truth — we'd rather store an unknown new value than reject
-- a real dispute event. Switch to a permissive regex (lowercase
-- snake_case, length-bounded) so a future Stripe enum addition
-- doesn't require a code deploy.

ALTER TABLE partner_gifts DROP CONSTRAINT IF EXISTS chk_partner_gifts_chargeback_status;
ALTER TABLE partner_gifts
  ADD CONSTRAINT chk_partner_gifts_chargeback_status
  CHECK (
    chargeback_status IS NULL
    OR chargeback_status ~ '^[a-z][a-z0-9_]{0,63}$'
  );

DO $$
BEGIN
  RAISE NOTICE 'Migration 089 complete: chargeback_status CHECK is now regex-based (H-D8)';
END $$;
