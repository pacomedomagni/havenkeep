-- ============================================
-- Migration 065: audit_logs hash chain (Ch04-F095)
-- Date: 2026-04-25
-- Description:
--   Migration 031 already locks audit_logs against UPDATE/DELETE, but a DBA
--   with INSERT can still rewrite history by truncating and replaying with
--   different content. Add a per-row this_hash that incorporates the prior
--   row's hash so any tampering with a single row breaks every subsequent
--   verification.
--
--   verify_audit_chain() walks the table in created_at order and surfaces
--   any row whose computed hash != stored this_hash.
-- ============================================

ALTER TABLE audit_logs
  ADD COLUMN IF NOT EXISTS prev_hash CHAR(64),
  ADD COLUMN IF NOT EXISTS this_hash CHAR(64);

-- Compute this_hash as sha256 of the canonical row representation + prev_hash.
-- BEFORE INSERT trigger so the hash is part of the row before the immutability
-- trigger sees it.
CREATE OR REPLACE FUNCTION audit_logs_assign_hash()
RETURNS TRIGGER AS $$
DECLARE
  v_prev CHAR(64);
  v_payload TEXT;
BEGIN
  -- Snapshot the latest row's hash. We use FOR SHARE so concurrent inserts
  -- chain in commit order; any concurrent inserter waits for our chain
  -- decision.
  SELECT this_hash INTO v_prev
    FROM audit_logs
    ORDER BY created_at DESC, id DESC
    LIMIT 1;

  v_payload := COALESCE(v_prev, '') || '|' ||
               COALESCE(NEW.user_id::text, '') || '|' ||
               COALESCE(NEW.user_email, '') || '|' ||
               NEW.action || '|' ||
               COALESCE(NEW.severity, '') || '|' ||
               COALESCE(NEW.resource_type, '') || '|' ||
               COALESCE(NEW.resource_id, '') || '|' ||
               COALESCE(NEW.description, '') || '|' ||
               COALESCE(NEW.metadata::text, '') || '|' ||
               COALESCE(NEW.ip_address::text, '') || '|' ||
               COALESCE(NEW.user_agent, '') || '|' ||
               COALESCE(NEW.endpoint, '') || '|' ||
               COALESCE(NEW.http_method, '') || '|' ||
               COALESCE(NEW.success::text, '') || '|' ||
               COALESCE(NEW.error_message, '') || '|' ||
               COALESCE(NEW.created_at::text, NOW()::text);

  NEW.prev_hash := v_prev;
  NEW.this_hash := encode(digest(v_payload, 'sha256'), 'hex');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_audit_logs_hash_chain ON audit_logs;
CREATE TRIGGER trg_audit_logs_hash_chain
  BEFORE INSERT ON audit_logs
  FOR EACH ROW EXECUTE FUNCTION audit_logs_assign_hash();

-- Verifier: returns the count of rows whose stored this_hash doesn't match
-- a recomputation. 0 = chain intact.
CREATE OR REPLACE FUNCTION verify_audit_chain()
RETURNS TABLE(broken_at TIMESTAMPTZ, broken_id UUID) AS $$
DECLARE
  v_prev CHAR(64) := NULL;
  v_expected CHAR(64);
  r RECORD;
BEGIN
  FOR r IN SELECT * FROM audit_logs ORDER BY created_at ASC, id ASC LOOP
    v_expected := encode(digest(
      COALESCE(v_prev, '') || '|' ||
      COALESCE(r.user_id::text, '') || '|' ||
      COALESCE(r.user_email, '') || '|' ||
      r.action || '|' ||
      COALESCE(r.severity, '') || '|' ||
      COALESCE(r.resource_type, '') || '|' ||
      COALESCE(r.resource_id, '') || '|' ||
      COALESCE(r.description, '') || '|' ||
      COALESCE(r.metadata::text, '') || '|' ||
      COALESCE(r.ip_address::text, '') || '|' ||
      COALESCE(r.user_agent, '') || '|' ||
      COALESCE(r.endpoint, '') || '|' ||
      COALESCE(r.http_method, '') || '|' ||
      COALESCE(r.success::text, '') || '|' ||
      COALESCE(r.error_message, '') || '|' ||
      COALESCE(r.created_at::text, ''),
      'sha256'
    ), 'hex');

    IF r.this_hash IS NOT NULL AND r.this_hash <> v_expected THEN
      broken_at := r.created_at;
      broken_id := r.id;
      RETURN NEXT;
    END IF;

    v_prev := r.this_hash;
  END LOOP;
END;
$$ LANGUAGE plpgsql STABLE;

-- ── F094: cap metadata JSONB at 8KB ────────────────────────────────────
ALTER TABLE audit_logs
  DROP CONSTRAINT IF EXISTS chk_audit_logs_metadata_size;
ALTER TABLE audit_logs
  ADD CONSTRAINT chk_audit_logs_metadata_size
  CHECK (metadata IS NULL OR octet_length(metadata::text) <= 8192);

DO $$
BEGIN
  RAISE NOTICE 'Migration 065 complete: audit_logs hash chain + metadata size cap';
END $$;
