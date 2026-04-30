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
-- ALTER COLUMN ... TYPE on a column under a CHECK constraint can be
-- expensive on a large table; PG can avoid the rewrite when the new
-- type is strictly larger. VARCHAR(320) ⊇ VARCHAR(255), so no rewrite
-- on a populated table.

ALTER TABLE audit_logs
  ALTER COLUMN user_email TYPE VARCHAR(320);

DO $$
BEGIN
  RAISE NOTICE 'Migration 091 complete: audit_logs.user_email widened to VARCHAR(320) (M-D2)';
END $$;
