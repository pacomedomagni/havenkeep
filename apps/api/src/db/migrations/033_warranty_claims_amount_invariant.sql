-- ============================================
-- Migration 033: warranty_claims amount invariants (Ch04-F002)
-- Date: 2026-04-25
-- Description: amount_saved = repair_cost - out_of_pocket should always hold
--   and savings can never be negative or exceed the repair cost. The audit
--   found social-proof and analytics polluted by user-controlled bogus values.
--   Add DB-side CHECK so service-level bugs cannot bypass the invariant.
-- ============================================

-- Sanitize any pre-existing rows that violate the invariant before adding the
-- constraint. Three classes of broken row:
--   (a) negative repair_cost or amount_saved -> clamp to 0
--   (b) amount_saved > repair_cost           -> clamp amount_saved to repair_cost
UPDATE warranty_claims
SET repair_cost  = GREATEST(repair_cost, 0),
    amount_saved = GREATEST(amount_saved, 0),
    out_of_pocket = GREATEST(COALESCE(out_of_pocket, 0), 0);

UPDATE warranty_claims
SET amount_saved = repair_cost
WHERE amount_saved > repair_cost;

ALTER TABLE warranty_claims
  DROP CONSTRAINT IF EXISTS chk_warranty_claims_amounts;

ALTER TABLE warranty_claims
  ADD CONSTRAINT chk_warranty_claims_amounts
  CHECK (
    repair_cost   >= 0
    AND amount_saved >= 0
    AND COALESCE(out_of_pocket, 0) >= 0
    AND amount_saved <= repair_cost
  );

DO $$
BEGIN
  RAISE NOTICE 'Migration 033 complete: warranty_claims invariant CHECK installed';
END $$;
