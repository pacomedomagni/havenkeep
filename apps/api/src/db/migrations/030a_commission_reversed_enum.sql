-- ============================================
-- Migration 030a: Add 'reversed' to commission_status enum
-- Date: 2026-04-25
-- Description: Postgres requires a new enum value to be committed before it
--   can be referenced in any expression (CHECK, predicate, INSERT). The
--   migration runner wraps each file in BEGIN/COMMIT, so the ADD VALUE has
--   to live in its OWN file — file 030b then references the new value
--   inside its CHECK constraint after this commit lands.
--
--   IF NOT EXISTS guard makes the file safe to re-run / safe to ship after
--   a partial bootstrap.
-- ============================================

ALTER TYPE commission_status ADD VALUE IF NOT EXISTS 'reversed';

DO $$
BEGIN
  RAISE NOTICE 'Migration 030a complete: commission_status now contains ''reversed''';
END $$;
