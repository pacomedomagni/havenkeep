-- Add missing user columns and item tracking fields

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS auth_provider VARCHAR(20) NOT NULL DEFAULT 'email',
  ADD COLUMN IF NOT EXISTS referred_by UUID,
  ADD COLUMN IF NOT EXISTS referral_code VARCHAR(64);

CREATE INDEX IF NOT EXISTS idx_users_referral_code ON users(referral_code);

ALTER TABLE items
  ADD COLUMN IF NOT EXISTS added_via VARCHAR(32) NOT NULL DEFAULT 'manual';

-- Push notification tokens table
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

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgname = 'update_user_push_tokens_updated_at'
  ) THEN
    CREATE TRIGGER update_user_push_tokens_updated_at
      BEFORE UPDATE ON user_push_tokens
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;
