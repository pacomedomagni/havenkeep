-- Migration 102: anonymize-but-retain partner_gifts + partner_commissions.
--
-- C0-10 (audit): when a user account is hard-deleted (account-purge cron
-- after the 30-day cooling-off window), the cascade chain
--   users → partners → partner_gifts → partner_commissions
-- erased the partner's entire commission ledger — including rows the
-- partner had already been PAID OUT on. The 1099-NEC tax reporting trail
-- (3-year retention requirement) disappeared in one DELETE. Mig 083
-- gave warranty_purchases / warranty_claims the SET NULL + denorm-email
-- treatment for the same reason; partners didn't get it.
--
-- Fix:
--   1. Drop NOT NULL on partner_id (otherwise SET NULL violates the
--      constraint as the cascade fires).
--   2. Drop the existing CASCADE FK; re-create as ON DELETE SET NULL.
--   3. Add denormalized columns (`partner_id_at_event`,
--      `partner_company_name_at_event`, `partner_email_at_event`)
--      snapshotted at INSERT time so the row remembers WHO was paid
--      even after the partner row is gone.
--
-- Service-layer code must populate the *_at_event columns on every
-- INSERT after this migration ships. The columns are nullable here so
-- the schema change is forward-only (zero users, no backfill); a future
-- NOT NULL constraint can land once every code path is wired.

-- ── partner_commissions ──────────────────────────────────────────

ALTER TABLE partner_commissions
  ALTER COLUMN partner_id DROP NOT NULL;

ALTER TABLE partner_commissions
  DROP CONSTRAINT IF EXISTS partner_commissions_partner_id_fkey;

ALTER TABLE partner_commissions
  ADD CONSTRAINT partner_commissions_partner_id_fkey
    FOREIGN KEY (partner_id) REFERENCES partners(id) ON DELETE SET NULL;

ALTER TABLE partner_commissions
  ADD COLUMN IF NOT EXISTS partner_id_at_event UUID,
  ADD COLUMN IF NOT EXISTS partner_company_name_at_event VARCHAR(255),
  ADD COLUMN IF NOT EXISTS partner_email_at_event VARCHAR(320);

-- ── partner_gifts ────────────────────────────────────────────────

ALTER TABLE partner_gifts
  ALTER COLUMN partner_id DROP NOT NULL;

ALTER TABLE partner_gifts
  DROP CONSTRAINT IF EXISTS partner_gifts_partner_id_fkey;

ALTER TABLE partner_gifts
  ADD CONSTRAINT partner_gifts_partner_id_fkey
    FOREIGN KEY (partner_id) REFERENCES partners(id) ON DELETE SET NULL;

ALTER TABLE partner_gifts
  ADD COLUMN IF NOT EXISTS partner_id_at_event UUID,
  ADD COLUMN IF NOT EXISTS partner_company_name_at_event VARCHAR(255),
  ADD COLUMN IF NOT EXISTS partner_email_at_event VARCHAR(320);

DO $$
BEGIN
  RAISE NOTICE 'Migration 102 complete: partner_gifts + partner_commissions retain identity after partner DELETE';
END $$;
