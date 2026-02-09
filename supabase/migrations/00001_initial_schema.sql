-- ============================================
-- HavenKeep Initial Schema
-- Migration: 00001_initial_schema.sql
-- Source: docs/havenkeep-ux-spec.md v6 (Data Models section)
-- ============================================

-- ============================================
-- EXTENSIONS
-- ============================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- ENUMS
-- ============================================

CREATE TYPE item_category AS ENUM (
  'refrigerator', 'dishwasher', 'washer', 'dryer',
  'oven_range', 'microwave', 'garbage_disposal', 'range_hood',
  'hvac', 'water_heater', 'furnace', 'water_softener', 'sump_pump',
  'tv', 'computer', 'smart_home',
  'roofing', 'windows', 'doors', 'flooring',
  'plumbing', 'electrical',
  'furniture', 'other'
);

CREATE TYPE item_room AS ENUM (
  'kitchen', 'bathroom', 'master_bedroom', 'bedroom',
  'living_room', 'dining_room', 'laundry',
  'garage', 'basement', 'attic',
  'outdoor', 'hvac_utility', 'office', 'other'
);

CREATE TYPE warranty_type AS ENUM (
  'manufacturer', 'extended', 'store', 'home_warranty'
);

CREATE TYPE warranty_status AS ENUM (
  'active', 'expiring', 'expired'
);

CREATE TYPE auth_provider AS ENUM (
  'email', 'google', 'apple'
);

CREATE TYPE user_plan AS ENUM (
  'free', 'premium'
);

CREATE TYPE home_type AS ENUM (
  'house', 'condo', 'apartment', 'townhouse', 'other'
);

CREATE TYPE document_type AS ENUM (
  'receipt', 'warranty_card', 'manual', 'invoice', 'other'
);

CREATE TYPE notification_type AS ENUM (
  'warranty_expiring', 'warranty_expired',
  'item_added', 'warranty_extended',
  'tip', 'system'
);

CREATE TYPE notification_action AS ENUM (
  'view_item', 'get_protection', 'find_repair'
);

CREATE TYPE partner_type AS ENUM (
  'realtor', 'builder', 'other'
);

CREATE TYPE referral_source AS ENUM (
  'realtor', 'builder', 'user_invite'
);

CREATE TYPE conversion_type AS ENUM (
  'extended_warranty', 'repair_referral', 'premium_sub'
);

CREATE TYPE conversion_status AS ENUM (
  'pending', 'confirmed', 'paid'
);

CREATE TYPE item_added_via AS ENUM (
  'quick_add', 'receipt_scan', 'barcode_scan', 'manual', 'bulk_setup'
);

CREATE TYPE offline_action AS ENUM (
  'create_item', 'update_item', 'delete_item',
  'create_document', 'update_preferences'
);

CREATE TYPE offline_status AS ENUM (
  'pending', 'synced', 'failed'
);

-- ============================================
-- TABLES
-- ============================================

-- 1. USERS
-- Extends Supabase auth.users with app-specific fields.
-- Supabase Auth handles email/password/OAuth — this table stores profile data.
CREATE TABLE public.users (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email       TEXT NOT NULL,
  full_name   TEXT NOT NULL,
  avatar_url  TEXT,
  auth_provider auth_provider NOT NULL DEFAULT 'email',
  plan        user_plan NOT NULL DEFAULT 'free',
  plan_expires_at TIMESTAMPTZ,
  referred_by UUID,  -- FK added after referral_partners table
  referral_code TEXT UNIQUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. HOMES / PROPERTIES
CREATE TABLE public.homes (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  address     TEXT,
  city        TEXT,
  state       TEXT,
  zip         TEXT,
  home_type   home_type DEFAULT 'house',
  move_in_date DATE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. ITEMS
CREATE TABLE public.items (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  home_id           UUID NOT NULL REFERENCES public.homes(id) ON DELETE CASCADE,
  user_id           UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

  -- Product Info
  name              TEXT NOT NULL,
  brand             TEXT,
  model_number      TEXT,
  serial_number     TEXT,
  category          item_category NOT NULL DEFAULT 'other',
  room              item_room,  -- NULLABLE: not all items belong to a room
  product_image_url TEXT,
  barcode           TEXT,

  -- Purchase Info
  purchase_date     DATE NOT NULL,
  store             TEXT,
  price             DECIMAL(10, 2),

  -- Warranty Info
  warranty_months   INTEGER NOT NULL DEFAULT 12,
  warranty_end_date DATE GENERATED ALWAYS AS (purchase_date + (warranty_months * INTERVAL '1 month'))::DATE STORED,
  warranty_type     warranty_type NOT NULL DEFAULT 'manufacturer',
  warranty_provider TEXT,

  -- Meta
  notes             TEXT,
  is_archived       BOOLEAN NOT NULL DEFAULT FALSE,
  added_via         item_added_via NOT NULL DEFAULT 'manual',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. DOCUMENTS
CREATE TABLE public.documents (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  item_id       UUID NOT NULL REFERENCES public.items(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  type          document_type NOT NULL DEFAULT 'other',
  file_url      TEXT NOT NULL,
  file_name     TEXT NOT NULL,
  file_size     INTEGER NOT NULL DEFAULT 0,  -- bytes
  mime_type     TEXT NOT NULL DEFAULT 'application/octet-stream',
  thumbnail_url TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. NOTIFICATIONS
CREATE TABLE public.notifications (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  item_id       UUID REFERENCES public.items(id) ON DELETE SET NULL,
  type          notification_type NOT NULL,
  title         TEXT NOT NULL,
  body          TEXT NOT NULL,
  is_read       BOOLEAN NOT NULL DEFAULT FALSE,
  action_type   notification_action,
  action_data   JSONB,
  scheduled_at  TIMESTAMPTZ NOT NULL,
  sent_at       TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 6. REFERRAL PARTNERS (realtors, builders)
CREATE TABLE public.referral_partners (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email             TEXT NOT NULL UNIQUE,
  full_name         TEXT NOT NULL,
  company_name      TEXT,
  phone             TEXT,
  avatar_url        TEXT,
  partner_type      partner_type NOT NULL DEFAULT 'realtor',
  referral_code     TEXT NOT NULL UNIQUE,
  stripe_account_id TEXT,
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Now add the FK from users.referred_by → referral_partners
ALTER TABLE public.users
  ADD CONSTRAINT fk_users_referred_by
  FOREIGN KEY (referred_by) REFERENCES public.referral_partners(id)
  ON DELETE SET NULL;

-- 7. REFERRALS
CREATE TABLE public.referrals (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  partner_id  UUID NOT NULL REFERENCES public.referral_partners(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  source      referral_source NOT NULL DEFAULT 'realtor',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE(partner_id, user_id)  -- one referral per partner-user pair
);

-- 8. AFFILIATE CONVERSIONS
CREATE TABLE public.affiliate_conversions (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id             UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  item_id             UUID REFERENCES public.items(id) ON DELETE SET NULL,
  partner_id          UUID REFERENCES public.referral_partners(id) ON DELETE SET NULL,
  type                conversion_type NOT NULL,
  provider            TEXT NOT NULL,  -- "Asurion", "OnPoint", "Angi"
  revenue             DECIMAL(10, 2) NOT NULL DEFAULT 0,
  commission          DECIMAL(10, 2) NOT NULL DEFAULT 0,
  partner_commission  DECIMAL(10, 2) NOT NULL DEFAULT 0,
  status              conversion_status NOT NULL DEFAULT 'pending',
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 9. NOTIFICATION PREFERENCES
CREATE TABLE public.notification_preferences (
  user_id                 UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  reminders_enabled       BOOLEAN NOT NULL DEFAULT TRUE,
  first_reminder_days     INTEGER NOT NULL DEFAULT 30,  -- 90, 60, 30, 14, or 7
  reminder_time           TIME NOT NULL DEFAULT '09:00',
  warranty_offers_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  tips_enabled            BOOLEAN NOT NULL DEFAULT TRUE,
  push_enabled            BOOLEAN NOT NULL DEFAULT TRUE,
  email_enabled           BOOLEAN NOT NULL DEFAULT FALSE
);

-- 10. OFFLINE QUEUE (primarily used client-side via drift, but mirrored here for sync)
CREATE TABLE public.offline_queue (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  action      offline_action NOT NULL,
  payload     JSONB NOT NULL,
  status      offline_status NOT NULL DEFAULT 'pending',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  synced_at   TIMESTAMPTZ,
  retry_count INTEGER NOT NULL DEFAULT 0
);

-- 11. CATEGORY DEFAULTS (reference data — populated via seed.sql)
CREATE TABLE public.category_defaults (
  category        item_category PRIMARY KEY,
  default_room    item_room,
  warranty_months INTEGER NOT NULL DEFAULT 12,
  icon            TEXT NOT NULL DEFAULT '📦'
);

-- 12. BRAND SUGGESTIONS (reference data — populated via seed.sql)
CREATE TABLE public.brand_suggestions (
  id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  category  item_category NOT NULL,
  brand     TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,

  UNIQUE(category, brand)
);

-- ============================================
-- INDEXES
-- ============================================

-- Items: most common queries
CREATE INDEX idx_items_user_id ON public.items(user_id);
CREATE INDEX idx_items_home_id ON public.items(home_id);
CREATE INDEX idx_items_warranty_end_date ON public.items(warranty_end_date);
CREATE INDEX idx_items_user_archived ON public.items(user_id, is_archived);
CREATE INDEX idx_items_category ON public.items(category);

-- Homes
CREATE INDEX idx_homes_user_id ON public.homes(user_id);

-- Documents
CREATE INDEX idx_documents_item_id ON public.documents(item_id);
CREATE INDEX idx_documents_user_id ON public.documents(user_id);

-- Notifications
CREATE INDEX idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX idx_notifications_scheduled ON public.notifications(scheduled_at) WHERE sent_at IS NULL;

-- Referrals
CREATE INDEX idx_referrals_partner_id ON public.referrals(partner_id);
CREATE INDEX idx_referrals_user_id ON public.referrals(user_id);

-- Affiliate conversions
CREATE INDEX idx_conversions_user_id ON public.affiliate_conversions(user_id);
CREATE INDEX idx_conversions_partner_id ON public.affiliate_conversions(partner_id);

-- Brand suggestions
CREATE INDEX idx_brand_suggestions_category ON public.brand_suggestions(category, sort_order);

-- ============================================
-- FUNCTIONS
-- ============================================

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Compute warranty_status from warranty_end_date
-- Used in queries/views, not stored (keeps data normalized)
CREATE OR REPLACE FUNCTION public.get_warranty_status(end_date DATE)
RETURNS warranty_status AS $$
BEGIN
  IF end_date < CURRENT_DATE THEN
    RETURN 'expired';
  ELSIF end_date <= CURRENT_DATE + INTERVAL '90 days' THEN
    RETURN 'expiring';
  ELSE
    RETURN 'active';
  END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Count non-archived items for a user (for free plan limit check)
CREATE OR REPLACE FUNCTION public.count_active_items(p_user_id UUID)
RETURNS INTEGER AS $$
BEGIN
  RETURN (
    SELECT COUNT(*)::INTEGER
    FROM public.items
    WHERE user_id = p_user_id AND is_archived = FALSE
  );
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================
-- TRIGGERS
-- ============================================

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER trg_homes_updated_at
  BEFORE UPDATE ON public.homes
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER trg_items_updated_at
  BEFORE UPDATE ON public.items
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- ============================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================

-- Enable RLS on all tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.homes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_partners ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.affiliate_conversions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.offline_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.category_defaults ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.brand_suggestions ENABLE ROW LEVEL SECURITY;

-- USERS: users can only read/update their own profile
CREATE POLICY users_select ON public.users
  FOR SELECT USING (auth.uid() = id);
CREATE POLICY users_update ON public.users
  FOR UPDATE USING (auth.uid() = id);
CREATE POLICY users_insert ON public.users
  FOR INSERT WITH CHECK (auth.uid() = id);

-- HOMES: users can CRUD their own homes
CREATE POLICY homes_select ON public.homes
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY homes_insert ON public.homes
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY homes_update ON public.homes
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY homes_delete ON public.homes
  FOR DELETE USING (auth.uid() = user_id);

-- ITEMS: users can CRUD their own items
CREATE POLICY items_select ON public.items
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY items_insert ON public.items
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY items_update ON public.items
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY items_delete ON public.items
  FOR DELETE USING (auth.uid() = user_id);

-- DOCUMENTS: users can CRUD their own documents
CREATE POLICY documents_select ON public.documents
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY documents_insert ON public.documents
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY documents_update ON public.documents
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY documents_delete ON public.documents
  FOR DELETE USING (auth.uid() = user_id);

-- NOTIFICATIONS: users can read/update their own notifications
CREATE POLICY notifications_select ON public.notifications
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY notifications_update ON public.notifications
  FOR UPDATE USING (auth.uid() = user_id);

-- REFERRAL PARTNERS: public read (for displaying "Referred by" info)
CREATE POLICY referral_partners_select ON public.referral_partners
  FOR SELECT USING (TRUE);

-- REFERRALS: users can see their own referral
CREATE POLICY referrals_select ON public.referrals
  FOR SELECT USING (auth.uid() = user_id);

-- AFFILIATE CONVERSIONS: users can see their own conversions
CREATE POLICY conversions_select ON public.affiliate_conversions
  FOR SELECT USING (auth.uid() = user_id);

-- NOTIFICATION PREFERENCES: users can CRUD their own prefs
CREATE POLICY notif_prefs_select ON public.notification_preferences
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY notif_prefs_insert ON public.notification_preferences
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY notif_prefs_update ON public.notification_preferences
  FOR UPDATE USING (auth.uid() = user_id);

-- OFFLINE QUEUE: users can CRUD their own queue entries
CREATE POLICY offline_queue_all ON public.offline_queue
  FOR ALL USING (auth.uid() = user_id);

-- CATEGORY DEFAULTS: public read (reference data)
CREATE POLICY category_defaults_select ON public.category_defaults
  FOR SELECT USING (TRUE);

-- BRAND SUGGESTIONS: public read (reference data)
CREATE POLICY brand_suggestions_select ON public.brand_suggestions
  FOR SELECT USING (TRUE);

-- ============================================
-- STORAGE BUCKETS
-- ============================================

-- Documents bucket (receipts, warranty cards, manuals, product photos)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'documents',
  'documents',
  FALSE,
  52428800,  -- 50MB
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
);

-- Storage RLS: users can only access their own files
-- Files stored as: documents/{user_id}/{item_id}/{filename}
CREATE POLICY storage_documents_select ON storage.objects
  FOR SELECT USING (
    bucket_id = 'documents'
    AND (storage.foldername(name))[1] = auth.uid()::TEXT
  );

CREATE POLICY storage_documents_insert ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'documents'
    AND (storage.foldername(name))[1] = auth.uid()::TEXT
  );

CREATE POLICY storage_documents_delete ON storage.objects
  FOR DELETE USING (
    bucket_id = 'documents'
    AND (storage.foldername(name))[1] = auth.uid()::TEXT
  );

-- ============================================
-- VIEWS (convenience queries)
-- ============================================

-- Items with computed warranty status
CREATE OR REPLACE VIEW public.items_with_status AS
SELECT
  i.*,
  public.get_warranty_status(i.warranty_end_date) AS warranty_status,
  CASE
    WHEN i.warranty_end_date >= CURRENT_DATE
    THEN i.warranty_end_date - CURRENT_DATE
    ELSE 0
  END AS days_remaining
FROM public.items i
WHERE i.is_archived = FALSE;

-- Dashboard summary per user
CREATE OR REPLACE VIEW public.dashboard_summary AS
SELECT
  i.user_id,
  COUNT(*) FILTER (WHERE public.get_warranty_status(i.warranty_end_date) = 'active') AS active_count,
  COUNT(*) FILTER (WHERE public.get_warranty_status(i.warranty_end_date) = 'expiring') AS expiring_count,
  COUNT(*) FILTER (WHERE public.get_warranty_status(i.warranty_end_date) = 'expired') AS expired_count,
  COALESCE(SUM(i.price) FILTER (WHERE public.get_warranty_status(i.warranty_end_date) IN ('active', 'expiring')), 0) AS total_coverage_value,
  COUNT(*) FILTER (WHERE i.price IS NOT NULL AND public.get_warranty_status(i.warranty_end_date) IN ('active', 'expiring')) AS items_with_price,
  COUNT(*) FILTER (WHERE public.get_warranty_status(i.warranty_end_date) IN ('active', 'expiring')) AS total_active_items
FROM public.items i
WHERE i.is_archived = FALSE
GROUP BY i.user_id;

-- Needs attention: expiring + expired items (for dashboard cards)
CREATE OR REPLACE VIEW public.needs_attention AS
SELECT
  i.*,
  public.get_warranty_status(i.warranty_end_date) AS warranty_status,
  CASE
    WHEN i.warranty_end_date >= CURRENT_DATE
    THEN i.warranty_end_date - CURRENT_DATE
    ELSE -(CURRENT_DATE - i.warranty_end_date)
  END AS days_remaining
FROM public.items i
WHERE i.is_archived = FALSE
  AND public.get_warranty_status(i.warranty_end_date) IN ('expiring', 'expired')
ORDER BY i.warranty_end_date ASC;
