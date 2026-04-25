-- ============================================
-- Migration 035: warranty_purchase Stripe refund tracking (Ch04-F012)
-- Date: 2026-04-25
-- Description: Cancelling an active extended warranty was a DB-only flip; no
--   Stripe refund was issued and no idempotency key was persisted, so a
--   re-cancel could double-refund. Add stripe_refund_id + refund_amount_cents
--   so the cancel route can use upsert idempotency.
-- ============================================

ALTER TABLE warranty_purchases
  ADD COLUMN IF NOT EXISTS stripe_refund_id      VARCHAR(255),
  ADD COLUMN IF NOT EXISTS refund_amount_cents   INTEGER,
  ADD COLUMN IF NOT EXISTS refunded_at           TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS idx_warranty_purchases_stripe_refund
  ON warranty_purchases(stripe_refund_id)
  WHERE stripe_refund_id IS NOT NULL;

ALTER TABLE warranty_purchases
  DROP CONSTRAINT IF EXISTS chk_warranty_purchases_refund_shape;

ALTER TABLE warranty_purchases
  ADD CONSTRAINT chk_warranty_purchases_refund_shape
  CHECK (
    (refund_amount_cents IS NULL AND refunded_at IS NULL)
    OR (refund_amount_cents >= 0 AND refunded_at IS NOT NULL)
  );

DO $$
BEGIN
  RAISE NOTICE 'Migration 035 complete: warranty_purchase refund columns added';
END $$;
