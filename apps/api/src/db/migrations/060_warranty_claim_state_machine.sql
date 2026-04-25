-- ============================================
-- Migration 060: warranty_claims state machine + transition history
--   (Ch04-F001, F010)
-- Date: 2026-04-25
-- Description:
--   Status was free-form VARCHAR; the audit caught Mobile/server enums
--   diverging and arbitrary strings landing in the column. Lock down to a
--   canonical set + record an immutable transition history for every status
--   change so we can audit who moved a claim from `filed` to `denied`.
-- ============================================

-- ── 1. Canonicalize existing rows ──────────────────────────────────────
-- Map legacy values to the canonical state set:
--   'pending' / 'submitted' → 'filed'
--   'completed' / 'approved' → 'approved'
--   'cancelled' → 'closed'
UPDATE warranty_claims SET status = 'filed'
 WHERE status IN ('pending', 'submitted');
UPDATE warranty_claims SET status = 'approved'
 WHERE status IN ('completed');
UPDATE warranty_claims SET status = 'closed'
 WHERE status IN ('cancelled');
UPDATE warranty_claims SET status = 'filed'
 WHERE status IS NULL OR status NOT IN ('filed','in_review','approved','denied','settled','closed');

ALTER TABLE warranty_claims
  ALTER COLUMN status SET NOT NULL,
  ALTER COLUMN status SET DEFAULT 'filed';

ALTER TABLE warranty_claims
  DROP CONSTRAINT IF EXISTS chk_warranty_claims_status;
ALTER TABLE warranty_claims
  ADD CONSTRAINT chk_warranty_claims_status
  CHECK (status IN ('filed','in_review','approved','denied','settled','closed'));

-- ── 2. Transition history table ────────────────────────────────────────
-- One row per status change; immutable (no UPDATE) so we have a real audit
-- trail of who moved the claim and when.
CREATE TABLE IF NOT EXISTS warranty_claim_state_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  claim_id UUID NOT NULL REFERENCES warranty_claims(id) ON DELETE CASCADE,
  from_status VARCHAR(32),
  to_status VARCHAR(32) NOT NULL,
  -- actor is the user_id of the caller; NULL only for system transitions.
  actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_state_history_to
    CHECK (to_status IN ('filed','in_review','approved','denied','settled','closed'))
);

CREATE INDEX IF NOT EXISTS idx_claim_state_history_claim
  ON warranty_claim_state_history (claim_id, created_at);

-- Block UPDATE/DELETE outright so a DBA can't silently rewrite history.
CREATE OR REPLACE FUNCTION warranty_claim_state_history_immutable()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION 'warranty_claim_state_history is append-only';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_warranty_claim_state_history_no_update ON warranty_claim_state_history;
CREATE TRIGGER trg_warranty_claim_state_history_no_update
  BEFORE UPDATE OR DELETE ON warranty_claim_state_history
  FOR EACH ROW EXECUTE FUNCTION warranty_claim_state_history_immutable();

DO $$
BEGIN
  RAISE NOTICE 'Migration 060 complete: warranty_claims state machine + transition history';
END $$;
