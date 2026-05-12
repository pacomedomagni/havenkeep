-- ============================================
-- HavenKeep PostgreSQL Schema
-- For DigitalOcean Managed Database
-- ============================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Enums.
-- S3-F: every CREATE is idempotent so re-running schema.sql against an
-- otherwise-bootstrapped DB (e.g. after the schema_version row got dropped
-- and the runner replays the base schema) is a no-op. ALTER TYPE values
-- added by later migrations are preserved because we never drop the type.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'item_category') THEN
    CREATE TYPE item_category AS ENUM (
      'refrigerator', 'dishwasher', 'washer', 'dryer',
      'oven_range', 'microwave', 'garbage_disposal', 'range_hood',
      'hvac', 'water_heater', 'furnace', 'water_softener', 'sump_pump',
      'tv', 'computer', 'smart_home',
      'roofing', 'windows', 'doors', 'flooring',
      'plumbing', 'electrical',
      'furniture', 'other'
    );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'item_room') THEN
    CREATE TYPE item_room AS ENUM (
      'kitchen', 'bathroom', 'master_bedroom', 'bedroom',
      'living_room', 'dining_room', 'laundry',
      'garage', 'basement', 'attic',
      'outdoor', 'hvac_utility', 'office', 'other'
    );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'warranty_type') THEN
    CREATE TYPE warranty_type AS ENUM (
      'manufacturer', 'extended', 'store', 'home_warranty'
    );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_plan') THEN
    CREATE TYPE user_plan AS ENUM (
      'free', 'premium'
    );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'home_type') THEN
    CREATE TYPE home_type AS ENUM (
      'house', 'condo', 'apartment', 'townhouse', 'other'
    );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'document_type') THEN
    CREATE TYPE document_type AS ENUM (
      'receipt', 'warranty_card', 'manual', 'invoice', 'other'
    );
  END IF;
END $$;

-- Users table
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email VARCHAR(255) NOT NULL UNIQUE,
  password_hash VARCHAR(255),
  full_name VARCHAR(255) NOT NULL,
  avatar_url TEXT,
  auth_provider VARCHAR(20) NOT NULL DEFAULT 'email',
  plan user_plan NOT NULL DEFAULT 'free',
  plan_expires_at TIMESTAMPTZ,
  referred_by UUID,
  referral_code VARCHAR(64),
  is_admin BOOLEAN NOT NULL DEFAULT FALSE,
  email_verified BOOLEAN NOT NULL DEFAULT FALSE,
  apple_user_id VARCHAR(255) UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_plan ON users(plan);
CREATE INDEX IF NOT EXISTS idx_users_referral_code ON users(referral_code);
CREATE INDEX IF NOT EXISTS idx_users_apple_user_id ON users(apple_user_id) WHERE apple_user_id IS NOT NULL;

-- Homes table
CREATE TABLE IF NOT EXISTS homes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  address TEXT,
  city VARCHAR(100),
  state VARCHAR(50),
  zip VARCHAR(20),
  home_type home_type DEFAULT 'house',
  move_in_date DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_homes_user_id ON homes(user_id);

-- Items table
CREATE TABLE IF NOT EXISTS items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  home_id UUID NOT NULL REFERENCES homes(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  
  -- Product info
  name VARCHAR(255) NOT NULL,
  brand VARCHAR(100),
  model_number VARCHAR(100),
  serial_number VARCHAR(100),
  category item_category NOT NULL DEFAULT 'other',
  room item_room,
  product_image_url TEXT,
  barcode VARCHAR(100),
  
  -- Purchase info
  purchase_date DATE NOT NULL,
  store VARCHAR(100),
  price DECIMAL(10, 2),
  
  -- Warranty info
  warranty_months INTEGER NOT NULL DEFAULT 12,
  warranty_end_date DATE NOT NULL,
  warranty_type warranty_type NOT NULL DEFAULT 'manufacturer',
  warranty_provider VARCHAR(100),
  added_via VARCHAR(32) NOT NULL DEFAULT 'manual',
  
  -- Meta
  notes TEXT,
  is_archived BOOLEAN NOT NULL DEFAULT FALSE,
  archived_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_items_user_id ON items(user_id);
CREATE INDEX IF NOT EXISTS idx_items_home_id ON items(home_id);
CREATE INDEX IF NOT EXISTS idx_items_warranty_end ON items(warranty_end_date);
CREATE INDEX IF NOT EXISTS idx_items_category ON items(category);

-- Documents table
CREATE TABLE IF NOT EXISTS documents (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type document_type NOT NULL DEFAULT 'other',
  -- Bucket-relative object key. URL is built on read (audit Ch02-F040).
  object_key TEXT NOT NULL,
  file_name VARCHAR(255) NOT NULL,
  file_size INTEGER NOT NULL DEFAULT 0,
  mime_type VARCHAR(100) NOT NULL DEFAULT 'application/octet-stream',
  thumbnail_key TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_documents_item_id ON documents(item_id);
CREATE INDEX IF NOT EXISTS idx_documents_user_id ON documents(user_id);

-- Refresh tokens table (for JWT auth)
CREATE TABLE IF NOT EXISTS refresh_tokens (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token VARCHAR(500) NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_token ON refresh_tokens(token);

-- Push notification tokens
CREATE TABLE IF NOT EXISTS user_push_tokens (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  fcm_token VARCHAR(512) NOT NULL,
  platform VARCHAR(20) NOT NULL DEFAULT 'unknown',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, fcm_token)
);

CREATE INDEX IF NOT EXISTS idx_user_push_tokens_user_id ON user_push_tokens(user_id);

-- Email verification tokens
CREATE TABLE IF NOT EXISTS email_verification_tokens (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token VARCHAR(255) NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_email_verification_user_id ON email_verification_tokens(user_id);

-- Password reset tokens
CREATE TABLE IF NOT EXISTS password_reset_tokens (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token VARCHAR(255) NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  used BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_password_reset_user_id ON password_reset_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_password_reset_token ON password_reset_tokens(token);

-- Triggers for updated_at
-- search_path-pinned to defeat schema-shadowing attacks (Ch00-DB006).
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- DO blocks make the trigger declarations idempotent so re-running schema.sql
-- against a partially-bootstrapped DB doesn't ERROR on duplicate triggers
-- (Ch00-DB003). Migration 045's schema_version table is the canonical "is
-- this done?" marker — these IF NOT EXISTS guards are belt-and-braces.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_users_updated_at') THEN
    CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_homes_updated_at') THEN
    CREATE TRIGGER update_homes_updated_at BEFORE UPDATE ON homes
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_items_updated_at') THEN
    CREATE TRIGGER update_items_updated_at BEFORE UPDATE ON items
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_user_push_tokens_updated_at') THEN
    CREATE TRIGGER update_user_push_tokens_updated_at BEFORE UPDATE ON user_push_tokens
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

-- Ch00-DB001: documents.updated_at trigger was missing from schema.sql.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_documents_updated_at') THEN
    CREATE TRIGGER update_documents_updated_at BEFORE UPDATE ON documents
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

-- Views for analytics
CREATE OR REPLACE VIEW user_stats AS
SELECT
  u.id,
  u.email,
  u.full_name,
  u.plan,
  u.created_at,
  COUNT(DISTINCT i.id) AS total_items,
  COALESCE(SUM(i.price), 0) AS total_value,
  MAX(i.created_at) AS last_item_created,
  MAX(i.updated_at) AS last_activity
FROM users u
LEFT JOIN items i ON i.user_id = u.id AND i.is_archived = FALSE
GROUP BY u.id, u.email, u.full_name, u.plan, u.created_at;
