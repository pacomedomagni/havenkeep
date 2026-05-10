-- Migration 109: H23 — key_version on encrypted-token tables.
--
-- The encrypt/decrypt helper currently walks the primary key first
-- then the legacy keys until one validates. Without a stored
-- key_version, we can never know "all rows have been re-encrypted to
-- the new key" — which means the legacy list grows monotonically and
-- a key rotation can never be cleanly finalized. Adding a column
-- bounded to the actual key used at encrypt time turns rotation into:
--
--   1. Add new secret as primary; old as legacy.
--   2. Background sweep: SELECT rows WHERE key_version = N, decrypt with
--      legacy, re-encrypt with primary, UPDATE key_version = N+1.
--   3. When `MIN(key_version) = N+1` everywhere, drop the legacy
--      secret from config.
--
-- Default 1 because no users / no encrypted rows exist yet, so the
-- column has no meaningful semantics to preserve.

ALTER TABLE user_oauth_integrations
  ADD COLUMN IF NOT EXISTS key_version SMALLINT NOT NULL DEFAULT 1;

ALTER TABLE user_mfa_factors
  ADD COLUMN IF NOT EXISTS key_version SMALLINT NOT NULL DEFAULT 1;
