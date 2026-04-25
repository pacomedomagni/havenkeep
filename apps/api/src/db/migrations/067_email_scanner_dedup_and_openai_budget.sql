-- ============================================
-- Migration 067: email scanner Gmail message dedup + OpenAI cost cap
--   (Ch04-F063, F067)
-- Date: 2026-04-25
-- Description:
--   1. (Ch04-F067) The same Gmail message would match multiple of our
--      sender-domain queries (e.g. amazon.com order + shipment confirmation
--      separately) and double-bill the user's OpenAI budget. Track scanned
--      message ids per user so a re-encounter is a no-op.
--
--   2. (Ch04-F063) Add a per-user-day cost cap projection on top of the
--      `openai_usage` ledger introduced in migration 050. The actual cap
--      enforcement happens in code; this view powers the lookup.
-- ============================================

-- ── 1. Gmail message dedup ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS email_scanner_seen_messages (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider VARCHAR(16) NOT NULL,
  -- Gmail message-id (or Outlook internetMessageId). 998 chars covers RFC
  -- 5322 worst-case while staying under PG's btree key limit.
  provider_message_id VARCHAR(998) NOT NULL,
  -- The scan that first saw this message — for diagnostics.
  first_seen_scan_id UUID REFERENCES email_scans(id) ON DELETE SET NULL,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, provider, provider_message_id)
);

CREATE INDEX IF NOT EXISTS idx_email_scanner_seen_first_seen
  ON email_scanner_seen_messages (first_seen_at);

COMMENT ON TABLE email_scanner_seen_messages IS
  'Idempotency keyed on the provider message id so re-scans + overlapping queries do not double-bill OpenAI.';

-- ── 2. Per-user-day OpenAI cost projection ─────────────────────────────
CREATE OR REPLACE VIEW openai_user_daily_cost AS
  SELECT user_id,
         (created_at AT TIME ZONE 'UTC')::date AS day,
         feature,
         SUM(cost_micros)::bigint AS cost_micros,
         SUM(total_tokens)::bigint AS tokens
    FROM openai_usage
   GROUP BY 1, 2, 3;

COMMENT ON VIEW openai_user_daily_cost IS
  'Daily per-user OpenAI cost rollup. Used to enforce a per-day cap before kicking off another scan.';

DO $$
BEGIN
  RAISE NOTICE 'Migration 067 complete: scanner dedup + openai daily cost view';
END $$;
