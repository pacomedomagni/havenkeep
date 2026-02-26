-- Migration 017: Add license_number to partners table and fix is_active default
-- license_number is accepted by the API validator but was never persisted.
-- is_active should default FALSE so new partners require admin approval.

ALTER TABLE partners
  ADD COLUMN IF NOT EXISTS license_number VARCHAR(100);

-- Change default for new partner registrations: require admin approval
ALTER TABLE partners
  ALTER COLUMN is_active SET DEFAULT FALSE;

DO $$
BEGIN
  RAISE NOTICE 'Migration 017: Added license_number column, changed is_active default to FALSE';
END $$;
