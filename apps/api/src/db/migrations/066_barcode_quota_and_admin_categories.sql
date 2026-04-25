-- ============================================
-- Migration 066: barcode per-user daily quota + admin category writes
--   (Ch04-F098, F103)
-- Date: 2026-04-25
-- Description:
--   Two endpoints get hardened in this migration:
--
--   1. (Ch04-F103) The shared 100/day upcitemdb quota lets a single chatty
--      user starve the rest. Track per-user daily counts so the route can
--      enforce 10/day on free, 50/day on premium.
--
--   2. (Ch04-F098) category_defaults had no admin write route; the table is
--      seeded from migration 024 and never updated. Add an updated_by /
--      updated_at pair so admin POST/PUT can record provenance.
-- ============================================

-- ── 1. Per-user barcode quota ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS barcode_lookup_quota (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- UTC day (date) — quota resets at midnight UTC
  quota_date DATE NOT NULL,
  lookups INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, quota_date),
  CONSTRAINT chk_barcode_quota_lookups_nonneg CHECK (lookups >= 0)
);

CREATE INDEX IF NOT EXISTS idx_barcode_quota_date
  ON barcode_lookup_quota (quota_date);

COMMENT ON TABLE barcode_lookup_quota IS
  'Per-user daily quota for /barcode/lookup. Reset at UTC midnight.';

-- ── 2. category_defaults updated_by/updated_at ─────────────────────────
ALTER TABLE category_defaults
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS updated_by UUID REFERENCES users(id) ON DELETE SET NULL;

DO $$
BEGIN
  RAISE NOTICE 'Migration 066 complete: barcode quota table + category_defaults provenance';
END $$;
