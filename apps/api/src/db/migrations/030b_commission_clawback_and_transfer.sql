-- ============================================
-- Migration 030b: Commission clawback ledger + Stripe transfer wiring
--   (Ch03-F011, Ch03-F012, Ch03-F054, Ch12-T004, Ch09-FlowC-T-C10, Ch12-R015)
-- Date: 2026-04-25
-- Description: Companion to 030a. Adds the columns, indexes, and CHECK
--   constraints that depend on the 'reversed' enum value being live (which
--   it is, because 030a committed first).
--
--   * Adds reversal_of_commission_id so a clawback row points back at the
--     original paid commission. amount on a reversal is negative.
--   * Adds CHECK so 'paid' commissions must carry a real Stripe transfer id.
--   * Adds composite (partner_id, created_at) index for earnings queries.
--   * Adds CHECK so 'reversed' rows must reference an original AND carry a
--     non-positive amount.
-- ============================================

-- 1. Reversal pointer column.
ALTER TABLE partner_commissions
  ADD COLUMN IF NOT EXISTS reversal_of_commission_id UUID
    REFERENCES partner_commissions(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_partner_commissions_reversal_of
  ON partner_commissions(reversal_of_commission_id)
  WHERE reversal_of_commission_id IS NOT NULL;

-- 2. Composite index for earnings range queries (Ch03-F076).
CREATE INDEX IF NOT EXISTS idx_partner_commissions_partner_created
  ON partner_commissions(partner_id, created_at DESC);

-- 3. CHECK: a 'paid' commission must have a Stripe transfer id.
ALTER TABLE partner_commissions
  DROP CONSTRAINT IF EXISTS chk_partner_commissions_paid_has_transfer;

ALTER TABLE partner_commissions
  ADD CONSTRAINT chk_partner_commissions_paid_has_transfer
  CHECK (status <> 'paid' OR stripe_transfer_id IS NOT NULL);

-- 4. CHECK: reversal rows must point back at an original commission AND
--    carry a non-positive amount. References 'reversed' literal, which only
--    works because 030a's ALTER TYPE has already committed.
ALTER TABLE partner_commissions
  DROP CONSTRAINT IF EXISTS chk_partner_commissions_reversal_shape;

ALTER TABLE partner_commissions
  ADD CONSTRAINT chk_partner_commissions_reversal_shape
  CHECK (
    status <> 'reversed'
    OR (reversal_of_commission_id IS NOT NULL AND amount <= 0)
  );

DO $$
BEGIN
  RAISE NOTICE 'Migration 030b complete: clawback ledger + transfer constraint';
END $$;
