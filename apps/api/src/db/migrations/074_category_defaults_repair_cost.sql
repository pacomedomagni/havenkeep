-- ============================================
-- Migration 074: estimated_repair_cost on category_defaults (Ch08-D017)
-- Date: 2026-04-25
-- Description: items.estimated_repair_cost has been a column since
--   migration 002 but no path ever populated it, so health_score and the
--   savings_feed never had a sensible default to fall back on. Add the
--   per-category default + a small seed; the items create route reads
--   from this table when the user doesn't supply an explicit value.
-- ============================================

ALTER TABLE category_defaults
  ADD COLUMN IF NOT EXISTS estimated_repair_cost DECIMAL(10, 2);

-- Seed reasonable median repair costs (USD). Values from CHC homeowner
-- surveys + Angi 2024 averages. Anything not listed remains NULL and the
-- service falls back to the historical heuristic.
WITH defaults(category, repair_cost) AS (
  VALUES
    ('refrigerator',      850.00),
    ('dishwasher',        450.00),
    ('washer',            500.00),
    ('dryer',             400.00),
    ('oven_range',        450.00),
    ('microwave',         200.00),
    ('garbage_disposal',  175.00),
    ('range_hood',        225.00),
    ('hvac',             1500.00),
    ('water_heater',      900.00),
    ('furnace',          1300.00),
    ('water_softener',    600.00),
    ('sump_pump',         400.00),
    ('tv',                250.00),
    ('computer',          400.00),
    ('smart_home',        125.00),
    ('roofing',          5000.00),
    ('windows',          1200.00),
    ('doors',             800.00),
    ('flooring',         2500.00),
    ('plumbing',          550.00),
    ('electrical',        700.00),
    ('furniture',         150.00),
    ('other',             200.00)
)
INSERT INTO category_defaults (category, estimated_repair_cost)
SELECT d.category::item_category, d.repair_cost FROM defaults d
ON CONFLICT (category) DO UPDATE
  SET estimated_repair_cost = COALESCE(category_defaults.estimated_repair_cost, EXCLUDED.estimated_repair_cost),
      updated_at = NOW();

DO $$
BEGIN
  RAISE NOTICE 'Migration 074 complete: category_defaults.estimated_repair_cost seeded';
END $$;
