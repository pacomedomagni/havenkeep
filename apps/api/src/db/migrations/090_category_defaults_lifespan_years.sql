-- Migration 090: add lifespan_years to category_defaults; seed from
-- the hardcoded CATEGORY_DEFAULT_LIFESPAN map in items.ts.
--
-- Audit H-C2: items.ts had a CATEGORY_DEFAULT_LIFESPAN object literal
-- (line ~54) used by computeLifespanPercentage. The category_defaults
-- table existed (mig 024) for warranty_months / icon / default_room
-- but didn't carry lifespan, so the lifespan map was a second source
-- of truth divergent from the per-category data. An admin updating
-- category_defaults via /admin/categories/:cat/defaults couldn't
-- change the lifespan — only a code deploy could.
--
-- Add the column, seed from the hardcoded values, and let the route
-- read from the DB. The hardcoded map will be removed in the same
-- commit as this migration; the seed below is the one-time backfill
-- so behavior is identical post-migration.

ALTER TABLE category_defaults
  ADD COLUMN IF NOT EXISTS lifespan_years INTEGER;

-- Sanity bound — matches the items.expected_lifespan_years CHECK in
-- mig 041 so the two columns can't drift in opposite directions.
ALTER TABLE category_defaults
  DROP CONSTRAINT IF EXISTS chk_category_defaults_lifespan_years;
ALTER TABLE category_defaults
  ADD CONSTRAINT chk_category_defaults_lifespan_years
  CHECK (lifespan_years IS NULL OR lifespan_years BETWEEN 1 AND 100);

-- Seed from the hardcoded CATEGORY_DEFAULT_LIFESPAN map in items.ts.
-- Same values, same categories — this is a backfill, not a behavior
-- change. category_defaults is keyed by item_category enum, not VARCHAR,
-- so the cast below applies.
WITH defaults(category, years) AS (
  VALUES
    ('appliance',   12),
    ('electronics',  5),
    ('furniture',   15),
    ('hvac',        15),
    ('plumbing',    20),
    ('roofing',     25),
    ('flooring',    15),
    ('outdoor',     10),
    ('other',       10)
)
INSERT INTO category_defaults (category, lifespan_years)
SELECT d.category::item_category, d.years FROM defaults d
ON CONFLICT (category) DO UPDATE
  SET lifespan_years = COALESCE(category_defaults.lifespan_years, EXCLUDED.lifespan_years),
      updated_at = NOW();

DO $$
BEGIN
  RAISE NOTICE 'Migration 090 complete: category_defaults.lifespan_years seeded (H-C2)';
END $$;
