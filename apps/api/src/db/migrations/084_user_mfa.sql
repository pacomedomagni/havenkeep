-- Migration 084: TOTP MFA enrollment + login challenge tables.
--
-- Audit S-C2: there is no second factor on any account, including admin
-- and partner roles that handle Stripe Connect payouts and gift-creation
-- charges. Combined with per-IP-only rate-limit (S-C3), credential
-- stuffing from a 100-IP botnet is unbounded against any chosen victim.
--
-- This migration adds the storage:
--
-- user_mfa_factors:
--   - factor_type: only 'totp' for now; column is the natural extension
--     point if/when WebAuthn ships (separate code change).
--   - secret_ciphertext / iv / tag: AES-256-GCM encrypted via the
--     OAUTH_TOKEN_ENCRYPTION_SECRET (oauth-encryption.ts) — same key
--     mechanism used for Gmail/Outlook OAuth refresh tokens. The TOTP
--     base32 secret is sensitive — possessing it equals possessing the
--     factor.
--   - verified_at: NULL until the user successfully verifies the first
--     code. Pre-verified factors are never honored at login (one-step
--     enrollment-and-login would let an attacker who already has the
--     password enroll their own factor).
--
-- user_mfa_backup_codes:
--   - code_hash: HMAC-SHA-256 keyed by the refresh-token JWT secret
--     (utils/token-hash.ts hashToken), matching the rest of the
--     opaque-bearer-token storage convention (Ch01-F019). Single-use:
--     used_at marks consumption.

CREATE TABLE IF NOT EXISTS user_mfa_factors (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  factor_type VARCHAR(16) NOT NULL CHECK (factor_type IN ('totp')),
  -- AES-256-GCM-encrypted base32 TOTP secret. The columns mirror the
  -- existing user_oauth_integrations encrypted-token shape (mig 038)
  -- so utils/oauth-encryption.ts encryptToken/decryptToken work without
  -- modification. Base64 strings.
  secret_ciphertext TEXT,
  secret_iv VARCHAR(32),
  secret_tag VARCHAR(32),
  -- The label the user typed at enrollment (e.g. "Google Authenticator").
  -- Optional; only used in the UI for "your registered factors" listing.
  label VARCHAR(64),
  verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- A user can have at most one verified factor of each type. Pre-
-- verified factors don't count — re-enrollment overwrites the
-- unverified row.
CREATE UNIQUE INDEX IF NOT EXISTS uq_user_mfa_factors_verified
  ON user_mfa_factors(user_id, factor_type)
  WHERE verified_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_user_mfa_factors_user
  ON user_mfa_factors(user_id);

CREATE TABLE IF NOT EXISTS user_mfa_backup_codes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- Keyed HMAC of the plaintext code — same pattern as refresh tokens
  -- (auth.ts hashToken / utils/token-hash.ts).
  code_hash CHAR(64) NOT NULL,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_mfa_backup_codes_hash
  ON user_mfa_backup_codes(code_hash);

CREATE INDEX IF NOT EXISTS idx_user_mfa_backup_codes_user_unused
  ON user_mfa_backup_codes(user_id)
  WHERE used_at IS NULL;

DO $$
BEGIN
  RAISE NOTICE 'Migration 084 complete: user_mfa_factors + user_mfa_backup_codes created';
END $$;
