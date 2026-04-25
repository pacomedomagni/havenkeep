-- ============================================
-- Migration 073: Partner welcome-email open tracker (Ch03-F083/F084)
-- Date: 2026-04-25
-- Description: A 1x1 tracking pixel was already in the gift-activation
--   email; the welcome email had nothing. Add the column the welcome-pixel
--   route writes to. Same shape as `partner_gifts.email_opened_at` so the
--   admin dashboard can render both side-by-side without a special case.
--   COALESCE-set semantics in the route mean the first open wins.
-- ============================================

ALTER TABLE partners
  ADD COLUMN IF NOT EXISTS welcome_email_opened_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_partners_welcome_email_opened
  ON partners(welcome_email_opened_at)
  WHERE welcome_email_opened_at IS NOT NULL;

DO $$
BEGIN
  RAISE NOTICE 'Migration 073 complete: partners.welcome_email_opened_at added';
END $$;
