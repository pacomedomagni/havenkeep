-- ============================================
-- Migration 024: Create category_defaults and brand_suggestions tables
-- Date: 2026-03-04
-- Description: The API routes GET /categories/defaults and
--   GET /categories/:category/brands query these tables, but they were
--   never created in any prior migration.
-- ============================================

-- ============================================
-- category_defaults — reference table for per-category default values
-- Columns derived from CategoryDefault model (shared_models):
--   category, default_room, warranty_months, icon
-- ============================================
CREATE TABLE IF NOT EXISTS category_defaults (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  category item_category NOT NULL UNIQUE,
  default_room item_room,
  warranty_months INTEGER NOT NULL DEFAULT 12,
  icon VARCHAR(16) NOT NULL DEFAULT '📦',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Trigger to keep updated_at current
CREATE TRIGGER update_category_defaults_updated_at
  BEFORE UPDATE ON category_defaults
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Index on category for fast lookups (UNIQUE already creates one, but explicit for clarity)
-- The UNIQUE constraint on category already provides an index.

COMMENT ON TABLE category_defaults IS 'Per-category default values (warranty duration, default room, icon) used by quick-add flow';

-- ============================================
-- brand_suggestions — pre-populated brand names per category
-- Columns derived from BrandSuggestion model (shared_models):
--   id, category, brand, sort_order
-- The API route orders by sort_order ASC and filters by category.
-- ============================================
CREATE TABLE IF NOT EXISTS brand_suggestions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  category item_category NOT NULL,
  brand VARCHAR(255) NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Trigger to keep updated_at current
CREATE TRIGGER update_brand_suggestions_updated_at
  BEFORE UPDATE ON brand_suggestions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Composite index for the query: WHERE category = $1 ORDER BY sort_order ASC
CREATE INDEX idx_brand_suggestions_category_sort
  ON brand_suggestions(category, sort_order);

-- Prevent duplicate brand names within the same category
ALTER TABLE brand_suggestions
  ADD CONSTRAINT uq_brand_suggestions_category_brand UNIQUE (category, brand);

COMMENT ON TABLE brand_suggestions IS 'Pre-populated brand suggestions per item category, used by quick-add and manual-entry brand autocomplete';

DO $$
BEGIN
  RAISE NOTICE 'Migration 024: Created category_defaults and brand_suggestions tables';
END $$;
