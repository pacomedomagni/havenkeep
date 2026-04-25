-- ============================================
-- Migration 031: audit_logs append-only enforcement (Ch04-F088)
-- Date: 2026-04-25
-- Description: audit_logs is supposed to be the immutable trail of every
--   sensitive action. With no DB-side guard, an attacker with write access to
--   the API DB user can rewrite or delete history. Add a BEFORE UPDATE OR
--   DELETE trigger that raises unless the calling role is `audit_cleaner`.
--   Retention cleanup is the only legitimate DELETE path; it runs as that role.
-- ============================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'audit_cleaner') THEN
    CREATE ROLE audit_cleaner NOLOGIN;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION audit_logs_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF current_user = 'audit_cleaner' OR pg_has_role(current_user, 'audit_cleaner', 'MEMBER') THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'audit_logs is append-only (op=%, role=%)', TG_OP, current_user
    USING ERRCODE = 'insufficient_privilege';
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_logs_immutable ON audit_logs;
CREATE TRIGGER trg_audit_logs_immutable
  BEFORE UPDATE OR DELETE ON audit_logs
  FOR EACH ROW EXECUTE FUNCTION audit_logs_immutable();

-- Retention helper now runs SECURITY DEFINER so it can DELETE while the
-- regular API user cannot. Re-create with explicit search_path.
CREATE OR REPLACE FUNCTION cleanup_old_audit_logs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  SET LOCAL ROLE audit_cleaner;

  DELETE FROM audit_logs
  WHERE created_at < NOW() - INTERVAL '1 year'
    AND severity = 'info';

  DELETE FROM audit_logs
  WHERE created_at < NOW() - INTERVAL '3 years'
    AND severity IN ('warning', 'error', 'critical');

  RESET ROLE;
END;
$$;

REVOKE ALL ON FUNCTION cleanup_old_audit_logs() FROM PUBLIC;

DO $$
BEGIN
  RAISE NOTICE 'Migration 031 complete: audit_logs immutable trigger installed';
END $$;
