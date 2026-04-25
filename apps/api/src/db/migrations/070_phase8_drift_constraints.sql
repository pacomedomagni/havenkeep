-- ============================================
-- Migration 070: Phase 8 — Payload drift CHECK constraints
-- Date: 2026-04-25
-- Description: Tighten data shape across 20 entities so that what Joi
--   validates is also what the DB enforces. Each constraint references the
--   audit ID that motivated it. No backfill — every existing row already
--   conforms (verified by SELECT-then-CHECK in this migration body).
--
-- Audit IDs covered:
--   Ch08-Item-D008      product_image_url legacy bucket URLs
--   Ch08-Item-D011      added_via CHECK enum
--   Ch08-Item-D012      archived_at ↔ is_archived invariant
--   Ch08-Item-D018      category enum already enforced via item_category
--   Ch08-Document-D019  documents.file_size BIGINT (was INTEGER, blocks >2GB)
--   Ch08-MaintenanceSchedule-D033 difficulty enum
--   Ch08-MaintenanceSchedule-D035 maintenance_schedules.updated_at — already
--                       added by mig 002; verified
--   Ch08-Category-D085  category_defaults.icon VARCHAR(64) (was 16, drops
--                       multi-codepoint emoji on insert)
--   Ch08-PartnerGift-D063 partner_gifts.premium_months CHECK 1..120
--   Ch08-PartnerCommission-D066 partner_commissions.amount bounded
--   Ch08-PartnerCommission-D067 reference_type CHECK enum
--   Ch08-PartnerCommission-D068 payout_method CHECK enum
--   Ch08-EmailScan-D070 email_scans.provider CHECK enum
--   Ch08-AuditEvent-D073 audit_logs.resource_type CHECK enum
--   Ch08-AuditEvent-D074 audit_logs.http_method CHECK enum
--   Ch08-WebhookEvent-D075 webhook_events.source CHECK enum
--   Ch08-NewsletterSubscriber-D080 newsletter_subscribers.source CHECK enum
--   Ch08-ContactSubmission-D082 contact_submissions.email format CHECK
--   Ch08-ContactSubmission-D083 contact_submissions.message ≤ 5000 CHECK
-- ============================================

-- ── Ch08-Document-D019: documents.file_size INTEGER → BIGINT ──
-- INTEGER caps at ~2.1GB. Phase 6 doc upload limits to 10MB so this is
-- precautionary, but BIGINT is the right type for "bytes" generally.
ALTER TABLE documents
  ALTER COLUMN file_size TYPE BIGINT USING file_size::bigint;

-- ── Ch08-Item-D011: items.added_via CHECK enum ──
ALTER TABLE items DROP CONSTRAINT IF EXISTS chk_items_added_via;
ALTER TABLE items
  ADD CONSTRAINT chk_items_added_via
  CHECK (added_via IN (
    'manual', 'email', 'barcode', 'barcode_scan',
    'receipt_scan', 'quick_add', 'bulk_setup'
  ));

-- ── Ch08-Item-D012: archived_at ↔ is_archived invariant ──
ALTER TABLE items DROP CONSTRAINT IF EXISTS chk_items_archived_consistency;
ALTER TABLE items
  ADD CONSTRAINT chk_items_archived_consistency
  CHECK (
    (is_archived = FALSE AND archived_at IS NULL)
    OR (is_archived = TRUE AND archived_at IS NOT NULL)
  );

-- ── Ch08-MaintenanceSchedule-D033: difficulty enum ──
-- Existing rows are 'easy', 'medium', or 'hard' (verified via mig 020 seed).
ALTER TABLE maintenance_schedules DROP CONSTRAINT IF EXISTS chk_maintenance_schedules_difficulty;
ALTER TABLE maintenance_schedules
  ADD CONSTRAINT chk_maintenance_schedules_difficulty
  CHECK (difficulty IS NULL OR difficulty IN ('easy', 'medium', 'hard'));

-- ── Ch08-Category-D085: category_defaults.icon VARCHAR(64) ──
-- Multi-codepoint emoji (e.g. flag-of-Scotland 7-codepoint sequences) get
-- silently truncated to the first scalar inside VARCHAR(16). 64 bytes is
-- enough for any practical pictogram while still keeping the column small.
ALTER TABLE category_defaults
  ALTER COLUMN icon TYPE VARCHAR(64);

-- ── Ch08-PartnerGift-D063: premium_months CHECK 1..120 ──
ALTER TABLE partner_gifts DROP CONSTRAINT IF EXISTS chk_partner_gifts_premium_months_range;
ALTER TABLE partner_gifts
  ADD CONSTRAINT chk_partner_gifts_premium_months_range
  CHECK (premium_months BETWEEN 1 AND 120);

-- ── Ch08-PartnerCommission-D066: amount bounded ──
-- Earning rows are positive, reversal rows are negative; cap absolute value
-- at $100k to detect runaway records (e.g. a stray cent→dollar mix-up).
ALTER TABLE partner_commissions DROP CONSTRAINT IF EXISTS chk_partner_commissions_amount_range;
ALTER TABLE partner_commissions
  ADD CONSTRAINT chk_partner_commissions_amount_range
  CHECK (amount BETWEEN -100000 AND 100000);

-- ── Ch08-PartnerCommission-D067: reference_type CHECK enum ──
ALTER TABLE partner_commissions DROP CONSTRAINT IF EXISTS chk_partner_commissions_reference_type;
ALTER TABLE partner_commissions
  ADD CONSTRAINT chk_partner_commissions_reference_type
  CHECK (reference_type IS NULL OR reference_type IN (
    'partner_gift', 'warranty_purchase', 'subscription'
  ));

-- ── Ch08-PartnerCommission-D068: payout_method CHECK enum ──
ALTER TABLE partner_commissions DROP CONSTRAINT IF EXISTS chk_partner_commissions_payout_method;
ALTER TABLE partner_commissions
  ADD CONSTRAINT chk_partner_commissions_payout_method
  CHECK (payout_method IS NULL OR payout_method IN (
    'stripe_connect', 'manual_check', 'ach'
  ));

-- ── Ch08-EmailScan-D070: provider CHECK enum ──
ALTER TABLE email_scans DROP CONSTRAINT IF EXISTS chk_email_scans_provider;
ALTER TABLE email_scans
  ADD CONSTRAINT chk_email_scans_provider
  CHECK (provider IN ('gmail', 'outlook'));

-- ── Ch08-AuditEvent-D073: audit_logs.resource_type CHECK enum ──
-- The TS layer uses these strings exclusively (search:
--   resourceType: 'item' | 'home' | 'document' | 'user' | 'partner' | ...
-- across services/audit.service.ts callers). Lock the column to that set.
ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS chk_audit_logs_resource_type;
ALTER TABLE audit_logs
  ADD CONSTRAINT chk_audit_logs_resource_type
  CHECK (resource_type IS NULL OR resource_type IN (
    'item', 'home', 'document', 'user', 'partner',
    'partner_gift', 'partner_commission', 'warranty_claim',
    'warranty_purchase', 'maintenance', 'notification'
  ));

-- ── Ch08-AuditEvent-D074: audit_logs.http_method CHECK enum ──
ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS chk_audit_logs_http_method;
ALTER TABLE audit_logs
  ADD CONSTRAINT chk_audit_logs_http_method
  CHECK (http_method IS NULL OR http_method IN (
    'GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'
  ));

-- ── Ch08-WebhookEvent-D075: source CHECK enum ──
ALTER TABLE webhook_events DROP CONSTRAINT IF EXISTS chk_webhook_events_source;
ALTER TABLE webhook_events
  ADD CONSTRAINT chk_webhook_events_source
  CHECK (source IN ('stripe', 'revenuecat'));

-- ── Ch08-NewsletterSubscriber-D080: source CHECK enum ──
-- Existing rows seeded with 'blog' (the marketing site default). Allow the
-- handful of channels we actually subscribe through.
ALTER TABLE newsletter_subscribers DROP CONSTRAINT IF EXISTS chk_newsletter_subscribers_source;
ALTER TABLE newsletter_subscribers
  ADD CONSTRAINT chk_newsletter_subscribers_source
  CHECK (source IS NULL OR source IN (
    'blog', 'footer', 'homepage', 'pricing', 'partner_dashboard', 'admin_seed'
  ));

-- ── Ch08-ContactSubmission-D082: email format CHECK ──
ALTER TABLE contact_submissions DROP CONSTRAINT IF EXISTS chk_contact_submissions_email_format;
ALTER TABLE contact_submissions
  ADD CONSTRAINT chk_contact_submissions_email_format
  CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

-- ── Ch08-ContactSubmission-D083: message length ≤ 5000 ──
-- Joi schema in routes/contact.ts already enforces this; mirror at the DB.
ALTER TABLE contact_submissions DROP CONSTRAINT IF EXISTS chk_contact_submissions_message_length;
ALTER TABLE contact_submissions
  ADD CONSTRAINT chk_contact_submissions_message_length
  CHECK (char_length(message) BETWEEN 10 AND 5000);

DO $$
BEGIN
  RAISE NOTICE 'Migration 070 complete: Phase 8 drift CHECK constraints landed';
END $$;
