-- ============================================
-- Migration 072: Notification digest outbox (Ch04-F034)
-- Date: 2026-04-25
-- Description: Mig 063 added `notification_preferences.digest_minutes`; this
--   migration adds the queue table that the cron actually flushes. A
--   notification destined for a digest user lands in `notification_outbox`
--   with `flush_at = NOW() + digest_minutes` instead of being pushed
--   immediately. The cron job claims rows whose `flush_at <= NOW()`,
--   coalesces per-user into a single push (count + summary), and writes
--   them to `notification_history` with `delivery_status = 'delivered'`.
--
--   Why a separate table (vs reusing notification_history with a 'queued'
--   status): notification_history is the immutable audit trail; coalescing
--   would mean inserting and then mutating, which the audit-log work in
--   migration 065 explicitly forbids. The outbox is mutable scratch space.
-- ============================================

CREATE TABLE IF NOT EXISTS notification_outbox (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- The notification's intended type + body. We don't reference the
  -- template_id directly so a template change after enqueue but before
  -- flush doesn't cause a mid-flight rendering swap.
  type notification_type NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB DEFAULT '{}'::jsonb,

  -- The bucket that gates flushing. Computed at enqueue time as
  -- `NOW() + digest_minutes` so the user's preference at enqueue is
  -- the one that wins (mid-flight pref change doesn't re-bucket).
  flush_at TIMESTAMPTZ NOT NULL,

  -- Claim window (claimer holds for ~30s before retrying so a cron crash
  -- doesn't strand items).
  claimed_at TIMESTAMPTZ,

  -- The notification_history row this outbox row landed in (NULL until
  -- flushed). Lets the cron skip already-coalesced rows on retry.
  flushed_into_id UUID REFERENCES notification_history(id) ON DELETE SET NULL,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index drives the per-user coalescing query (`WHERE flush_at <= NOW()
-- ORDER BY user_id`).
CREATE INDEX IF NOT EXISTS idx_notification_outbox_due
  ON notification_outbox(flush_at)
  WHERE flushed_into_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_notification_outbox_user_due
  ON notification_outbox(user_id, flush_at)
  WHERE flushed_into_id IS NULL;

DO $$
BEGIN
  RAISE NOTICE 'Migration 072 complete: notification_outbox table created';
END $$;
