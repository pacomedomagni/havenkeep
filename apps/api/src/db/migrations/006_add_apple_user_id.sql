-- ============================================
-- Add apple_user_id column to users table
-- Required for Apple OAuth lookup when Apple
-- does not provide email on subsequent sign-ins
-- ============================================

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS apple_user_id VARCHAR(255) UNIQUE;

-- Index for fast lookup by apple_user_id during OAuth
CREATE INDEX IF NOT EXISTS idx_users_apple_user_id
  ON users(apple_user_id)
  WHERE apple_user_id IS NOT NULL;
