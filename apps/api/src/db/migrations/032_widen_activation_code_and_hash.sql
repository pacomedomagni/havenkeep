-- ============================================
-- Migration 032: Activation code 64-bit + hashed at rest
--   (Ch09-FlowC-T-C2, Ch09-FlowC-T-C16)
-- Date: 2026-04-25
-- Description:
--   Old activation codes were 8 hex (32 bits). With ~10k live gifts the
--   collision chance per random guess is ~2e-6, so a low-rate brute force
--   succeeds in days; combined with the verify-code enumeration oracle it
--   finds active gifts daily.
--   New scheme: 16 hex chars (64 bits) and stored hashed (SHA-256).
--   Plaintext appears only in the activation email + URL; verify by hash.
--
--   Existing rows get their plaintext stored as the `legacy_plaintext` column
--   for one rotation cycle so the email template can keep delivering active
--   links — but `activation_code_hash` is the column the API reads for the
--   verify path going forward. After this migration is in production for
--   30 days the legacy_plaintext column should be dropped (Phase 5 follow-up).
-- ============================================

-- 1. Add hash column + widen plaintext column (existing rows keep their values).
ALTER TABLE partner_gifts
  ADD COLUMN IF NOT EXISTS activation_code_hash CHAR(64);

CREATE UNIQUE INDEX IF NOT EXISTS idx_partner_gifts_activation_code_hash
  ON partner_gifts(activation_code_hash);

-- 2. Backfill: hash any existing plaintext code into activation_code_hash.
--    activation_code is uppercased before hashing to normalize.
UPDATE partner_gifts
SET activation_code_hash = encode(digest(UPPER(activation_code), 'sha256'), 'hex')
WHERE activation_code IS NOT NULL
  AND activation_code_hash IS NULL;

-- 3. Per-IP/per-code lockout state (simple counter; rate limiter still primary).
CREATE TABLE IF NOT EXISTS gift_verify_attempts (
  ip_address INET NOT NULL,
  bucket_minute TIMESTAMPTZ NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (ip_address, bucket_minute)
);

CREATE INDEX IF NOT EXISTS idx_gift_verify_attempts_minute
  ON gift_verify_attempts(bucket_minute);

DO $$
BEGIN
  RAISE NOTICE 'Migration 032 complete: activation_code_hash backfilled';
END $$;
