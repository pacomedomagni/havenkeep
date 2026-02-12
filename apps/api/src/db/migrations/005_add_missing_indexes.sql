-- ============================================
-- Add Missing Database Indexes
-- Performance improvements for common queries
-- ============================================

-- Composite index for items filtered by user + archived status (dashboard queries)
CREATE INDEX IF NOT EXISTS idx_items_user_archived
  ON items(user_id, is_archived);

-- Composite index for items filtered by user + home (common filter)
CREATE INDEX IF NOT EXISTS idx_items_user_home
  ON items(user_id, home_id);

-- Index for warranty expiration lookups (items needing attention)
CREATE INDEX IF NOT EXISTS idx_items_warranty_end_user
  ON items(user_id, warranty_end_date)
  WHERE is_archived = FALSE;

-- Composite index for documents by user+item (fetched together)
CREATE INDEX IF NOT EXISTS idx_documents_user_item
  ON documents(user_id, item_id);

-- Index for refresh token expiry cleanup
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_expires
  ON refresh_tokens(expires_at);

-- Index for password reset token lookup (token + not used + not expired)
CREATE INDEX IF NOT EXISTS idx_password_reset_lookup
  ON password_reset_tokens(token, used, expires_at);

-- Push tokens table index (if table exists)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'user_push_tokens') THEN
    CREATE INDEX IF NOT EXISTS idx_push_tokens_user
      ON user_push_tokens(user_id);
  END IF;
END $$;

-- Audit logs index (if table exists) for user-based queries
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'audit_logs') THEN
    CREATE INDEX IF NOT EXISTS idx_audit_logs_user_created
      ON audit_logs(user_id, created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_audit_logs_action
      ON audit_logs(action);
  END IF;
END $$;
