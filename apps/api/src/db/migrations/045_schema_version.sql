-- ============================================
-- Migration 045: schema_version table for partial-bootstrap detection
--   (Ch00-DB003)
-- Date: 2026-04-25
-- Description: ensureBaseSchema in run-migration.ts treated "users table
--   exists" as proof that schema.sql had run. That races a partial bootstrap
--   (e.g. crash mid-schema-load) where some tables exist and others don't.
--   Persist a row per fully-applied schema phase so the bootstrap helper
--   has a definitive completion marker.
-- ============================================

CREATE TABLE IF NOT EXISTS schema_version (
  -- Phase identifier: 'base' for schema.sql, or migration filename for
  -- numbered migrations.
  phase VARCHAR(255) PRIMARY KEY,
  completed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- pg version + extension state at apply time, useful for triage
  pg_version TEXT,
  -- sha256 of the SQL file applied; helps catch silent mutation
  source_sha256 CHAR(64)
);

-- Mark the base schema as applied if all canonical tables exist. This
-- lets a fresh-from-master DB pick up where the old bootstrap left off
-- without re-running schema.sql against an already-populated database.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'users')
     AND EXISTS (SELECT 1 FROM pg_class WHERE relname = 'items')
     AND EXISTS (SELECT 1 FROM pg_class WHERE relname = 'partners')
  THEN
    INSERT INTO schema_version (phase, pg_version)
      VALUES ('base', current_setting('server_version'))
      ON CONFLICT (phase) DO NOTHING;
  END IF;
END $$;

COMMENT ON TABLE schema_version IS
  'Definitive record of which schema phases have completed. Read by run-migration.ts to skip schema.sql bootstrap on already-initialized DBs.';

DO $$
BEGIN
  RAISE NOTICE 'Migration 045 complete: schema_version table installed';
END $$;
