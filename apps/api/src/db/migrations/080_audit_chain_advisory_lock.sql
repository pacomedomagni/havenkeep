-- Migration 080: serialize audit-log hash-chain inserts via advisory lock
--   (S-ME-08 / Ch04-F095 follow-up).
--
-- Pre-S-ME-08, the audit-chain trigger read the latest `this_hash` with
-- FOR SHARE but two concurrent BEFORE-INSERTs could each see the same
-- `v_prev` snapshot and chain off the same predecessor. The chain forks;
-- `verify_audit_chain()` then surfaces one of the children as "broken"
-- on the next run. Not a tampering bypass — but a denial-of-confidence
-- attack: any high-throughput route that fans out concurrent audit
-- writes produces false integrity alerts.
--
-- Fix: take a transaction-scoped advisory lock at the start of the
-- trigger so all concurrent inserts serialize through the chain.
-- `pg_advisory_xact_lock` releases automatically at commit/rollback.
-- The lock key is a fixed integer (`audit_logs_hash_chain` is the
-- semantic name); 0xA00D17_C8A1 = 0xA00D17C8A1 collides only with
-- callers using the same constant — none today.

CREATE OR REPLACE FUNCTION audit_logs_assign_hash()
RETURNS TRIGGER AS $$
DECLARE
  v_prev CHAR(64);
  v_payload TEXT;
BEGIN
  -- S-ME-08: serialize chain extension. Without this two concurrent
  -- inserts can see the same v_prev and produce a fork.
  PERFORM pg_advisory_xact_lock(687638440097);  -- 0xA00D17C8A1

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
