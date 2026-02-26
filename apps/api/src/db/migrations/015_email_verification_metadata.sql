-- Migration 015: Add metadata JSONB column to email_verification_tokens
-- Required by the email change flow (POST /users/me/change-email) which stores
-- { type: 'change_email', new_email: '...' } to distinguish from registration tokens.

ALTER TABLE email_verification_tokens
  ADD COLUMN IF NOT EXISTS metadata JSONB;

-- Index for filtering by token type (e.g., WHERE metadata->>'type' = 'change_email')
CREATE INDEX IF NOT EXISTS idx_email_verification_metadata_type
  ON email_verification_tokens ((metadata->>'type'))
  WHERE metadata IS NOT NULL;

DO $$
BEGIN
  RAISE NOTICE 'Migration 015: Added metadata JSONB column to email_verification_tokens';
END $$;
