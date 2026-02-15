-- ============================================
-- HavenKeep Migration 011 - Audit Fixes
-- Date: 2026-02-15
-- Description: Addresses database audit findings
--   DB-1:  Add 'pending_payment' and 'payment_failed' to gift_status ENUM
--   DB-2:  FK constraint on users.referred_by -> users(id) ON DELETE SET NULL
--   DB-3:  Index on users.referred_by
--   DB-5:  CHECK constraint: stripe_charge_id NOT NULL when gift status is 'created' or 'activated'
--   DB-6:  CHECK constraint on warranty_claims.status for valid values
--   DB-7:  Composite index on items(user_id, warranty_end_date, is_archived)
--   DB-8:  documents.updated_at column with trigger (same as DB-28)
--   DB-10: CHECK constraint on partner_gifts.homebuyer_email format
--   DB-13: Add commission_rate column + CHECK BETWEEN 0 AND 1 on partner_commissions
--   DB-14: warranty_claims financial fields NOT NULL DEFAULT 0
--   DB-16: CHECK constraint: is_activated matches status on partner_gifts
--   DB-21: Composite index on items(user_id, warranty_end_date) for warranty expiry queries
--   DB-23: UNIQUE constraint on users.referral_code (allow NULL)
--   DB-24: UNIQUE constraint on partner_gifts.activation_code (allow NULL)
--   DB-28: documents.updated_at column with trigger (same as DB-8)
-- ============================================

-- DB-1: Add 'pending_payment' and 'payment_failed' to gift_status ENUM
-- NOTE: ALTER TYPE ... ADD VALUE cannot run inside a transaction block in PostgreSQL.
-- These statements MUST be executed before BEGIN.
ALTER TYPE gift_status ADD VALUE IF NOT EXISTS 'pending_payment';
ALTER TYPE gift_status ADD VALUE IF NOT EXISTS 'payment_failed';

BEGIN;

-- ============================================
-- DB-23: UNIQUE constraint on users.referral_code (allow NULLs)
-- PostgreSQL UNIQUE constraints already allow multiple NULLs.
-- ============================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'uq_users_referral_code'
      AND conrelid = 'users'::regclass
  ) THEN
    ALTER TABLE users ADD CONSTRAINT uq_users_referral_code UNIQUE (referral_code);
  END IF;
END $$;

-- ============================================
-- DB-24: UNIQUE constraint on partner_gifts.activation_code (allow NULLs)
-- ============================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'uq_partner_gifts_activation_code'
      AND conrelid = 'partner_gifts'::regclass
  ) THEN
    ALTER TABLE partner_gifts ADD CONSTRAINT uq_partner_gifts_activation_code UNIQUE (activation_code);
  END IF;
END $$;

-- ============================================
-- DB-2: FK constraint on users.referred_by -> users(id) ON DELETE SET NULL
-- ============================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fk_users_referred_by'
      AND conrelid = 'users'::regclass
  ) THEN
    ALTER TABLE users
      ADD CONSTRAINT fk_users_referred_by
      FOREIGN KEY (referred_by) REFERENCES users(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ============================================
-- DB-6: CHECK constraint on warranty_claims.status
-- Only allow: 'pending', 'submitted', 'in_review', 'approved', 'denied', 'completed', 'cancelled'
-- ============================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_warranty_claims_status'
      AND conrelid = 'warranty_claims'::regclass
  ) THEN
    ALTER TABLE warranty_claims
      ADD CONSTRAINT chk_warranty_claims_status
      CHECK (status IN ('pending', 'submitted', 'in_review', 'approved', 'denied', 'completed', 'cancelled'));
  END IF;
END $$;

-- ============================================
-- DB-5: CHECK constraint on partner_gifts ensuring stripe_charge_id is NOT NULL
--        when status is 'created' or 'activated'
-- ============================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_partner_gifts_stripe_charge_required'
      AND conrelid = 'partner_gifts'::regclass
  ) THEN
    ALTER TABLE partner_gifts
      ADD CONSTRAINT chk_partner_gifts_stripe_charge_required
      CHECK (
        (status IN ('created', 'activated') AND stripe_charge_id IS NOT NULL)
        OR
        (status NOT IN ('created', 'activated'))
      );
  END IF;
END $$;

-- ============================================
-- DB-3: Index on users.referred_by
-- ============================================
CREATE INDEX IF NOT EXISTS idx_users_referred_by ON users(referred_by);

-- ============================================
-- DB-7: Composite index on items(user_id, warranty_end_date, is_archived)
-- ============================================
CREATE INDEX IF NOT EXISTS idx_items_user_warranty_archived
  ON items(user_id, warranty_end_date, is_archived);

-- ============================================
-- DB-10: CHECK constraint on partner_gifts.homebuyer_email LIKE '%@%.%'
-- ============================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_partner_gifts_homebuyer_email_format'
      AND conrelid = 'partner_gifts'::regclass
  ) THEN
    ALTER TABLE partner_gifts
      ADD CONSTRAINT chk_partner_gifts_homebuyer_email_format
      CHECK (homebuyer_email LIKE '%@%.%');
  END IF;
END $$;

-- ============================================
-- DB-13: Add commission_rate column to partner_commissions (if missing)
--        and add CHECK constraint BETWEEN 0 AND 1
-- ============================================
ALTER TABLE partner_commissions
  ADD COLUMN IF NOT EXISTS commission_rate DECIMAL(5, 4);

-- Set default for new rows
ALTER TABLE partner_commissions ALTER COLUMN commission_rate SET DEFAULT 0.15;
-- Backfill existing rows
UPDATE partner_commissions SET commission_rate = 0.15 WHERE commission_rate IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_partner_commissions_rate_range'
      AND conrelid = 'partner_commissions'::regclass
  ) THEN
    ALTER TABLE partner_commissions
      ADD CONSTRAINT chk_partner_commissions_rate_range
      CHECK (commission_rate BETWEEN 0 AND 1);
  END IF;
END $$;

-- ============================================
-- DB-14: warranty_claims financial fields NOT NULL with DEFAULT 0
-- out_of_pocket is currently nullable; repair_cost and amount_saved already NOT NULL DEFAULT 0
-- Backfill NULLs first so the NOT NULL constraint will not fail.
-- ============================================
UPDATE warranty_claims SET out_of_pocket = 0  WHERE out_of_pocket IS NULL;
UPDATE warranty_claims SET amount_saved   = 0 WHERE amount_saved   IS NULL;
UPDATE warranty_claims SET repair_cost    = 0 WHERE repair_cost    IS NULL;

ALTER TABLE warranty_claims
  ALTER COLUMN out_of_pocket SET NOT NULL,
  ALTER COLUMN out_of_pocket SET DEFAULT 0;

ALTER TABLE warranty_claims
  ALTER COLUMN amount_saved SET NOT NULL,
  ALTER COLUMN amount_saved SET DEFAULT 0;

ALTER TABLE warranty_claims
  ALTER COLUMN repair_cost SET NOT NULL,
  ALTER COLUMN repair_cost SET DEFAULT 0;

-- ============================================
-- DB-16: CHECK constraint on partner_gifts ensuring is_activated matches status
-- (status = 'activated' AND is_activated = TRUE) OR (status != 'activated' AND is_activated = FALSE)
-- ============================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_partner_gifts_activation_consistency'
      AND conrelid = 'partner_gifts'::regclass
  ) THEN
    ALTER TABLE partner_gifts
      ADD CONSTRAINT chk_partner_gifts_activation_consistency
      CHECK (
        (status = 'activated' AND is_activated = TRUE)
        OR
        (status != 'activated' AND is_activated = FALSE)
      );
  END IF;
END $$;

-- ============================================
-- DB-21: Composite index on items(user_id, warranty_end_date)
-- for warranty expiry queries
-- ============================================
CREATE INDEX IF NOT EXISTS idx_items_user_warranty_end
  ON items(user_id, warranty_end_date);

-- ============================================
-- DB-28 / DB-8: Add documents.updated_at column with trigger
-- ============================================
ALTER TABLE documents
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'update_documents_updated_at'
  ) THEN
    CREATE TRIGGER update_documents_updated_at
      BEFORE UPDATE ON documents
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

-- ============================================
-- Record this migration
-- ============================================
INSERT INTO schema_migrations (name)
VALUES ('011_audit_fixes')
ON CONFLICT (name) DO NOTHING;

COMMIT;
