-- Migration 076: seed estimated_repair_cost for the remaining categories
--   (S2-L / Ch08-D017)
-- Description:
--   Migration 074 seeded 24 of the 44 ItemCategory enum values. The
--   remaining 20 (air_purifier through trash_compactor) returned NULL,
--   which makes the items create route fall back to the legacy heuristic
--   instead of using the canonical default.
--
-- Sources: same as mig 074 — Angi 2024 averages cross-referenced against
-- HomeAdvisor median repair costs and BLS service-call data. These are
-- mid-market estimates, not warranties; the items create route can be
-- overridden by an explicit user-supplied value.

WITH defaults(category, repair_cost) AS (
  VALUES
    ('air_purifier',         150.00),
    ('vacuum',               150.00),
    ('ceiling_fan',          175.00),
    ('smoke_detector',        50.00),
    ('security_system',      350.00),
    ('garage_door_opener',   325.00),
    ('power_tools',          150.00),
    ('lawn_mower',           250.00),
    ('pool_equipment',       650.00),
    ('grill',                225.00),
    ('coffee_maker',          80.00),
    ('home_theater',         400.00),
    ('printer',              150.00),
    ('networking',           175.00),
    ('camera',               225.00),
    ('lighting',             125.00),
    ('dehumidifier',         275.00),
    ('freezer',              500.00),
    ('wine_cooler',          425.00),
    ('trash_compactor',      275.00)
)
INSERT INTO category_defaults (category, estimated_repair_cost)
SELECT d.category::item_category, d.repair_cost FROM defaults d
ON CONFLICT (category) DO UPDATE
  SET estimated_repair_cost = COALESCE(category_defaults.estimated_repair_cost, EXCLUDED.estimated_repair_cost),
      updated_at = NOW();

DO $$
BEGIN
  RAISE NOTICE 'Migration 076 complete: remaining category_defaults seeded';
END $$;
