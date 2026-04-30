-- Migration 096: add 'partner.payout_request' to the audit_action enum.
--
-- Required by the new partner self-service payout endpoint (POST
-- /api/v1/partners/me/payouts). The endpoint records an audit_logs row
-- summarizing the sweep (paid/failed counts, total). Without this enum
-- value, the INSERT fails with PG 22P02 (invalid_text_representation),
-- which an outer WARN-mapper translates to a 400 — the partner sees a
-- generic validation error and the payout never logs.
--
-- ALTER TYPE ADD VALUE cannot run inside a transaction; the migration
-- runner auto-detects this pattern and executes the file outside its
-- BEGIN/COMMIT wrapper.

ALTER TYPE audit_action ADD VALUE IF NOT EXISTS 'partner.payout_request';

DO $$
BEGIN
  RAISE NOTICE 'Migration 096 complete: audit_action gained partner.payout_request';
END $$;
