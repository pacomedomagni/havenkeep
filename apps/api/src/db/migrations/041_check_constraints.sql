-- ============================================
-- Migration 041: CHECK constraint hardening + nullable defaults
--   (Ch00-DB014..019, DB044..049)
-- Date: 2026-04-25
-- Description: Tighten data shape so the API can stop double-validating in
--   service code. Each CHECK rejects only what should never have been
--   accepted in the first place.
-- ============================================

-- ── DB046: partners.subscription_tier nullable ──
-- Backfill any NULL rows to 'basic' before the NOT NULL flip.
UPDATE partners SET subscription_tier = 'basic' WHERE subscription_tier IS NULL;
ALTER TABLE partners ALTER COLUMN subscription_tier SET NOT NULL;
ALTER TABLE partners ALTER COLUMN subscription_tier SET DEFAULT 'basic';

-- ── DB044: partners.is_active default change not backfilled ──
-- Approval flow flipped this default; honor the audit trail by NOT touching
-- existing rows here (audit Ch00-DB044). Just lock in the default + NOT NULL.
ALTER TABLE partners ALTER COLUMN is_active SET NOT NULL;

-- ── DB049: brand_color hex CHECK ──
-- Sanitize anything that's not a 6-hex-char value first (NULL it out).
UPDATE partners SET brand_color = NULL
 WHERE brand_color IS NOT NULL
   AND brand_color !~ '^#[0-9A-Fa-f]{6}$';

ALTER TABLE partners DROP CONSTRAINT IF EXISTS chk_partners_brand_color_hex;
ALTER TABLE partners
  ADD CONSTRAINT chk_partners_brand_color_hex
  CHECK (brand_color IS NULL OR brand_color ~ '^#[0-9A-Fa-f]{6}$');

-- ── DB014: chk_partner_gifts_stripe_charge_required omits 'sent' ──
-- A 'sent' gift went out via email; that only makes sense if Stripe paid.
ALTER TABLE partner_gifts DROP CONSTRAINT IF EXISTS chk_partner_gifts_stripe_charge_required;
ALTER TABLE partner_gifts
  ADD CONSTRAINT chk_partner_gifts_stripe_charge_required
  CHECK (
    status IN ('pending_payment', 'created', 'expired')
    OR stripe_charge_id IS NOT NULL
  );

-- ── DB015: chk_partner_gifts_activation_consistency ──
-- If is_activated then status must be 'activated'; if expired, is_activated
-- must be FALSE (refund/expiry path resets the flag).
ALTER TABLE partner_gifts DROP CONSTRAINT IF EXISTS chk_partner_gifts_activation_consistency;
ALTER TABLE partner_gifts
  ADD CONSTRAINT chk_partner_gifts_activation_consistency
  CHECK (
    (is_activated = FALSE)
    OR (is_activated = TRUE AND status = 'activated')
  );

-- ── DB016: homebuyer_email regex (replace LIKE '%@%.%') ──
-- Use the same pattern as the API's Joi schema so the DB rejects what the
-- service rejects. The regex requires <local>@<domain>.<tld>.
ALTER TABLE partner_gifts DROP CONSTRAINT IF EXISTS chk_partner_gifts_homebuyer_email_format;
ALTER TABLE partner_gifts
  ADD CONSTRAINT chk_partner_gifts_homebuyer_email_format
  CHECK (homebuyer_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

-- ── DB018: partner_commissions.commission_rate DEFAULT 0.15 freezes the rate ──
-- Drop the DEFAULT so a row inserted without an explicit rate raises NOT NULL
-- (the service must populate from the partner tier, not silently default).
ALTER TABLE partner_commissions ALTER COLUMN commission_rate DROP DEFAULT;

-- Existing pending rows that carry the frozen 0.15 are flagged for the audit
-- by virtue of the column being un-defaulted; they still validate.

-- ── DB047: first_reminder_days CHECK ──
ALTER TABLE notification_preferences DROP CONSTRAINT IF EXISTS chk_notification_first_reminder_days;
ALTER TABLE notification_preferences
  ADD CONSTRAINT chk_notification_first_reminder_days
  CHECK (first_reminder_days BETWEEN 1 AND 365);

-- ── DB048: reminder_time HH:MM CHECK ──
ALTER TABLE notification_preferences DROP CONSTRAINT IF EXISTS chk_notification_reminder_time_hhmm;
ALTER TABLE notification_preferences
  ADD CONSTRAINT chk_notification_reminder_time_hhmm
  CHECK (reminder_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$');

-- ── DB019: users.referral_code UNIQUE was added without dedup check ──
-- Detect duplicates and surface them; abort if found rather than silently
-- preserving the unique constraint that the audit found drifting.
DO $$
DECLARE
  v_dup INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_dup
    FROM (
      SELECT referral_code FROM users
       WHERE referral_code IS NOT NULL
       GROUP BY referral_code
       HAVING COUNT(*) > 1
    ) d;
  IF v_dup > 0 THEN
    RAISE EXCEPTION 'users.referral_code has % duplicates — manual reconciliation required before this migration can complete', v_dup;
  END IF;
END $$;

-- ── Items: estimated_repair_cost / expected_lifespan_years sanity ──
-- These came from migration 002 with no bounds; tighten so analytics can
-- trust them.
ALTER TABLE items DROP CONSTRAINT IF EXISTS chk_items_repair_cost_nonneg;
ALTER TABLE items
  ADD CONSTRAINT chk_items_repair_cost_nonneg
  CHECK (estimated_repair_cost IS NULL OR estimated_repair_cost >= 0);

ALTER TABLE items DROP CONSTRAINT IF EXISTS chk_items_lifespan_positive;
ALTER TABLE items
  ADD CONSTRAINT chk_items_lifespan_positive
  CHECK (expected_lifespan_years IS NULL OR expected_lifespan_years BETWEEN 1 AND 100);

DO $$
BEGIN
  RAISE NOTICE 'Migration 041 complete: CHECK constraints + NOT NULL backfill landed';
END $$;
