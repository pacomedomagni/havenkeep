-- ============================================
-- Migration 039: Email scanner review queue (Ch09-FlowB-T-B6, T-B7)
-- Date: 2026-04-25
-- Description: The scanner pipes any email body through OpenAI and acts on
--   the JSON it returns. Prompt-injection in the email body lets a spoofed
--   sender insert items into a victim's account silently. New rule: only
--   trusted retailer domains auto-create items; everything else is parked
--   in this queue for the user to review in-app.
-- ============================================

CREATE TYPE email_scan_review_state AS ENUM ('pending', 'approved', 'rejected');

CREATE TABLE IF NOT EXISTS email_scanner_review_queue (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email_scan_id UUID NOT NULL REFERENCES email_scans(id) ON DELETE CASCADE,

  sender_address VARCHAR(320) NOT NULL,
  sender_domain  VARCHAR(255) NOT NULL,
  subject TEXT,

  suggested_item JSONB NOT NULL,
  confidence_score NUMERIC(3, 2) NOT NULL CHECK (confidence_score >= 0 AND confidence_score <= 1),
  rejection_reason TEXT,
  rejected_by_pattern VARCHAR(120),

  state email_scan_review_state NOT NULL DEFAULT 'pending',
  reviewed_at TIMESTAMPTZ,
  applied_item_id UUID REFERENCES items(id) ON DELETE SET NULL,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_email_scan_review_applied
    CHECK (state <> 'approved' OR applied_item_id IS NOT NULL OR reviewed_at IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_email_review_user_state
  ON email_scanner_review_queue(user_id, state, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_email_review_scan
  ON email_scanner_review_queue(email_scan_id);

DO $$
BEGIN
  RAISE NOTICE 'Migration 039 complete: email scanner review queue created';
END $$;
