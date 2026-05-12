-- 114: Partner-program simplification, phase 1 (additive nullability).
--
-- The partner program is being collapsed to "gifts only" — no Stripe, no
-- commissions, no payouts. This migration just relaxes the NOT NULL on the
-- two gift columns that the simplified createGift will stop writing, so we
-- can land the code change without a destructive schema migration in the
-- same release.
--
-- The actual column drops + table drops happen in phase 5, after the
-- application code has stopped touching these.
--
-- Why relax instead of drop now: this lets us roll back phases 2-4 by
-- redeploying the prior application image without a backwards migration.
-- Phase 5 is the one-way door.

BEGIN;

-- partner_gifts.amount_charged: was NOT NULL — the new createGift never
-- charges, so gifts will have NULL here.
ALTER TABLE partner_gifts ALTER COLUMN amount_charged DROP NOT NULL;

-- partner_gifts.premium_months: was NOT NULL DEFAULT 6 — the new createGift
-- relies on the default. Drop the NOT NULL so a future-phase code change
-- removing the column entirely can stop writing it earlier.
ALTER TABLE partner_gifts ALTER COLUMN premium_months DROP NOT NULL;

COMMIT;
