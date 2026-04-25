-- ============================================
-- Migration 034: Preserve user plan across suspend / soft-delete
--   (Ch12-R002, Ch12-R003, Ch01-F057)
-- Date: 2026-04-25
-- Description: Admin suspend and self-delete both unconditionally moved the
--   user's plan to 'free', so unsuspend / recover stranded paid customers on
--   the free tier. Capture the plan at suspend / delete time so it can be
--   restored on the inverse path. Stripe entitlement and RC sync still need
--   to be reconciled — that lives in the route, not this migration.
-- ============================================

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS plan_before_suspend VARCHAR(32),
  ADD COLUMN IF NOT EXISTS plan_before_delete  VARCHAR(32);

-- Backfill: any user currently in plan='suspended' loses the prior plan
-- forever (we have no way to recover it). Mark the column NULL so unsuspend
-- treats them as 'free' explicitly. New suspends populate it correctly.

CREATE INDEX IF NOT EXISTS idx_users_plan_before_suspend
  ON users(plan_before_suspend)
  WHERE plan_before_suspend IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_users_plan_before_delete
  ON users(plan_before_delete)
  WHERE plan_before_delete IS NOT NULL;

DO $$
BEGIN
  RAISE NOTICE 'Migration 034 complete: plan_before_suspend / plan_before_delete columns added';
END $$;
