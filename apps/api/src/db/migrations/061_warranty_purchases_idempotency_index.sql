-- ============================================
-- Migration 061: warranty_purchases idempotency + expiry hot-path index
--   (Ch04-F020, F021)
-- Date: 2026-04-25
-- Description:
--   A double-tap on /warranty-purchases (or a Stripe webhook retry) could
--   create two rows pointing at the same payment_intent_id. Add a partial
--   UNIQUE index so we surface 23505 instead of double-charging the user.
--   Also add a composite (user_id, expires_at) index for getExpiringWarranties
--   which currently scans by user_id then filters in memory.
-- ============================================

-- Idempotency: one row per (user, payment_intent_id) where the payment
-- intent is set. Partial index so legacy rows with NULL aren't blocked.
CREATE UNIQUE INDEX IF NOT EXISTS uniq_warranty_purchases_user_payment_intent
  ON warranty_purchases (user_id, stripe_payment_intent_id)
  WHERE stripe_payment_intent_id IS NOT NULL;

-- Hot path for /warranty-purchases/expiring + the daily expire job.
CREATE INDEX IF NOT EXISTS idx_warranty_purchases_user_expires
  ON warranty_purchases (user_id, expires_at)
  WHERE status = 'active';

DO $$
BEGIN
  RAISE NOTICE 'Migration 061 complete: idempotency UNIQUE + expiring index';
END $$;
