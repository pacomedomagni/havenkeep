-- Migration 090: add lifespan_years to category_defaults; seed for
-- every value of the item_category enum.
--
-- Audit H-C2: items.ts had a CATEGORY_DEFAULT_LIFESPAN object literal
-- (line ~54) used by computeLifespanPercentage. The category_defaults
-- table existed (mig 024) for warranty_months / icon / default_room
-- but didn't carry lifespan, so the lifespan map was a second source
-- of truth divergent from the per-category data. An admin updating
-- category_defaults via /admin/categories/:cat/defaults couldn't
-- change the lifespan — only a code deploy could.
--
-- Add the column, seed sensible values for every value of the
-- item_category enum, and let the route read from the DB. Items.ts
-- removes its hardcoded map in the same change.
--
-- Audit-of-the-audit (Phase-5 follow-up): the original mig 090 seeded
-- against a 9-category coarse taxonomy (`appliance`, `electronics`,
-- `outdoor`, ...) that does NOT exist in the item_category enum —
-- the enum has 44 fine-grained values like `refrigerator`,
-- `dishwasher`, `tv`, etc. The cast `'appliance'::item_category`
-- raised 22P02 on every fresh bootstrap, blocking the migration
-- runner at file 090. Discovered when standing the docker-compose
-- stack up locally for the first time post-Phase-5 merge. This
-- rewrite seeds against the real enum values.

ALTER TABLE category_defaults
  ADD COLUMN IF NOT EXISTS lifespan_years INTEGER;

-- Sanity bound — matches the items.expected_lifespan_years CHECK in
-- mig 041 so the two columns can't drift in opposite directions.
ALTER TABLE category_defaults
  DROP CONSTRAINT IF EXISTS chk_category_defaults_lifespan_years;
ALTER TABLE category_defaults
  ADD CONSTRAINT chk_category_defaults_lifespan_years
  CHECK (lifespan_years IS NULL OR lifespan_years BETWEEN 1 AND 100);

-- Seed every enum value. Numbers come from manufacturer-published
-- expected lifespans (Energy Star / NAR / NAHB). Rounded to whole
-- years because the column is INTEGER and the percentage gauge in
-- computeLifespanPercentage is itself rounded to whole percent.
WITH defaults(category, years) AS (
  VALUES
    -- Major appliances
    ('refrigerator',        13),
    ('freezer',             15),
    ('dishwasher',           9),
    ('washer',              11),
    ('dryer',               13),
    ('oven_range',          15),
    ('microwave',            9),
    ('garbage_disposal',    12),
    ('range_hood',          14),
    ('trash_compactor',      6),
    ('wine_cooler',         12),
    -- HVAC / water / mechanical
    ('hvac',                15),
    ('water_heater',        10),
    ('furnace',             18),
    ('water_softener',      12),
    ('sump_pump',           10),
    ('air_purifier',         8),
    ('dehumidifier',         8),
    ('ceiling_fan',         15),
    -- Electronics
    ('tv',                   7),
    ('computer',             5),
    ('smart_home',           7),
    ('home_theater',         8),
    ('printer',              5),
    ('networking',           5),
    ('camera',               5),
    -- Structural / construction
    ('roofing',             25),
    ('windows',             25),
    ('doors',               30),
    ('flooring',            20),
    ('plumbing',            40),
    ('electrical',          40),
    -- Furniture & lighting
    ('furniture',           15),
    ('lighting',            12),
    -- Safety / security
    ('smoke_detector',      10),
    ('security_system',     12),
    ('garage_door_opener',  15),
    -- Outdoor / tools
    ('power_tools',         10),
    ('lawn_mower',           9),
    ('pool_equipment',      10),
    ('grill',               12),
    -- Small / misc
    ('vacuum',               8),
    ('coffee_maker',         5),
    ('other',               10)
)
INSERT INTO category_defaults (category, lifespan_years)
SELECT d.category::item_category, d.years FROM defaults d
ON CONFLICT (category) DO UPDATE
  SET lifespan_years = COALESCE(category_defaults.lifespan_years, EXCLUDED.lifespan_years),
      updated_at = NOW();

DO $$
DECLARE
  unseeded_count INTEGER;
BEGIN
  -- Defensive guard: if the enum gains a new value in a future
  -- migration but mig 090 isn't extended, surface it now instead of
  -- silently leaving lifespan_years NULL (which degrades to "no
  -- default" in computeLifespanPercentage).
  SELECT COUNT(*) INTO unseeded_count
  FROM (
    SELECT unnest(enum_range(NULL::item_category)) AS v
  ) e
  LEFT JOIN category_defaults c ON c.category::text = e.v::text
  WHERE c.lifespan_years IS NULL;

  IF unseeded_count > 0 THEN
    RAISE WARNING 'Migration 090: % item_category value(s) have no lifespan_years seed — extend the seed map', unseeded_count;
  END IF;

  RAISE NOTICE 'Migration 090 complete: category_defaults.lifespan_years seeded (H-C2)';
END $$;
