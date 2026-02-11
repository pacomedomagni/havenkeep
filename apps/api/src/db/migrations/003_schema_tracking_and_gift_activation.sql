-- ============================================
-- HavenKeep Migration 003
-- Date: 2026-02-11
-- Description: Adds schema migration tracking table
--              and activation_code/activation_url to partner_gifts
-- ============================================

-- 1. SCHEMA MIGRATION TRACKING
CREATE TABLE IF NOT EXISTS schema_migrations (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) UNIQUE NOT NULL,
  applied_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE schema_migrations IS 'Tracks which database migrations have been applied';

-- Record previous migrations
INSERT INTO schema_migrations (name) VALUES
  ('001_initial_schema'),
  ('002_enhanced_features'),
  ('003_schema_tracking_and_gift_activation')
ON CONFLICT (name) DO NOTHING;

-- 2. ADD ACTIVATION COLUMNS TO PARTNER_GIFTS
ALTER TABLE partner_gifts
  ADD COLUMN IF NOT EXISTS activation_code VARCHAR(20),
  ADD COLUMN IF NOT EXISTS activation_url TEXT;

-- Generate activation codes for existing gifts that don't have one
UPDATE partner_gifts
SET activation_code = UPPER(SUBSTRING(id::text, 1, 4) || '-' || SUBSTRING(id::text, 5, 4))
WHERE activation_code IS NULL;

-- Add index for activation code lookups
CREATE INDEX IF NOT EXISTS idx_partner_gifts_activation_code ON partner_gifts(activation_code);

COMMENT ON COLUMN partner_gifts.activation_code IS 'Unique code homebuyer enters to activate gift';
COMMENT ON COLUMN partner_gifts.activation_url IS 'Direct activation URL sent to homebuyer';

-- 3. ADD COMPOSITE INDEXES FOR COMMON QUERY PATTERNS
CREATE INDEX IF NOT EXISTS idx_items_user_archived ON items(user_id, is_archived);
CREATE INDEX IF NOT EXISTS idx_items_home_warranty_archived ON items(home_id, warranty_end_date, is_archived);
CREATE INDEX IF NOT EXISTS idx_warranty_claims_user_status ON warranty_claims(user_id, status);

-- ============================================
-- MIGRATION COMPLETE
-- ============================================

DO $$
BEGIN
  RAISE NOTICE 'Migration 003 completed successfully at %', NOW();
  RAISE NOTICE 'Added: schema_migrations table, activation columns on partner_gifts, composite indexes';
END $$;
