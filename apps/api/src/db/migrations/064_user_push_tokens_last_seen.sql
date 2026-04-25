-- ============================================
-- Migration 064: user_push_tokens.last_seen_at (Ch04-F079)
-- Date: 2026-04-25
-- Description:
--   FCM tokens stick around forever even after the device hasn't checked in
--   for months — a removed-and-reinstalled app gets a fresh token and the
--   stale one keeps generating registration-token-not-registered errors.
--   Tag rows with last_seen_at on every refresh and let the cleanup job
--   purge tokens older than 60 days.
-- ============================================

ALTER TABLE user_push_tokens
  ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_user_push_tokens_last_seen
  ON user_push_tokens (last_seen_at);

DO $$
BEGIN
  RAISE NOTICE 'Migration 064 complete: user_push_tokens.last_seen_at';
END $$;
