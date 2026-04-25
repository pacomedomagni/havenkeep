-- ============================================
-- Migration 038: Server-side OAuth refresh tokens (Ch04-F059)
-- Date: 2026-04-25
-- Description: The Gmail/Outlook scanner currently accepts a raw access token
--   from the mobile client and uses it directly. That means:
--     - Compromised mobile = direct API access to Google/MS for as long as
--       the access token lasts.
--     - The server has no way to refresh because no refresh token is stored.
--     - The server cannot revoke without the user re-doing OAuth.
--
--   New flow: client sends OAuth `code`, server exchanges for refresh+access,
--   stores the refresh token AES-encrypted, derives access tokens server-side
--   for each scan. This table holds the encrypted refresh tokens.
-- ============================================

CREATE TYPE oauth_provider AS ENUM ('gmail', 'outlook');

CREATE TABLE IF NOT EXISTS user_oauth_integrations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider oauth_provider NOT NULL,
  provider_email VARCHAR(320) NOT NULL,

  -- Encrypted blob (AES-256-GCM, key from env). Stored base64.
  refresh_token_ciphertext TEXT NOT NULL,
  refresh_token_iv         CHAR(24) NOT NULL,   -- 12 bytes -> base64
  refresh_token_tag        CHAR(24) NOT NULL,   -- 16 bytes -> base64

  -- Access token cache (lasts ~1 hour). Re-fetched when expiring.
  access_token_ciphertext TEXT,
  access_token_iv         CHAR(24),
  access_token_tag        CHAR(24),
  access_token_expires_at TIMESTAMPTZ,

  granted_scope TEXT NOT NULL,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at TIMESTAMPTZ,

  CONSTRAINT uq_user_oauth_provider UNIQUE (user_id, provider, provider_email)
);

CREATE INDEX IF NOT EXISTS idx_user_oauth_integrations_user
  ON user_oauth_integrations(user_id)
  WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_user_oauth_integrations_provider
  ON user_oauth_integrations(provider, user_id)
  WHERE revoked_at IS NULL;

CREATE TRIGGER trg_user_oauth_integrations_updated_at
  BEFORE UPDATE ON user_oauth_integrations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE user_oauth_integrations IS
  'Encrypted OAuth refresh tokens per user/provider. Access tokens are cached briefly here.';

DO $$
BEGIN
  RAISE NOTICE 'Migration 038 complete: user_oauth_integrations table created';
END $$;
