-- ============================================
-- HavenKeep Enhanced Features Migration
-- Version: 002
-- Date: 2026-02-11
-- Description: Adds warranty claims, maintenance tracking,
--              partner program, extended warranties, analytics
-- ============================================

-- ============================================
-- 1. WARRANTY CLAIMS TRACKING
-- ============================================

CREATE TABLE IF NOT EXISTS warranty_claims (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- Claim details
  claim_date DATE NOT NULL DEFAULT CURRENT_DATE,
  issue_description TEXT,
  repair_description TEXT,

  -- Financial impact
  repair_cost DECIMAL(10, 2) NOT NULL DEFAULT 0,
  amount_saved DECIMAL(10, 2) NOT NULL DEFAULT 0,
  out_of_pocket DECIMAL(10, 2) DEFAULT 0,

  -- Status tracking
  status VARCHAR(50) NOT NULL DEFAULT 'completed',
  filed_with VARCHAR(100),
  claim_number VARCHAR(100),

  -- Meta
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_warranty_claims_user_id ON warranty_claims(user_id);
CREATE INDEX idx_warranty_claims_item_id ON warranty_claims(item_id);
CREATE INDEX idx_warranty_claims_date ON warranty_claims(claim_date DESC);
CREATE INDEX idx_warranty_claims_status ON warranty_claims(status);

COMMENT ON TABLE warranty_claims IS 'Tracks warranty claims filed by users to calculate ROI and savings';

-- ============================================
-- 2. PREVENTIVE MAINTENANCE SYSTEM
-- ============================================

CREATE TABLE IF NOT EXISTS maintenance_schedules (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  category item_category NOT NULL,
  task_name VARCHAR(255) NOT NULL,
  description TEXT,

  -- Frequency
  frequency_months INTEGER NOT NULL,
  frequency_label VARCHAR(50), -- 'Monthly', 'Quarterly', 'Annually', etc.

  -- Task details
  estimated_duration_minutes INTEGER,
  difficulty VARCHAR(20) DEFAULT 'easy', -- 'easy', 'medium', 'hard'
  prevents_cost DECIMAL(10, 2),

  -- Resources
  how_to_url TEXT,
  video_url TEXT,
  tools_needed TEXT[],

  -- Meta
  is_required_for_warranty BOOLEAN DEFAULT FALSE,
  priority INTEGER DEFAULT 5,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_maintenance_schedules_category ON maintenance_schedules(category);

COMMENT ON TABLE maintenance_schedules IS 'Master list of maintenance tasks by appliance category';

CREATE TABLE IF NOT EXISTS maintenance_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  schedule_id UUID REFERENCES maintenance_schedules(id) ON DELETE SET NULL,

  -- Task details
  task_name VARCHAR(255) NOT NULL,
  completed_date DATE NOT NULL DEFAULT CURRENT_DATE,

  -- Details
  notes TEXT,
  duration_minutes INTEGER,
  cost DECIMAL(10, 2) DEFAULT 0,

  -- Meta
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_maintenance_history_user_id ON maintenance_history(user_id);
CREATE INDEX idx_maintenance_history_item_id ON maintenance_history(item_id);
CREATE INDEX idx_maintenance_history_date ON maintenance_history(completed_date DESC);

COMMENT ON TABLE maintenance_history IS 'Logs completed maintenance tasks by users';

-- ============================================
-- 3. EMAIL SCANNING
-- ============================================

CREATE TYPE email_scan_status AS ENUM ('pending', 'scanning', 'completed', 'failed');

CREATE TABLE IF NOT EXISTS email_scans (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- Provider info
  provider VARCHAR(50) NOT NULL, -- 'gmail', 'outlook'
  provider_email VARCHAR(255),

  -- Scan details
  scan_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  date_range_start DATE,
  date_range_end DATE,
  emails_scanned INTEGER DEFAULT 0,
  receipts_found INTEGER DEFAULT 0,
  items_imported INTEGER DEFAULT 0,

  -- Status
  status email_scan_status DEFAULT 'pending',
  error_message TEXT,
  completed_at TIMESTAMPTZ,

  -- Meta
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_email_scans_user_id ON email_scans(user_id);
CREATE INDEX idx_email_scans_status ON email_scans(status);
CREATE INDEX idx_email_scans_date ON email_scans(scan_date DESC);

COMMENT ON TABLE email_scans IS 'Tracks email scanning operations for receipt import';

-- ============================================
-- 4. PARTNER PROGRAM
-- ============================================

CREATE TYPE partner_type_enum AS ENUM ('realtor', 'builder', 'contractor', 'other');
CREATE TYPE partner_tier AS ENUM ('basic', 'premium', 'platinum');
CREATE TYPE commission_status AS ENUM ('pending', 'approved', 'paid', 'cancelled');

CREATE TABLE IF NOT EXISTS partners (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- Partner info
  partner_type partner_type_enum NOT NULL DEFAULT 'realtor',
  company_name VARCHAR(255),
  phone VARCHAR(50),
  website VARCHAR(255),

  -- Branding
  brand_color VARCHAR(7), -- hex color like #FF5733
  logo_url TEXT,
  subscription_tier partner_tier DEFAULT 'basic',

  -- Settings
  default_message TEXT,
  default_premium_months INTEGER DEFAULT 6,

  -- Stripe Connect (for payouts)
  stripe_account_id VARCHAR(255),
  stripe_onboarded BOOLEAN DEFAULT FALSE,

  -- Status
  is_active BOOLEAN DEFAULT TRUE,
  is_verified BOOLEAN DEFAULT FALSE,

  -- Meta
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_partners_user_id ON partners(user_id);
CREATE INDEX idx_partners_type ON partners(partner_type);
CREATE INDEX idx_partners_active ON partners(is_active);
CREATE INDEX idx_partners_stripe ON partners(stripe_account_id);

COMMENT ON TABLE partners IS 'Realtor and builder partner profiles';

CREATE TYPE gift_status AS ENUM ('created', 'sent', 'activated', 'expired');

CREATE TABLE IF NOT EXISTS partner_gifts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  partner_id UUID NOT NULL REFERENCES partners(id) ON DELETE CASCADE,

  -- Homebuyer info
  homebuyer_email VARCHAR(255) NOT NULL,
  homebuyer_name VARCHAR(255) NOT NULL,
  homebuyer_phone VARCHAR(50),
  home_address TEXT,
  closing_date DATE,

  -- Gift details
  premium_months INTEGER NOT NULL DEFAULT 6,
  custom_message TEXT,

  -- Activation
  status gift_status DEFAULT 'created',
  is_activated BOOLEAN DEFAULT FALSE,
  activated_at TIMESTAMPTZ,
  activated_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  expires_at TIMESTAMPTZ,

  -- Billing
  amount_charged DECIMAL(10, 2) NOT NULL,
  stripe_charge_id VARCHAR(255),

  -- Analytics
  email_opened_at TIMESTAMPTZ,
  app_download_at TIMESTAMPTZ,
  first_item_added_at TIMESTAMPTZ,

  -- Meta
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_partner_gifts_partner_id ON partner_gifts(partner_id);
CREATE INDEX idx_partner_gifts_email ON partner_gifts(homebuyer_email);
CREATE INDEX idx_partner_gifts_activated_user ON partner_gifts(activated_user_id);
CREATE INDEX idx_partner_gifts_status ON partner_gifts(status);
CREATE INDEX idx_partner_gifts_closing_date ON partner_gifts(closing_date);

COMMENT ON TABLE partner_gifts IS 'Closing gifts given to homebuyers by partners';

CREATE TYPE commission_type AS ENUM ('gift', 'warranty_sale', 'referral', 'subscription');

CREATE TABLE IF NOT EXISTS partner_commissions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  partner_id UUID NOT NULL REFERENCES partners(id) ON DELETE CASCADE,

  -- Commission details
  type commission_type NOT NULL,
  amount DECIMAL(10, 2) NOT NULL,
  description TEXT,

  -- Status
  status commission_status DEFAULT 'pending',
  approved_at TIMESTAMPTZ,
  paid_at TIMESTAMPTZ,

  -- References
  reference_id UUID, -- gift_id, warranty_purchase_id, etc.
  reference_type VARCHAR(50),

  -- Payout
  stripe_transfer_id VARCHAR(255),
  payout_method VARCHAR(50) DEFAULT 'stripe_connect',

  -- Meta
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_partner_commissions_partner_id ON partner_commissions(partner_id);
CREATE INDEX idx_partner_commissions_status ON partner_commissions(status);
CREATE INDEX idx_partner_commissions_type ON partner_commissions(type);
CREATE INDEX idx_partner_commissions_created ON partner_commissions(created_at DESC);

COMMENT ON TABLE partner_commissions IS 'Commission tracking and payouts for partners';

-- ============================================
-- 5. EXTENDED WARRANTY MARKETPLACE
-- ============================================

CREATE TYPE warranty_purchase_status AS ENUM ('active', 'expired', 'cancelled', 'claimed');

CREATE TABLE IF NOT EXISTS warranty_purchases (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- Provider details
  provider VARCHAR(100) NOT NULL, -- 'Asurion', 'Choice Home Warranty', etc.
  plan_name VARCHAR(255) NOT NULL,
  external_policy_id VARCHAR(255),

  -- Coverage details
  duration_months INTEGER NOT NULL,
  starts_at DATE NOT NULL,
  expires_at DATE NOT NULL,
  coverage_details JSONB,

  -- Pricing
  price DECIMAL(10, 2) NOT NULL,
  deductible DECIMAL(10, 2) DEFAULT 0,
  claim_limit DECIMAL(10, 2),

  -- Commission tracking
  commission_amount DECIMAL(10, 2),
  commission_rate DECIMAL(5, 4),

  -- Purchase details
  purchase_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  stripe_payment_intent_id VARCHAR(255),

  -- Status
  status warranty_purchase_status DEFAULT 'active',
  cancelled_at TIMESTAMPTZ,
  cancellation_reason TEXT,

  -- Meta
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_warranty_purchases_user_id ON warranty_purchases(user_id);
CREATE INDEX idx_warranty_purchases_item_id ON warranty_purchases(item_id);
CREATE INDEX idx_warranty_purchases_status ON warranty_purchases(status);
CREATE INDEX idx_warranty_purchases_expires ON warranty_purchases(expires_at);

COMMENT ON TABLE warranty_purchases IS 'Extended warranty purchases through the marketplace';

-- ============================================
-- 6. USER ANALYTICS
-- ============================================

CREATE TABLE IF NOT EXISTS user_analytics (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,

  -- Engagement metrics
  last_active_at TIMESTAMPTZ,
  total_app_opens INTEGER DEFAULT 0,
  total_sessions INTEGER DEFAULT 0,
  avg_session_duration_seconds INTEGER DEFAULT 0,

  -- Health score
  current_health_score INTEGER DEFAULT 0,
  health_score_history JSONB DEFAULT '[]'::jsonb,

  -- Savings tracking
  total_warranty_savings DECIMAL(10, 2) DEFAULT 0,
  total_preventive_savings DECIMAL(10, 2) DEFAULT 0,
  total_claims_filed INTEGER DEFAULT 0,
  total_maintenance_completed INTEGER DEFAULT 0,

  -- Feature usage
  email_scans_completed INTEGER DEFAULT 0,
  items_added_manually INTEGER DEFAULT 0,
  items_added_via_email INTEGER DEFAULT 0,
  items_added_via_barcode INTEGER DEFAULT 0,
  documents_uploaded INTEGER DEFAULT 0,
  reports_generated INTEGER DEFAULT 0,

  -- Engagement flags
  has_activated_gift BOOLEAN DEFAULT FALSE,
  has_completed_onboarding BOOLEAN DEFAULT FALSE,
  has_added_first_item BOOLEAN DEFAULT FALSE,
  has_scanned_email BOOLEAN DEFAULT FALSE,
  has_filed_claim BOOLEAN DEFAULT FALSE,

  -- Meta
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_user_analytics_user_id ON user_analytics(user_id);
CREATE INDEX idx_user_analytics_last_active ON user_analytics(last_active_at DESC);
CREATE INDEX idx_user_analytics_health_score ON user_analytics(current_health_score DESC);

COMMENT ON TABLE user_analytics IS 'User engagement and behavior analytics';

-- ============================================
-- 7. NOTIFICATIONS SYSTEM
-- ============================================

CREATE TYPE notification_type AS ENUM (
  'warranty_expiring',
  'warranty_expired',
  'maintenance_due',
  'claim_opportunity',
  'health_score_update',
  'gift_received',
  'partner_commission',
  'system'
);

CREATE TABLE IF NOT EXISTS notification_templates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(255) NOT NULL UNIQUE,
  type notification_type NOT NULL,

  -- Template content
  title_template TEXT NOT NULL,
  body_template TEXT NOT NULL,

  -- Actions (JSON array of action objects)
  actions JSONB DEFAULT '[]'::jsonb,

  -- Settings
  is_active BOOLEAN DEFAULT TRUE,
  priority INTEGER DEFAULT 5,

  -- Meta
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notification_templates_type ON notification_templates(type);

COMMENT ON TABLE notification_templates IS 'Reusable notification templates with variables';

CREATE TABLE IF NOT EXISTS notification_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  template_id UUID REFERENCES notification_templates(id) ON DELETE SET NULL,

  -- Related entities
  item_id UUID REFERENCES items(id) ON DELETE CASCADE,
  gift_id UUID REFERENCES partner_gifts(id) ON DELETE SET NULL,

  -- Content
  type notification_type NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB DEFAULT '{}'::jsonb,

  -- Tracking
  sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  delivered_at TIMESTAMPTZ,
  opened_at TIMESTAMPTZ,
  action_taken VARCHAR(100),
  action_taken_at TIMESTAMPTZ,

  -- Platform
  platform VARCHAR(20), -- 'mobile', 'web', 'email'
  fcm_message_id VARCHAR(255),

  -- Meta
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notification_history_user_id ON notification_history(user_id);
CREATE INDEX idx_notification_history_sent ON notification_history(sent_at DESC);
CREATE INDEX idx_notification_history_opened ON notification_history(opened_at);
CREATE INDEX idx_notification_history_type ON notification_history(type);

COMMENT ON TABLE notification_history IS 'Log of all notifications sent to users';

-- ============================================
-- 8. SAVINGS FEED (PUBLIC SOCIAL PROOF)
-- ============================================

CREATE TABLE IF NOT EXISTS savings_feed (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- Anonymized data
  user_city VARCHAR(100),
  user_state VARCHAR(50),

  -- Savings details
  amount_saved DECIMAL(10, 2) NOT NULL,
  item_category item_category,
  claim_type VARCHAR(100), -- 'Warranty claim', 'Preventive maintenance', etc.

  -- Display
  display_text TEXT, -- Pre-generated for performance

  -- Meta
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_savings_feed_created_at ON savings_feed(created_at DESC);
CREATE INDEX idx_savings_feed_category ON savings_feed(item_category);

COMMENT ON TABLE savings_feed IS 'Public feed of savings for social proof (anonymized)';

-- ============================================
-- 9. ENHANCED ITEMS TABLE
-- ============================================

-- Add new columns to existing items table
ALTER TABLE items
  ADD COLUMN IF NOT EXISTS estimated_repair_cost DECIMAL(10, 2),
  ADD COLUMN IF NOT EXISTS expected_lifespan_years INTEGER,
  ADD COLUMN IF NOT EXISTS installation_date DATE,
  ADD COLUMN IF NOT EXISTS last_maintenance_date DATE,
  ADD COLUMN IF NOT EXISTS next_maintenance_due DATE;

COMMENT ON COLUMN items.estimated_repair_cost IS 'Average repair cost for this item type';
COMMENT ON COLUMN items.expected_lifespan_years IS 'Typical lifespan for this category';

-- ============================================
-- 10. TRIGGERS
-- ============================================

CREATE TRIGGER update_warranty_claims_updated_at
  BEFORE UPDATE ON warranty_claims
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_maintenance_schedules_updated_at
  BEFORE UPDATE ON maintenance_schedules
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_partners_updated_at
  BEFORE UPDATE ON partners
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_partner_gifts_updated_at
  BEFORE UPDATE ON partner_gifts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_partner_commissions_updated_at
  BEFORE UPDATE ON partner_commissions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_warranty_purchases_updated_at
  BEFORE UPDATE ON warranty_purchases
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_analytics_updated_at
  BEFORE UPDATE ON user_analytics
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_notification_templates_updated_at
  BEFORE UPDATE ON notification_templates
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- 11. FUNCTIONS & PROCEDURES
-- ============================================

-- Function to calculate warranty health score
CREATE OR REPLACE FUNCTION calculate_health_score(p_user_id UUID)
RETURNS INTEGER AS $$
DECLARE
  v_score INTEGER := 0;
  v_item_count INTEGER;
  v_active_warranties INTEGER;
  v_documented_items INTEGER;
  v_total_items INTEGER;
  v_maintenance_count INTEGER;
  v_expired_count INTEGER;
BEGIN
  -- Get item counts
  SELECT COUNT(*) INTO v_total_items
  FROM items WHERE user_id = p_user_id AND is_archived = FALSE;

  IF v_total_items = 0 THEN
    RETURN 0;
  END IF;

  -- Base points: Items tracked (max 30 points)
  v_score := v_score + LEAST(v_total_items * 2, 30);

  -- Active warranties (max 25 points)
  SELECT COUNT(*) INTO v_active_warranties
  FROM items
  WHERE user_id = p_user_id
    AND is_archived = FALSE
    AND warranty_end_date >= CURRENT_DATE;

  v_score := v_score + LEAST(v_active_warranties * 3, 25);

  -- Documents uploaded (max 20 points)
  SELECT COUNT(DISTINCT i.id) INTO v_documented_items
  FROM items i
  JOIN documents d ON d.item_id = i.id
  WHERE i.user_id = p_user_id AND i.is_archived = FALSE;

  v_score := v_score + LEAST((v_documented_items::FLOAT / v_total_items * 20)::INTEGER, 20);

  -- Maintenance completed (max 15 points)
  SELECT COUNT(*) INTO v_maintenance_count
  FROM maintenance_history
  WHERE user_id = p_user_id
    AND completed_date >= CURRENT_DATE - INTERVAL '6 months';

  v_score := v_score + LEAST(v_maintenance_count, 15);

  -- Penalty for expired warranties (max -10 points)
  SELECT COUNT(*) INTO v_expired_count
  FROM items
  WHERE user_id = p_user_id
    AND is_archived = FALSE
    AND warranty_end_date < CURRENT_DATE;

  v_score := v_score - LEAST(v_expired_count * 2, 10);

  -- Ensure score is between 0 and 100
  v_score := GREATEST(0, LEAST(v_score, 100));

  -- Update user analytics
  UPDATE user_analytics
  SET current_health_score = v_score,
      health_score_history = health_score_history || jsonb_build_object(
        'date', CURRENT_DATE,
        'score', v_score
      )
  WHERE user_id = p_user_id;

  RETURN v_score;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_health_score IS 'Calculates warranty health score (0-100) for a user';

-- Function to get dashboard stats
CREATE OR REPLACE FUNCTION get_dashboard_stats(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_stats JSONB;
BEGIN
  SELECT jsonb_build_object(
    'total_value', COALESCE(SUM(price), 0),
    'total_items', COUNT(*),
    'active_warranties', COUNT(*) FILTER (WHERE warranty_end_date >= CURRENT_DATE),
    'expiring_soon', COUNT(*) FILTER (WHERE warranty_end_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '90 days'),
    'expired', COUNT(*) FILTER (WHERE warranty_end_date < CURRENT_DATE),
    'total_repair_value', COALESCE(SUM(estimated_repair_cost), 0),
    'health_score', (SELECT current_health_score FROM user_analytics WHERE user_id = p_user_id)
  ) INTO v_stats
  FROM items
  WHERE user_id = p_user_id AND is_archived = FALSE;

  RETURN v_stats;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_dashboard_stats IS 'Returns dashboard statistics for a user';

-- ============================================
-- 12. SEED DATA - MAINTENANCE SCHEDULES
-- ============================================

INSERT INTO maintenance_schedules (category, task_name, description, frequency_months, frequency_label, estimated_duration_minutes, difficulty, prevents_cost, priority) VALUES
  -- HVAC
  ('hvac', 'Replace Air Filter', 'Replace HVAC air filter to maintain efficiency and air quality', 3, 'Quarterly', 5, 'easy', 200.00, 10),
  ('hvac', 'Annual Professional Inspection', 'Professional HVAC inspection and tune-up', 12, 'Annually', 60, 'hard', 500.00, 9),
  ('hvac', 'Clean Outdoor Unit', 'Clean debris and dirt from outdoor AC unit', 6, 'Semi-annually', 15, 'easy', 150.00, 7),

  -- Water Heater
  ('water_heater', 'Flush Tank', 'Drain and flush tank to remove sediment buildup', 12, 'Annually', 30, 'medium', 300.00, 8),
  ('water_heater', 'Test Pressure Relief Valve', 'Test TPR valve for proper operation', 12, 'Annually', 5, 'easy', 200.00, 6),

  -- Refrigerator
  ('refrigerator', 'Clean Condenser Coils', 'Vacuum or brush condenser coils to improve efficiency', 6, 'Semi-annually', 10, 'easy', 150.00, 7),
  ('refrigerator', 'Check Door Seals', 'Inspect and clean door gaskets for proper seal', 12, 'Annually', 5, 'easy', 100.00, 5),

  -- Dishwasher
  ('dishwasher', 'Clean Filter', 'Remove and clean dishwasher filter', 1, 'Monthly', 5, 'easy', 80.00, 6),
  ('dishwasher', 'Run Cleaning Cycle', 'Run dishwasher with cleaning tablet', 3, 'Quarterly', 120, 'easy', 50.00, 4),

  -- Washer
  ('washer', 'Clean Drum and Gasket', 'Wipe down drum and door gasket, run cleaning cycle', 1, 'Monthly', 10, 'easy', 120.00, 7),
  ('washer', 'Check Hoses', 'Inspect water supply hoses for cracks or leaks', 6, 'Semi-annually', 5, 'easy', 200.00, 8),

  -- Dryer
  ('dryer', 'Clean Lint Trap', 'Remove lint from trap after each use', 1, 'After each use', 1, 'easy', 300.00, 10),
  ('dryer', 'Clean Vent Duct', 'Clean dryer vent duct to prevent fire hazard', 12, 'Annually', 30, 'medium', 500.00, 9),

  -- Garbage Disposal
  ('garbage_disposal', 'Clean with Ice', 'Run ice cubes to clean blades', 1, 'Monthly', 2, 'easy', 50.00, 5),
  ('garbage_disposal', 'Deep Clean', 'Clean with baking soda and vinegar', 3, 'Quarterly', 5, 'easy', 30.00, 4)
ON CONFLICT DO NOTHING;

-- ============================================
-- 13. SEED DATA - NOTIFICATION TEMPLATES
-- ============================================

INSERT INTO notification_templates (name, type, title_template, body_template, actions) VALUES
  (
    'warranty_expiring_30_days',
    'warranty_expiring',
    '⚠️ {{item_name}} warranty expires in {{days_left}} days',
    'Worth ${{estimated_cost}} in free repairs. Don''t lose it!',
    '[
      {"id": "file_claim", "title": "File a Claim", "icon": "claim"},
      {"id": "extend", "title": "Extend Warranty", "icon": "extend"},
      {"id": "remind_later", "title": "Remind Me in 7 Days", "icon": "snooze"}
    ]'::jsonb
  ),
  (
    'maintenance_due',
    'maintenance_due',
    '🔧 Time to {{task_name}}',
    '{{item_name}} needs maintenance. Takes {{duration}} minutes, prevents ${{prevents_cost}} in repairs.',
    '[
      {"id": "mark_done", "title": "Mark as Done", "icon": "check"},
      {"id": "remind_later", "title": "Remind Tomorrow", "icon": "snooze"},
      {"id": "learn_how", "title": "How-To Guide", "icon": "help"}
    ]'::jsonb
  ),
  (
    'health_score_improved',
    'health_score_update',
    '🎉 Your health score increased to {{score}}!',
    'You''re doing great! You''re now in the top {{percentile}}% of homeowners.',
    '[
      {"id": "view_dashboard", "title": "View Dashboard", "icon": "dashboard"}
    ]'::jsonb
  ),
  (
    'gift_received',
    'gift_received',
    '🎁 {{partner_name}} gave you a gift!',
    '{{premium_months}} months of HavenKeep Premium. Tap to activate.',
    '[
      {"id": "activate_gift", "title": "Activate Gift", "icon": "gift"}
    ]'::jsonb
  )
ON CONFLICT DO NOTHING;

-- ============================================
-- 14. GRANT PERMISSIONS (if using separate DB user)
-- ============================================

-- Uncomment if using a specific database user
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO havenkeep_api;
-- GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO havenkeep_api;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO havenkeep_api;

-- ============================================
-- MIGRATION COMPLETE
-- ============================================

-- Log migration completion
DO $$
BEGIN
  RAISE NOTICE 'Migration 002 completed successfully at %', NOW();
  RAISE NOTICE 'Added tables: warranty_claims, maintenance_schedules, maintenance_history, email_scans, partners, partner_gifts, partner_commissions, warranty_purchases, user_analytics, notification_templates, notification_history, savings_feed';
  RAISE NOTICE 'Added functions: calculate_health_score, get_dashboard_stats';
END $$;
