-- Migration 099: fix cleanup_old_audit_logs() for newer PostgreSQL.
--
-- Mig 031 made audit_logs append-only via a BEFORE UPDATE/DELETE trigger
-- that allows DELETE only when current_user = 'audit_cleaner'. The
-- retention helper switched to that role with `SET LOCAL ROLE` inside
-- a SECURITY DEFINER body. Newer Postgres versions reject that combo
-- ("cannot set parameter \"role\" within security-definer function"),
-- so every call to /api/v1/audit/cleanup returned 500 from prod.
--
-- Fix: the function is owned by the api user (havenkeep) by default,
-- which doesn't pass the immutable-trigger check. Reassign ownership
-- to `audit_cleaner` and drop the SET LOCAL ROLE statement. With
-- SECURITY DEFINER + owner=audit_cleaner, the function body runs as
-- audit_cleaner, the trigger sees current_user='audit_cleaner', and
-- the DELETE proceeds. No security regression: only callers granted
-- EXECUTE on the function can trigger cleanup.

CREATE OR REPLACE FUNCTION cleanup_old_audit_logs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  DELETE FROM audit_logs
  WHERE created_at < NOW() - INTERVAL '1 year'
    AND severity = 'info';

  DELETE FROM audit_logs
  WHERE created_at < NOW() - INTERVAL '3 years'
    AND severity IN ('warning', 'error', 'critical');
END;
$$;

ALTER FUNCTION cleanup_old_audit_logs() OWNER TO audit_cleaner;

-- audit_cleaner needs SELECT (for the WHERE filter) + DELETE on audit_logs.
-- Without SELECT, the DELETE …  WHERE … evaluation raises 42501.
GRANT SELECT, DELETE ON audit_logs TO audit_cleaner;

DO $$
BEGIN
  RAISE NOTICE 'Migration 099 complete: cleanup_old_audit_logs runs as audit_cleaner via SECURITY DEFINER (no SET LOCAL ROLE)';
END $$;
