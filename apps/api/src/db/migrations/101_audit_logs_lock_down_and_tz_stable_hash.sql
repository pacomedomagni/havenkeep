-- Migration 101: lock audit_logs down + make hash payload TZ-stable.
--
-- Two related audit findings collapsed into one migration because they
-- both touch the same trigger/function:
--
-- C0-2: audit_logs was owned by the API role (`havenkeep`). An attacker
--   with API-level DB access could `DROP TRIGGER trg_audit_logs_immutable`,
--   silently UPDATE/DELETE rows to erase forensic evidence, then
--   re-create the trigger. The "append-only" property was theater.
--   Fix: re-own audit_logs (and its trigger/verifier functions) to
--   `audit_cleaner`, then REVOKE ALL from `havenkeep` and re-GRANT
--   only SELECT + INSERT — the exact privileges the API code uses
--   (see audit.service.ts: INSERT for logs, SELECT for queries,
--   EXECUTE on cleanup_old_audit_logs which is already SECURITY
--   DEFINER + owned by audit_cleaner).
--
-- C0-4: the hash payload formatted NEW.created_at with `::text`, which
--   uses the session's TimeZone GUC. A writer in `UTC` and a verifier
--   in `America/Los_Angeles` produced different strings for the same
--   row → false-positive chain break flagged on every row. Fix: use
--   `to_char(NEW.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US')`
--   so both writer and verifier emit the same canonical UTC text
--   regardless of session TZ. Both the trigger AND the verifier need
--   to change in lockstep — drift between them re-introduces the same
--   bug.
--
-- C0-3 (NOT applied, deliberately): the audit recommended swapping
--   `current_user` for `session_user` in audit_logs_immutable(). After
--   C0-2 the API role is no longer a member of audit_cleaner and can't
--   `SET ROLE audit_cleaner` anyway — Postgres rejects the SET with
--   42501 before the trigger ever sees a forged current_user. Meanwhile
--   the cleanup helper runs SECURITY DEFINER with owner=audit_cleaner,
--   so its `current_user` IS legitimately `audit_cleaner` mid-DELETE.
--   Switching to `session_user` there would return the original login
--   (`havenkeep`), the trigger would refuse, and retention cleanup
--   would 42501 on every invocation. C0-2 alone closes the threat
--   model; C0-3 as written would only break a working code path.

-- ── C0-2: re-own table + functions; relock GRANTs ─────────────────

ALTER TABLE audit_logs OWNER TO audit_cleaner;
ALTER FUNCTION audit_logs_immutable() OWNER TO audit_cleaner;
ALTER FUNCTION audit_logs_assign_hash() OWNER TO audit_cleaner;
ALTER FUNCTION verify_audit_chain() OWNER TO audit_cleaner;

REVOKE ALL ON TABLE audit_logs FROM havenkeep;
GRANT SELECT, INSERT ON audit_logs TO havenkeep;

-- The chain trigger fires BEFORE INSERT as SECURITY INVOKER (the
-- caller's role). The API role (havenkeep) has INSERT, which is all
-- the trigger body needs — it only reads (SELECT) the latest row to
-- compute prev_hash. Grant EXECUTE on the trigger functions explicitly
-- so any future search-path quirk doesn't silently break inserts.
GRANT EXECUTE ON FUNCTION audit_logs_assign_hash() TO havenkeep;
GRANT EXECUTE ON FUNCTION verify_audit_chain() TO havenkeep;

-- audit_cleaner already had SELECT + DELETE from mig 099/100; keep
-- those (re-owning the table preserves table-level privileges granted
-- to other roles).

-- ── C0-4: TZ-stable hash payload ──────────────────────────────────
--
-- Re-create both functions with `to_char(... AT TIME ZONE 'UTC', ...)`
-- replacing the prior `::text` cast on NEW.created_at / r.created_at.
-- Every other column-to-text formatting stays the same as mig 082 / 075
-- so the rest of the chain isn't disrupted.

CREATE OR REPLACE FUNCTION audit_logs_assign_hash()
RETURNS TRIGGER AS $$
DECLARE
  v_prev CHAR(64);
  v_payload TEXT;
BEGIN
  PERFORM pg_advisory_xact_lock(687638440097);

  SELECT this_hash INTO v_prev
    FROM audit_logs
    ORDER BY created_at DESC, id DESC
    LIMIT 1;

  v_payload := COALESCE(v_prev, '') || '|' ||
               COALESCE(NEW.user_id::text, '') || '|' ||
               COALESCE(NEW.user_email, '') || '|' ||
               NEW.action::text || '|' ||
               COALESCE(NEW.severity::text, '') || '|' ||
               COALESCE(NEW.resource_type, '') || '|' ||
               COALESCE(NEW.resource_id::text, '') || '|' ||
               COALESCE(NEW.description, '') || '|' ||
               COALESCE(NEW.metadata::text, '') || '|' ||
               COALESCE(NEW.ip_address::text, '') || '|' ||
               COALESCE(NEW.user_agent, '') || '|' ||
               COALESCE(NEW.endpoint, '') || '|' ||
               COALESCE(NEW.http_method, '') || '|' ||
               COALESCE(NEW.success::text, '') || '|' ||
               COALESCE(NEW.error_message, '') || '|' ||
               COALESCE(to_char(NEW.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US'), '');

  NEW.prev_hash := v_prev;
  NEW.this_hash := encode(digest(v_payload, 'sha256'), 'hex');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION verify_audit_chain()
RETURNS TABLE(broken_at TIMESTAMPTZ, broken_id UUID) AS $$
DECLARE
  v_prev CHAR(64) := NULL;
  r RECORD;
  v_payload TEXT;
  v_expected CHAR(64);
BEGIN
  FOR r IN
    SELECT * FROM audit_logs ORDER BY created_at, id
  LOOP
    v_payload := COALESCE(v_prev, '') || '|' ||
                 COALESCE(r.user_id::text, '') || '|' ||
                 COALESCE(r.user_email, '') || '|' ||
                 r.action::text || '|' ||
                 COALESCE(r.severity::text, '') || '|' ||
                 COALESCE(r.resource_type, '') || '|' ||
                 COALESCE(r.resource_id::text, '') || '|' ||
                 COALESCE(r.description, '') || '|' ||
                 COALESCE(r.metadata::text, '') || '|' ||
                 COALESCE(r.ip_address::text, '') || '|' ||
                 COALESCE(r.user_agent, '') || '|' ||
                 COALESCE(r.endpoint, '') || '|' ||
                 COALESCE(r.http_method, '') || '|' ||
                 COALESCE(r.success::text, '') || '|' ||
                 COALESCE(r.error_message, '') || '|' ||
                 COALESCE(to_char(r.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US'), '');
    v_expected := encode(digest(v_payload, 'sha256'), 'hex');
    IF r.this_hash IS DISTINCT FROM v_expected THEN
      broken_at := r.created_at;
      broken_id := r.id;
      RETURN NEXT;
    END IF;
    v_prev := r.this_hash;
  END LOOP;
  RETURN;
END;
$$ LANGUAGE plpgsql;

-- Re-grant after CREATE OR REPLACE — REPLACE preserves owner but the
-- new function objects need EXECUTE re-grants if the surrounding
-- GRANT block is re-run via a fresh role.
ALTER FUNCTION audit_logs_assign_hash() OWNER TO audit_cleaner;
ALTER FUNCTION verify_audit_chain() OWNER TO audit_cleaner;
GRANT EXECUTE ON FUNCTION audit_logs_assign_hash() TO havenkeep;
GRANT EXECUTE ON FUNCTION verify_audit_chain() TO havenkeep;

DO $$
BEGIN
  RAISE NOTICE 'Migration 101 complete: audit_logs locked to audit_cleaner; hash payload is TZ-stable (UTC microsecond format)';
END $$;
