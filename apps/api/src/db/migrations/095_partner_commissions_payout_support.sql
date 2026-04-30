-- Migration 095: support on-demand payouts + the 30-day auto-approve cron.
--
-- Two adds:
--
-- 1. Partial index on (status, created_at) covering 'pending' rows. The
--    auto-approve cron sweeps `WHERE status = 'pending' AND created_at <
--    NOW() - INTERVAL '30 days'`. On a partner_commissions table with
--    millions of paid+cancelled rows the sweep would full-scan; the
--    partial index keeps it cheap.
--
-- 2. partners.last_payout_requested_at — surfaces the timestamp of the
--    last self-service payout sweep so the dashboard can show "next
--    payout available" cooldown UX. Strictly informational; the API
--    enforces no cooldown today (partners can hammer "Request payout"
--    if they want, since each Stripe transfer is small + idempotent).
--    Column exists so the dashboard has something to render — it can
--    light up cooldown UX later without a schema change.

CREATE INDEX IF NOT EXISTS idx_partner_commissions_pending_age
  ON partner_commissions (created_at)
  WHERE status = 'pending';

ALTER TABLE partners
  ADD COLUMN IF NOT EXISTS last_payout_requested_at TIMESTAMPTZ;

DO $$
BEGIN
  RAISE NOTICE 'Migration 095 complete: payout support (auto-approve index + last_payout_requested_at column)';
END $$;
