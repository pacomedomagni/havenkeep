-- Migration 083: enable account-purge anonymization for warranty_* tables.
--
-- Audit C4: account-purge.service.ts does a plain DELETE FROM users WHERE
-- id = $1, but mig 028 deliberately set warranty_purchases.user_id and
-- warranty_claims.user_id to ON DELETE RESTRICT so paid records survive a
-- user soft-delete (DB031..032). The purge cron therefore hits 23503
-- (foreign_key_violation) for every paying user and skips them indefinitely
-- — GDPR/CCPA hard-delete is silently broken for paying users.
--
-- This migration enables anonymization-but-retention:
--   1. Add denormalized email columns so the financial trail keeps the
--      identifier of who bought / claimed (for tax + legal forensics).
--   2. Change the FK from RESTRICT to SET NULL so DELETE FROM users
--      succeeds and user_id naturally becomes NULL on the warranty rows.
--   3. account-purge.service.ts (separate change) populates the
--      denormalized email column BEFORE deleting the user, so the FK
--      action lands on rows that already carry a snapshotted identifier.
--
-- Existing rows (pre-migration) get NULL in user_email_at_purchase /
-- user_email_at_claim. The purge code only writes the column for users
-- it's about to delete; existing live users keep populating it as the
-- next-write side effect (see service-side change).

ALTER TABLE warranty_purchases
  ADD COLUMN IF NOT EXISTS user_email_at_purchase VARCHAR(320);

ALTER TABLE warranty_purchases
  DROP CONSTRAINT IF EXISTS warranty_purchases_user_id_fkey;

ALTER TABLE warranty_purchases
  ADD CONSTRAINT warranty_purchases_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE warranty_claims
  ADD COLUMN IF NOT EXISTS user_email_at_claim VARCHAR(320);

ALTER TABLE warranty_claims
  DROP CONSTRAINT IF EXISTS warranty_claims_user_id_fkey;

ALTER TABLE warranty_claims
  ADD CONSTRAINT warranty_claims_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

DO $$
BEGIN
  RAISE NOTICE 'Migration 083 complete: warranty_* anonymization columns added; user_id FKs now SET NULL';
END $$;
