-- 115: Partner-program simplification, phase 5 (destructive).
--
-- After phases 1-4 the application code no longer reads or writes any of
-- the columns / tables / enums dropped here. This migration removes them.
--
-- Irreversible. Phase 1's nullability relaxation (mig 114) means rolling
-- back to a pre-phase-2 app build is still safe up to this point; once
-- THIS migration applies, a downgrade requires a hand-written restore.
--
-- Scope:
--   * Drop partner_commissions (entire commission ledger + clawback rows)
--   * Drop Stripe-Connect columns on partners + the associated CHECKs,
--     indexes, defaults
--   * Drop billing + identity-snapshot columns on partner_gifts
--   * Drop the partner.subscription_tier, .license_number,
--     .default_premium_months, .welcome_email_opened_at,
--     .last_payout_requested_at, .is_active, .is_verified, .status columns
--   * Drop users.stripe_customer_id
--   * Drop the partner_tier / commission_status / commission_type enums
--   * Drop the partner_status enum
--   * Trim gift_status enum (remove 'pending_payment' + 'payment_failed')
--
-- Audit-action enum values (`admin.commission_*`, `partner.payout_request`,
-- `admin.partner_approve|reject`) are NOT dropped — Postgres rejects enum
-- value removal once written into rows, and the audit_logs trigger is
-- intentionally append-only. Those values become permanently dormant.

BEGIN;

-- ─── Drop dependent constraints + indexes first ──────────────────────
-- Constraints that reference columns we're about to drop, or enum
-- values we're about to remove. ALTER TABLE … DROP COLUMN can't drop a
-- column that's covered by a multi-column CHECK without CASCADE; we
-- DROP CONSTRAINT explicitly so the intent is in the migration log
-- instead of being implicit in a CASCADE.
ALTER TABLE partners
  DROP CONSTRAINT IF EXISTS chk_partners_active_status_consistent,
  DROP CONSTRAINT IF EXISTS chk_partners_stripe_account_status;

ALTER TABLE partner_gifts
  DROP CONSTRAINT IF EXISTS chk_partner_gifts_stripe_charge_required;

DROP INDEX IF EXISTS idx_partners_active;
DROP INDEX IF EXISTS idx_partners_status;
DROP INDEX IF EXISTS idx_partners_stripe;
DROP INDEX IF EXISTS idx_partners_welcome_email_opened;
DROP INDEX IF EXISTS idx_users_stripe;

-- ─── Drop partner_commissions ────────────────────────────────────────
-- partner_payouts never existed as a table — payouts live on
-- partner_commissions.status='paid' + .stripe_transfer_id. So a single
-- DROP TABLE on partner_commissions removes the entire commission
-- ledger.
--
-- Foreign keys: partner_commissions.partner_id was already SET NULL on
-- partner delete (mig 102), and no other table references
-- partner_commissions (the audit log carries id as a string in JSON
-- metadata only). Safe to drop unconditionally.
DROP TABLE IF EXISTS partner_commissions CASCADE;

-- ─── Strip dead columns on partners ──────────────────────────────────
ALTER TABLE partners
  DROP COLUMN IF EXISTS stripe_account_id,
  DROP COLUMN IF EXISTS stripe_onboarded,
  DROP COLUMN IF EXISTS stripe_account_status,
  DROP COLUMN IF EXISTS stripe_account_status_at,
  DROP COLUMN IF EXISTS last_payout_requested_at,
  DROP COLUMN IF EXISTS welcome_email_opened_at,
  DROP COLUMN IF EXISTS is_verified,
  DROP COLUMN IF EXISTS is_active,
  DROP COLUMN IF EXISTS status,
  DROP COLUMN IF EXISTS subscription_tier,
  DROP COLUMN IF EXISTS license_number,
  DROP COLUMN IF EXISTS default_premium_months;

-- ─── Strip dead columns on partner_gifts ─────────────────────────────
ALTER TABLE partner_gifts
  DROP COLUMN IF EXISTS amount_charged,
  DROP COLUMN IF EXISTS stripe_charge_id,
  DROP COLUMN IF EXISTS partner_id_at_event,
  DROP COLUMN IF EXISTS partner_company_name_at_event,
  DROP COLUMN IF EXISTS partner_email_at_event,
  -- The chargeback path is part of the dropped Stripe webhook handler;
  -- leave the index drop to CASCADE behaviour on the column drop.
  DROP COLUMN IF EXISTS disputed_at,
  DROP COLUMN IF EXISTS chargeback_status;

-- ─── Strip stripe_customer_id from users ─────────────────────────────
ALTER TABLE users DROP COLUMN IF EXISTS stripe_customer_id;

-- ─── Drop dead enums ─────────────────────────────────────────────────
-- partner_tier, commission_status, commission_type were only referenced
-- by partner_commissions + partners.subscription_tier, both gone above.
-- partner_status was only on partners.status, also gone.
DROP TYPE IF EXISTS partner_tier;
DROP TYPE IF EXISTS commission_status;
DROP TYPE IF EXISTS commission_type;
DROP TYPE IF EXISTS partner_status;

-- ─── Trim gift_status enum ───────────────────────────────────────────
-- 'pending_payment' and 'payment_failed' were Stripe-charge transitional
-- states no row will ever hold again. Postgres doesn't support
-- "ALTER TYPE … DROP VALUE", so we rebuild the enum:
--   1. Drop the activation-consistency CHECK that hard-codes the enum
--      type on its RHS — its `gift_status` reference becomes a comparison
--      between two distinct enum types mid-rebuild and the planner can't
--      find an operator for that. Recreated after the column TYPE change.
--   2. Rename the old enum out of the way.
--   3. Create the new enum with only the surviving values.
--   4. Alter the column to use the new enum (no rows hold dropped values).
--   5. Recreate the CHECK against the new enum type.
--   6. Drop the old enum.
ALTER TABLE partner_gifts
  DROP CONSTRAINT IF EXISTS chk_partner_gifts_activation_consistency;

ALTER TYPE gift_status RENAME TO gift_status_old;
CREATE TYPE gift_status AS ENUM ('created', 'sent', 'activated', 'expired');
ALTER TABLE partner_gifts
  ALTER COLUMN status DROP DEFAULT,
  ALTER COLUMN status TYPE gift_status USING status::text::gift_status,
  ALTER COLUMN status SET DEFAULT 'created';

ALTER TABLE partner_gifts
  ADD CONSTRAINT chk_partner_gifts_activation_consistency
    CHECK (is_activated = false OR (is_activated = true AND status = 'activated'::gift_status));

DROP TYPE gift_status_old;

DO $$
BEGIN
  RAISE NOTICE 'Migration 115 complete: partner program simplified to gifts-only';
END $$;

COMMIT;
