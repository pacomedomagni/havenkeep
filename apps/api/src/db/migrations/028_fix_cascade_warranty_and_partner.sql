-- ============================================
-- Migration 028: Fix CASCADE rules that wipe paid records (Ch00-DB031..034)
-- Date: 2026-04-25
-- Description: Several FKs were created with ON DELETE CASCADE on tables that
--   carry money/commission state. Deleting an item or partner therefore wiped
--   the paid policy / settled claim / commission ledger / gift record. This
--   migration converts each to ON DELETE SET NULL (where the record can survive
--   without its parent) or ON DELETE RESTRICT (where the parent must be retained
--   for tax / legal traceability).
-- ============================================

-- warranty_purchases.item_id   CASCADE -> SET NULL  (DB031)
-- warranty_purchases.user_id   CASCADE -> RESTRICT  (paid policies must survive user soft-delete)
ALTER TABLE warranty_purchases
  DROP CONSTRAINT IF EXISTS warranty_purchases_item_id_fkey,
  DROP CONSTRAINT IF EXISTS warranty_purchases_user_id_fkey;

ALTER TABLE warranty_purchases
  ALTER COLUMN item_id DROP NOT NULL;

ALTER TABLE warranty_purchases
  ADD CONSTRAINT warranty_purchases_item_id_fkey
    FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE SET NULL,
  ADD CONSTRAINT warranty_purchases_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT;

-- warranty_claims.item_id   CASCADE -> SET NULL  (DB032)
-- warranty_claims.user_id   CASCADE -> RESTRICT
ALTER TABLE warranty_claims
  DROP CONSTRAINT IF EXISTS warranty_claims_item_id_fkey,
  DROP CONSTRAINT IF EXISTS warranty_claims_user_id_fkey;

ALTER TABLE warranty_claims
  ALTER COLUMN item_id DROP NOT NULL;

ALTER TABLE warranty_claims
  ADD CONSTRAINT warranty_claims_item_id_fkey
    FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE SET NULL,
  ADD CONSTRAINT warranty_claims_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT;

-- partner_commissions.partner_id   CASCADE -> RESTRICT  (DB033)
ALTER TABLE partner_commissions
  DROP CONSTRAINT IF EXISTS partner_commissions_partner_id_fkey;

ALTER TABLE partner_commissions
  ADD CONSTRAINT partner_commissions_partner_id_fkey
    FOREIGN KEY (partner_id) REFERENCES partners(id) ON DELETE RESTRICT;

-- partner_gifts.partner_id   CASCADE -> RESTRICT  (DB034)
ALTER TABLE partner_gifts
  DROP CONSTRAINT IF EXISTS partner_gifts_partner_id_fkey;

ALTER TABLE partner_gifts
  ADD CONSTRAINT partner_gifts_partner_id_fkey
    FOREIGN KEY (partner_id) REFERENCES partners(id) ON DELETE RESTRICT;

DO $$
BEGIN
  RAISE NOTICE 'Migration 028 complete: CASCADE rules tightened on warranty + partner FKs';
END $$;
