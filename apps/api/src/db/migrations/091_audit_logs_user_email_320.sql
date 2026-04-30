-- Migration 091: widen audit_logs.user_email from VARCHAR(255) to VARCHAR(320).
--
-- Audit M-D2: RFC 5321 caps email at 64 (local) + @ + 255 (domain) = 320.
-- audit_logs.user_email was VARCHAR(255) which truncates valid long
-- emails. Other denormalized email columns in this codebase
-- (notification_history.user_email_at_send, etc.) are already 320; the
-- audit table's lag was an inconsistency.
--
-- Truncation in audit_logs is particularly bad: when the user's row
-- is later deleted (FK SET NULL drops user_id), the user_email
-- snapshot is the ONLY forensic record of who the row referred to.
-- A truncated email there means the audit chain still verifies (the
-- row is self-consistent under verify_audit_chain) but the recorded
-- identifier is wrong.
--
-- The recent_security_events view (mig 004) projects user_email and
-- pins PG's column-type alter check; we drop and recreate the view
-- around the ALTER. The view is a pure SELECT — no users, grants,
-- materialized data — so the drop is safe. CREATE OR REPLACE is not
-- usable because the column type changes.
--
-- ALTER COLUMN ... TYPE on a column with no rewrite is metadata-only;
-- VARCHAR(320) ⊇ VARCHAR(255), so no table rewrite even with data.

DROP VIEW IF EXISTS recent_security_events;

ALTER TABLE audit_logs
  ALTER COLUMN user_email TYPE VARCHAR(320);

CREATE VIEW recent_security_events AS
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

DO $$
BEGIN
  RAISE NOTICE 'Migration 091 complete: audit_logs.user_email widened to VARCHAR(320) (M-D2)';
END $$;
