-- Migration 016: Add soft-delete columns to users table
-- Required by account deletion with 30-day cooling-off period (DELETE /users/me)
-- and account recovery (POST /users/me/recover).

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deletion_scheduled_for TIMESTAMPTZ;

-- Index for the scheduled deletion cleanup job
CREATE INDEX IF NOT EXISTS idx_users_deletion_scheduled
  ON users (deletion_scheduled_for)
  WHERE deletion_scheduled_for IS NOT NULL;

DO $$
BEGIN
  RAISE NOTICE 'Migration 016: Added deleted_at and deletion_scheduled_for to users table';
END $$;
