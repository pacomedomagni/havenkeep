-- ============================================
-- Migration 050: Webhook ordering + dispute schema + partner safety nets
--   (Ch03-F009, F044, F046, F068, F079, F080, F114, F125)
-- Date: 2026-04-25
-- Description:
--   * Adds last_event_at + per-source ordering guard so a stale RC event
--     can't overwrite a fresher one (Ch03-F009).
--   * Promotes attempts → first_seen_at + last_seen_at so the dead-letter
--     transition path can decide based on age + count (Ch03-F046).
--   * Adds payload_digest so the age-window-on-missing-row case (Ch03-F044)
--     can be reasoned about during incident triage.
--   * Adds CHECK on partner_gifts.expires_at > created_at (Ch03-F079).
--   * Adds partner_gifts.disputed_at + chargeback_status for the dispute
--     handler (Ch03-F125).
--   * Adds partners.stripe_account_status so deactivation tracking is real
--     state, not a sticky flag (Ch03-F113).
--   * Locks partner_type post-registration (Ch03-F015) by adding a guard
--     trigger that rejects partner_type changes after creation.
-- ============================================

-- 1. Webhook events: ordering + tracing fields.
ALTER TABLE webhook_events
  ADD COLUMN IF NOT EXISTS first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS payload_digest CHAR(64);

-- last_event_at is the event-stream ordering anchor. For RC this is
-- event.event_timestamp_ms; for Stripe it is event.created converted to
-- a TIMESTAMPTZ. Used by the handler to drop out-of-order replays.
ALTER TABLE webhook_events
  ADD COLUMN IF NOT EXISTS last_event_at TIMESTAMPTZ;

-- Per-source ordering tracker. One row per (source, subject_id) where
-- subject_id is the RC app_user_id or Stripe charge id; lets us compare
-- the incoming event's ordering anchor against the last one applied.
CREATE TABLE IF NOT EXISTS webhook_event_high_water (
  source        VARCHAR(50)   NOT NULL,
  subject_id    VARCHAR(255)  NOT NULL,
  last_event_at TIMESTAMPTZ   NOT NULL,
  last_event_id VARCHAR(255)  NOT NULL,
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  PRIMARY KEY (source, subject_id)
);

CREATE INDEX IF NOT EXISTS idx_webhook_event_high_water_updated
  ON webhook_event_high_water(updated_at DESC);

-- 2. partner_gifts: expires_at integrity + dispute fields.
-- Existing rows that violate the constraint indicate stale/seed data; clamp
-- before constraint creation so the migration applies cleanly.
UPDATE partner_gifts
   SET expires_at = created_at + INTERVAL '6 months'
 WHERE expires_at IS NOT NULL
   AND expires_at <= created_at;

ALTER TABLE partner_gifts DROP CONSTRAINT IF EXISTS chk_partner_gifts_expires_after_created;
ALTER TABLE partner_gifts
  ADD CONSTRAINT chk_partner_gifts_expires_after_created
  CHECK (expires_at IS NULL OR expires_at > created_at);

ALTER TABLE partner_gifts
  ADD COLUMN IF NOT EXISTS disputed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS chargeback_status VARCHAR(40);

ALTER TABLE partner_gifts DROP CONSTRAINT IF EXISTS chk_partner_gifts_chargeback_status;
ALTER TABLE partner_gifts
  ADD CONSTRAINT chk_partner_gifts_chargeback_status
  CHECK (
    chargeback_status IS NULL
    OR chargeback_status IN (
      'warning_needs_response',
      'warning_under_review',
      'warning_closed',
      'needs_response',
      'under_review',
      'charge_refunded',
      'won',
      'lost'
    )
  );

CREATE INDEX IF NOT EXISTS idx_partner_gifts_chargeback_status
  ON partner_gifts(chargeback_status)
  WHERE chargeback_status IS NOT NULL;

-- 3. partners: real Stripe account status (replaces sticky stripe_onboarded).
ALTER TABLE partners
  ADD COLUMN IF NOT EXISTS stripe_account_status VARCHAR(40)
    NOT NULL DEFAULT 'unknown',
  ADD COLUMN IF NOT EXISTS stripe_account_status_at TIMESTAMPTZ;

ALTER TABLE partners DROP CONSTRAINT IF EXISTS chk_partners_stripe_account_status;
ALTER TABLE partners
  ADD CONSTRAINT chk_partners_stripe_account_status
  CHECK (stripe_account_status IN (
    'unknown',
    'pending',
    'enabled',
    'restricted',
    'disabled',
    'rejected'
  ));

-- 4. Lock partner_type after creation. Trigger rejects any UPDATE that
-- changes partner_type. Admin override tooling can `SET LOCAL` a session
-- GUC if a legitimate reclassification is ever needed.
CREATE OR REPLACE FUNCTION partners_lock_partner_type()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.partner_type IS DISTINCT FROM OLD.partner_type THEN
    -- Allow a session-scoped escape hatch for the rare admin reclassify case.
    IF current_setting('havenkeep.allow_partner_type_change', true) = 'on' THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'partner_type is immutable after registration (current: %, attempted: %)',
      OLD.partner_type, NEW.partner_type
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_partners_lock_partner_type ON partners;
CREATE TRIGGER trg_partners_lock_partner_type
  BEFORE UPDATE OF partner_type ON partners
  FOR EACH ROW
  EXECUTE FUNCTION partners_lock_partner_type();

-- 5. partner_commissions.commission_rate cannot remain nullable + un-defaulted
--    without breaking inserts that don't pass the rate. Migration 041 dropped
--    the DEFAULT to force callers to pass an explicit rate; mark it NOT NULL
--    here so a missing rate raises 23502 instead of silently storing NULL.
UPDATE partner_commissions
   SET commission_rate = 0.15
 WHERE commission_rate IS NULL;

ALTER TABLE partner_commissions
  ALTER COLUMN commission_rate SET NOT NULL;

DO $$
BEGIN
  RAISE NOTICE 'Migration 050 complete: ordering + dispute fields + partner_type lock';
END $$;
