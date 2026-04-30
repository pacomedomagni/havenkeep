-- Migration 082: re-apply enum/UUID text casts to audit-chain trigger.
--
-- Migration 080 added pg_advisory_xact_lock to audit_logs_assign_hash() to
-- serialize concurrent chain extensions, but copied the pre-075 trigger
-- body, undoing the cast fix that 075 shipped. Empty string can't coerce
-- to enum audit_severity or UUID, so every audit_logs INSERT raises
-- 22P02 (invalid_text_representation) on a deployment that has run mig 080.
--
-- This migration combines both fixes: the advisory lock from 080 AND the
-- typed-column casts from 075. Also aligns the writer's created_at
-- COALESCE fallback with the verifier in mig 075:81 — both now use ''
-- instead of the writer using NOW()::text and the verifier using ''.
-- That divergence was a latent false-positive (Pass 1 M12).

CREATE OR REPLACE FUNCTION audit_logs_assign_hash()
RETURNS TRIGGER AS $$
DECLARE
  v_prev CHAR(64);
  v_payload TEXT;
BEGIN
  -- S-ME-08 (mig 080): serialize chain extension via a transaction-scoped
  -- advisory lock so two concurrent BEFORE-INSERTs can't see the same
  -- predecessor and produce a forked chain.
  PERFORM pg_advisory_xact_lock(687638440097);

  SELECT this_hash INTO v_prev
    FROM audit_logs
    ORDER BY created_at DESC, id DESC
    LIMIT 1;

  -- Cast every typed column (enum, uuid, jsonb, inet, bool, timestamptz)
  -- to text so COALESCE with '' is type-safe. Without these casts the
  -- COALESCE call tries to coerce '' into the enum / UUID type and fails
  -- with 22P02, breaking every login + every other audit-logged action.
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
               COALESCE(NEW.created_at::text, '');

  NEW.prev_hash := v_prev;
  NEW.this_hash := encode(digest(v_payload, 'sha256'), 'hex');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
