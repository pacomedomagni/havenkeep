-- Migration 097: let FK CASCADE delete prune warranty_claim_state_history
-- when the parent claim is deleted.
--
-- Original mig 060 added BEFORE UPDATE OR DELETE trigger
-- `warranty_claim_state_history_immutable` to make the audit trail
-- tamper-evident. The trigger blocked any DELETE, including the FK
-- CASCADE that fires when a user deletes their own warranty claim
-- (FK was declared `ON DELETE CASCADE`). Net effect: every
-- DELETE /warranty-claims/:id returned 500 from prod.
--
-- The intent is still "rows cannot be silently rewritten," not "rows
-- can never be removed even when the parent claim no longer exists."
-- Drop DELETE from the trigger; leave UPDATE blocked. CASCADE prunes
-- now work; tampering (UPDATE on an existing history row) still
-- raises an exception.

DROP TRIGGER IF EXISTS trg_warranty_claim_state_history_no_update ON warranty_claim_state_history;

CREATE TRIGGER trg_warranty_claim_state_history_no_update
  BEFORE UPDATE ON warranty_claim_state_history
  FOR EACH ROW EXECUTE FUNCTION warranty_claim_state_history_immutable();

DO $$
BEGIN
  RAISE NOTICE 'Migration 097 complete: warranty_claim_state_history allows FK CASCADE deletes (mig 060 over-blocked)';
END $$;
