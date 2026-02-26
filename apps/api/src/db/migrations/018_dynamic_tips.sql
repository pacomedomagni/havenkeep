-- Migration 018: Create dynamic tips table and seed with contextual tips
-- Replaces the hardcoded tips array in the notifications route with a
-- database-driven system that supports categories and activation toggling.

CREATE TABLE IF NOT EXISTS tips (
  id            SERIAL PRIMARY KEY,
  category      VARCHAR(50)  NOT NULL,
  trigger_condition VARCHAR(100),
  content       TEXT         NOT NULL,
  is_active     BOOLEAN      DEFAULT TRUE,
  created_at    TIMESTAMPTZ  DEFAULT NOW()
);

-- Index for the most common query pattern: active tips filtered by category
CREATE INDEX IF NOT EXISTS idx_tips_active_category ON tips (category) WHERE is_active = TRUE;

-- ──────────────────────────────────────────────
-- Seed data: 24 tips across 6 categories
-- ──────────────────────────────────────────────

INSERT INTO tips (category, trigger_condition, content) VALUES
  -- new_user: shown when user has zero items
  ('new_user',    'no_items',          'Add your first item to start tracking warranties and maintenance schedules.'),
  ('new_user',    'no_items',          'Start by adding the most expensive item in your home — it likely has the most to lose without warranty tracking.'),
  ('new_user',    'no_items',          'Snap a photo of a receipt and add your first item — it only takes a minute.'),

  -- maintenance: shown when user has never completed a maintenance task
  ('maintenance', 'no_maintenance',    'Schedule your first maintenance task to keep your items in top shape.'),
  ('maintenance', 'no_maintenance',    'Regular maintenance can double the lifespan of household appliances — set up your first task today.'),
  ('maintenance', 'no_maintenance',    'HVAC filters, fridge coils, dryer vents — pick one and create your first maintenance reminder.'),

  -- warranty: shown when user has expired warranties
  ('warranty',    'expired_warranty',  'Check out extended warranty options for items with expired coverage.'),
  ('warranty',    'expired_warranty',  'Some manufacturers offer post-warranty repair programs — review your expired items for options.'),
  ('warranty',    'expired_warranty',  'Expired warranty? Contact the manufacturer anyway — many offer goodwill repairs for recent expirations.'),

  -- warranty: shown when user has active warranties
  ('warranty',    'active_warranty',   'Keep your receipts and warranty cards digitized for easy access.'),
  ('warranty',    'active_warranty',   'Register products with manufacturers to activate full warranty coverage.'),
  ('warranty',    'active_warranty',   'Consider bundling items under home warranty plans for broader protection.'),

  -- general: rotated by day of year as default fallback
  ('general',     NULL,                'Take photos of serial numbers for quick reference during warranty claims.'),
  ('general',     NULL,                'Set a reminder to review your items at the start of each season.'),
  ('general',     NULL,                'Group similar items by room or category for easier management.'),
  ('general',     NULL,                'Keep digital copies of all receipts — paper fades over time.'),
  ('general',     NULL,                'Review your maintenance schedule weekly to stay on top of tasks.'),
  ('general',     NULL,                'Update item details whenever you move them to a different room.'),
  ('general',     NULL,                'Check for product recalls periodically to keep your household safe.'),
  ('general',     NULL,                'Add notes about any repairs or modifications to your items.'),
  ('general',     NULL,                'Back up your warranty documents in cloud storage for extra safety.'),
  ('general',     NULL,                'Log the model number — it speeds up support calls and parts ordering.'),
  ('general',     NULL,                'Clean and maintain appliances regularly to extend their lifespan.'),
  ('general',     NULL,                'Track energy usage of major appliances to spot issues early.'),
  ('general',     NULL,                'Share your inventory with household members so everyone stays informed.'),
  ('general',     NULL,                'Label power cords and cables — it saves time when troubleshooting.'),

  -- organization: general-pool tips about staying organized
  ('organization', NULL,               'Create separate rooms or zones in your inventory to mirror your actual living space.'),
  ('organization', NULL,               'Archive items you no longer own instead of deleting them — you may need the records later.'),

  -- power_user: shown contextually for engaged users (many items)
  ('power_user', 'many_items',         'Use tags or notes to track which items are covered by your homeowners insurance.'),
  ('power_user', 'many_items',         'Export your inventory periodically as a backup in case you ever need it for an insurance claim.');

DO $$
BEGIN
  RAISE NOTICE 'Migration 018: Created tips table and seeded 30 dynamic tips';
END $$;
