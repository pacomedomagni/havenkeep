-- Add missing indexes for performance
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_expires_at ON refresh_tokens(expires_at);
CREATE INDEX IF NOT EXISTS idx_items_is_archived ON items(is_archived);
CREATE INDEX IF NOT EXISTS idx_items_warranty_status ON items(warranty_end_date) WHERE is_archived = FALSE;

-- Composite indexes for common queries
CREATE INDEX IF NOT EXISTS idx_items_user_home ON items(user_id, home_id);
CREATE INDEX IF NOT EXISTS idx_items_user_archived ON items(user_id, is_archived);
