-- Migration 012: Fix warranty_claims default status
-- The default was incorrectly set to 'completed' instead of 'pending'

DO $$
BEGIN
  -- Fix the default value for warranty_claims.status
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'warranty_claims' AND column_name = 'status'
  ) THEN
    ALTER TABLE warranty_claims ALTER COLUMN status SET DEFAULT 'pending';
    RAISE NOTICE 'Fixed warranty_claims.status default to pending';
  END IF;
END $$;
