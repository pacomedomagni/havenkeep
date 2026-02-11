-- ============================================
-- Audit System Migration
-- Comprehensive audit logging for HavenKeep
-- ============================================

-- Audit action types
CREATE TYPE audit_action AS ENUM (
  -- Authentication
  'auth.login',
  'auth.logout',
  'auth.register',
  'auth.password_reset_request',
  'auth.password_reset_complete',
  'auth.email_verify',
  'auth.token_refresh',
  'auth.oauth_login',

  -- User actions
  'user.create',
  'user.update',
  'user.delete',
  'user.plan_upgrade',
  'user.plan_downgrade',

  -- Item actions
  'item.create',
  'item.update',
  'item.delete',
  'item.archive',
  'item.unarchive',
  'item.transfer',

  -- Home actions
  'home.create',
  'home.update',
  'home.delete',

  -- Document actions
  'document.upload',
  'document.delete',
  'document.view',

  -- Admin actions
  'admin.user_impersonate',
  'admin.user_delete',
  'admin.partner_approve',
  'admin.partner_reject',
  'admin.settings_change',

  -- Partner actions
  'partner.gift_create',
  'partner.gift_update',
  'partner.gift_activate',
  'partner.warranty_create',
  'partner.warranty_update',

  -- Security events
  'security.unauthorized_access',
  'security.rate_limit_exceeded',
  'security.suspicious_activity',
  'security.api_key_used',

  -- System events
  'system.error',
  'system.maintenance_start',
  'system.maintenance_end'
);

-- Audit severity levels
CREATE TYPE audit_severity AS ENUM (
  'info',
  'warning',
  'error',
  'critical'
);

-- Audit logs table
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- Who performed the action
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  user_email VARCHAR(255), -- Denormalized for deleted users

  -- What action was performed
  action audit_action NOT NULL,
  severity audit_severity NOT NULL DEFAULT 'info',

  -- What resource was affected
  resource_type VARCHAR(50), -- e.g., 'item', 'home', 'user', 'document'
  resource_id UUID, -- ID of the affected resource

  -- Details about the action
  description TEXT,
  metadata JSONB, -- Additional structured data (old values, new values, etc.)

  -- Request context
  ip_address INET,
  user_agent TEXT,
  endpoint VARCHAR(255), -- API endpoint called
  http_method VARCHAR(10),

  -- Result
  success BOOLEAN NOT NULL DEFAULT TRUE,
  error_message TEXT,

  -- Timing
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for efficient querying
CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at DESC);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_audit_logs_severity ON audit_logs(severity);
CREATE INDEX idx_audit_logs_resource ON audit_logs(resource_type, resource_id);
CREATE INDEX idx_audit_logs_user_created ON audit_logs(user_id, created_at DESC);

-- Composite index for common admin queries
CREATE INDEX idx_audit_logs_admin_view ON audit_logs(severity, created_at DESC)
  WHERE severity IN ('warning', 'error', 'critical');

-- GIN index for metadata JSONB queries
CREATE INDEX idx_audit_logs_metadata ON audit_logs USING GIN (metadata);

-- Retention policy function (delete logs older than 1 year for non-critical events)
CREATE OR REPLACE FUNCTION cleanup_old_audit_logs()
RETURNS void AS $$
BEGIN
  DELETE FROM audit_logs
  WHERE created_at < NOW() - INTERVAL '1 year'
    AND severity = 'info';

  -- Keep critical logs for 3 years
  DELETE FROM audit_logs
  WHERE created_at < NOW() - INTERVAL '3 years'
    AND severity IN ('warning', 'error', 'critical');
END;
$$ LANGUAGE plpgsql;

-- View for recent security events
CREATE OR REPLACE VIEW recent_security_events AS
SELECT
  al.id,
  al.user_id,
  al.user_email,
  al.action,
  al.severity,
  al.description,
  al.ip_address,
  al.created_at
FROM audit_logs al
WHERE al.action::text LIKE 'security.%'
  AND al.created_at > NOW() - INTERVAL '30 days'
ORDER BY al.created_at DESC;

-- View for user activity summary
CREATE OR REPLACE VIEW user_activity_summary AS
SELECT
  u.id AS user_id,
  u.email,
  u.full_name,
  COUNT(*) AS total_actions,
  COUNT(*) FILTER (WHERE al.created_at > NOW() - INTERVAL '7 days') AS actions_last_7_days,
  COUNT(*) FILTER (WHERE al.created_at > NOW() - INTERVAL '30 days') AS actions_last_30_days,
  MAX(al.created_at) AS last_activity,
  COUNT(*) FILTER (WHERE al.success = FALSE) AS failed_actions
FROM users u
LEFT JOIN audit_logs al ON al.user_id = u.id
GROUP BY u.id, u.email, u.full_name;

-- Comment
COMMENT ON TABLE audit_logs IS 'Comprehensive audit log for all user and system actions';
COMMENT ON COLUMN audit_logs.metadata IS 'JSONB field for storing structured data like old/new values, additional context';
COMMENT ON FUNCTION cleanup_old_audit_logs IS 'Cleanup function to maintain audit log retention policy - run via cron job';
