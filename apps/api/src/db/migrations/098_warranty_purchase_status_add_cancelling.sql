-- Migration 098: add 'cancelling' to warranty_purchase_status enum.
--
-- WarrantyPurchasesService.cancelPurchase splits the cancel into three
-- phases (lock+claim, Stripe refund, finalize). Phase 1 flips the row's
-- status to a transient 'cancelling' so a duplicate request short-
-- circuits while the Stripe call is in flight. Phase 3 finalizes to
-- 'cancelled'.
--
-- The enum (mig 002) only had {active, expired, cancelled, claimed,
-- pending}, so the phase-1 UPDATE to 'cancelling' raised PG 22P02
-- ("invalid input value for enum"). Net effect: every cancel returned
-- 400 with a generic "Field has the wrong type or format" message,
-- and no warranty purchase could ever be cancelled in prod.
--
-- ALTER TYPE ADD VALUE cannot run inside a transaction; the migration
-- runner detects this pattern and runs the file outside its tx wrapper.

ALTER TYPE warranty_purchase_status ADD VALUE IF NOT EXISTS 'cancelling';

DO $$
BEGIN
  RAISE NOTICE 'Migration 098 complete: warranty_purchase_status now includes cancelling';
END $$;
