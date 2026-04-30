-- Migration 100: grant SELECT on audit_logs to audit_cleaner.
--
-- Mig 099 reset cleanup_old_audit_logs() to run as audit_cleaner via
-- SECURITY DEFINER, but only granted DELETE. Postgres requires SELECT
-- privilege on the rows being inspected by the DELETE's WHERE clause —
-- without it, the cleanup function raises 42501 (insufficient_privilege)
-- on the first DELETE statement.
--
-- Granting SELECT here completes the privilege model: audit_cleaner can
-- read audit_logs (only inside this function via SECURITY DEFINER) and
-- delete the matched rows. The immutable trigger from mig 031 still
-- enforces tamper-evidence — non-cleaner roles can neither UPDATE nor
-- DELETE.

GRANT SELECT ON audit_logs TO audit_cleaner;

DO $$
BEGIN
  RAISE NOTICE 'Migration 100 complete: audit_cleaner now has SELECT on audit_logs (cleanup function works again)';
END $$;
