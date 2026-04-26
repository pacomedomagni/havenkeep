-- ============================================
-- Migration 051: per-user OpenAI cost attribution + receipt-scan idempotency
--   (Ch02-F040 — documents.file_url → documents.object_key)
--   (Ch02-F046 — receipt OCR cost matrix)
--   (Ch09-FlowA-T-A10 — receipts/scan idempotency keys)
-- Date: 2026-04-25
-- Description:
--   Phase 6 introduces per-user OpenAI cost tracking so we can surface a
--   monthly soft-cap before an attacker (or a runaway client) burns the
--   entire OpenAI budget on a single account. We also persist
--   Idempotency-Key results so a double-tap from the mobile client doesn't
--   double-bill the user's quota.
-- ============================================

-- ── 1. Per-user OpenAI usage ledger ────────────────────────────────────
--
-- One row per OpenAI call. Aggregating by user_id + day gives the per-user
-- daily spend; aggregating by feature gives the cost matrix used in
-- Ch09-CostMatrix.
CREATE TABLE IF NOT EXISTS openai_usage (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- Logical feature: 'receipt_scan', 'email_scan', etc. Keeps cost attributed
  -- to the right product surface even if we share an OpenAI org.
  feature VARCHAR(64) NOT NULL,
  model VARCHAR(64) NOT NULL,
  prompt_tokens INTEGER NOT NULL DEFAULT 0,
  completion_tokens INTEGER NOT NULL DEFAULT 0,
  total_tokens INTEGER NOT NULL DEFAULT 0,
  -- USD * 1_000_000 (micro-cents) so we can keep cost as bigint without
  -- floating-point drift. parseFloat→DECIMAL drift was the audit reason
  -- (Ch04-F004) for not just storing as DECIMAL.
  cost_micros BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_openai_usage_user_created
  ON openai_usage (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_openai_usage_feature_created
  ON openai_usage (feature, created_at DESC);

COMMENT ON TABLE openai_usage IS
  'Per-user OpenAI cost attribution. Powers the daily per-user cap that prevents a single account from burning the whole budget.';

-- ── 2. Idempotency-Key store for receipts/scan ─────────────────────────
--
-- Receipt scans are user-pays-by-API-call: a double-tap on the mobile client
-- previously burned two OpenAI calls and double-counted in the cost ledger.
-- Caller passes Idempotency-Key (UUID); server looks up `(user_id, key)`,
-- and if a row exists with the same request_hash, the prior `response_json`
-- is replayed instead of a new OpenAI call. A different hash for the same
-- key is rejected with 409 (RFC 9110 §17 / Stripe-style).
CREATE TABLE IF NOT EXISTS receipt_scan_idempotency (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- Caller-supplied UUID. We deliberately don't constrain to UUID format;
  -- some clients send opaque tokens.
  idempotency_key VARCHAR(255) NOT NULL,
  -- sha256(canonical_request_json). Mismatch on the same key = 409.
  request_hash CHAR(64) NOT NULL,
  -- The previously-returned response, replayed verbatim.
  response_json JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- TTL handled by a periodic cleanup; keep 24h of replay window.
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
  PRIMARY KEY (user_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_receipt_scan_idempotency_expires
  ON receipt_scan_idempotency (expires_at);

COMMENT ON TABLE receipt_scan_idempotency IS
  'Replay cache for /receipts/scan. Same Idempotency-Key + same request body returns the prior response without burning another OpenAI call.';

-- ── 3. documents.file_url → documents.object_key ──────────────────────
--
-- Audit Ch02-F040: storing the full public URL coupled the DB to the
-- current MinIO hostname; rotating MINIO_PUBLIC_URL silently broke every
-- existing document link. Going forward, the DB stores only the bucket-
-- relative object key, and `getPublicUrl(object_key)` builds the URL at
-- read time.
--
-- Guarded with information_schema lookups so a fresh install bootstrapped
-- from `schema.sql` (which captures the post-rename column names) doesn't
-- re-attempt the RENAME and fail with "undefined column".
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'documents' AND column_name = 'file_url'
  ) THEN
    ALTER TABLE documents RENAME COLUMN file_url TO object_key;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'documents' AND column_name = 'thumbnail_url'
  ) THEN
    ALTER TABLE documents RENAME COLUMN thumbnail_url TO thumbnail_key;
  END IF;
END $$;

COMMENT ON COLUMN documents.object_key IS
  'Bucket-relative object key. Public URL is built at read time via getPublicUrl().';

COMMENT ON COLUMN documents.thumbnail_key IS
  'Bucket-relative thumbnail object key. Public URL is built at read time.';

DO $$
BEGIN
  RAISE NOTICE 'Migration 051 complete: openai_usage + receipt_scan_idempotency installed; documents.file_url → documents.object_key';
END $$;
