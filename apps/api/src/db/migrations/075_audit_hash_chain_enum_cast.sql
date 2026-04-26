-- ============================================
-- Migration 075: fix audit hash chain trigger to cast enum + UUID to text
-- before COALESCE'ing with the empty string. Without these casts the
-- COALESCE call tries to coerce '' into the enum / UUID type and fails
-- with 22P02 (invalid_text_representation), breaking every login + every
-- other audit-logged action.
-- Date: 2026-04-26
-- ============================================

CREATE OR REPLACE FUNCTION audit_logs_assign_hash()
RETURNS TRIGGER AS $$
DECLARE
  v_prev CHAR(64);
  v_payload TEXT;
BEGIN
  -- Look up the most recently inserted row's hash, serializing the chain
  -- head with FOR SHARE so concurrent inserts can't both read NULL and
  -- both think they are the first row.
  SELECT this_hash INTO v_prev
    FROM audit_logs
   ORDER BY created_at DESC, id DESC
   LIMIT 1
   FOR SHARE;

  -- Concatenate the row's stable fields into a payload. Every typed
  -- column (enum, uuid, jsonb, inet, bool, timestamptz) is cast to
  -- text so the COALESCE branch can safely substitute the empty
  -- string when the column is NULL.
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
               COALESCE(NEW.created_at::text, NOW()::text);

  NEW.prev_hash := v_prev;
  NEW.this_hash := encode(digest(v_payload, 'sha256'), 'hex');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Same fix for the verifier — it recomputes the chain so it must use
-- the same payload format as the trigger above. Drift between the two
-- would falsely flag the chain as broken.
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
                 COALESCE(r.created_at::text, '');
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
