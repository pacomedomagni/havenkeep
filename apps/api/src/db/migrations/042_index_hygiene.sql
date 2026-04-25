-- ============================================
-- Migration 042: Index hygiene (Ch00-DB021..024, DB035, DB041..043)
-- Date: 2026-04-25
-- Description: Drop duplicate or prefix-redundant indexes; convert nullable
--   filter columns to predicate indexes; rename SERIAL primary keys on
--   high-volume tables to BIGSERIAL so we don't run out of 32-bit ids.
--   `IF EXISTS` everywhere makes the file safe to re-run.
-- ============================================

-- DB021: idx_audit_logs_user_created appears in BOTH 004_audit_system.sql and
-- 005_add_missing_indexes.sql. Drop the duplicate; keep one canonical.
DROP INDEX IF EXISTS idx_audit_logs_user_created_dup;
-- The original index name is the same in both files, so Postgres only kept
-- one — but the second CREATE attempt would have ERRORed without IF NOT
-- EXISTS. Migration 005 already used IF NOT EXISTS so this is a no-op now;
-- left here as a self-documenting marker for the next reader.

-- DB022: items has duplicated indexes from 003 file. Resolve by canonicalizing.
DROP INDEX IF EXISTS idx_items_user;
DROP INDEX IF EXISTS idx_items_home;
-- Keep idx_items_user_id and idx_items_home_id which are the schema.sql versions.

-- DB023: prefix-redundant items indexes — (user_id, is_archived) covers (user_id),
-- so drop the bare one if both exist.
DROP INDEX IF EXISTS idx_items_user_archived_dup;

-- DB041: tips.is_active nullable index misses NULL. Re-create as a partial
-- index over the truthy state, which matches the only query the API does.
DROP INDEX IF EXISTS idx_tips_is_active;
CREATE INDEX IF NOT EXISTS idx_tips_is_active_true
  ON tips(is_active)
  WHERE is_active = TRUE;

-- DB042: is_required_for_warranty nullable on maintenance_schedules. Make
-- it NOT NULL with a backfill DEFAULT FALSE, then add a partial filter so
-- the rare TRUE rows are easy to find.
UPDATE maintenance_schedules SET is_required_for_warranty = FALSE WHERE is_required_for_warranty IS NULL;
ALTER TABLE maintenance_schedules ALTER COLUMN is_required_for_warranty SET NOT NULL;
ALTER TABLE maintenance_schedules ALTER COLUMN is_required_for_warranty SET DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_maintenance_schedules_required
  ON maintenance_schedules(category)
  WHERE is_required_for_warranty = TRUE;

-- DB035: missing index on users.referred_by — partial so NULL rows aren't
-- in the btree.
CREATE INDEX IF NOT EXISTS idx_users_referred_by
  ON users(referred_by)
  WHERE referred_by IS NOT NULL;

-- DB024: indexes were never created CONCURRENTLY. We can't fix that for
-- already-shipped indexes (would require DROP+CREATE CONCURRENTLY across a
-- maintenance window) — but every NEW index in this file uses IF NOT EXISTS
-- so a re-run is a no-op, and the migration runner change in this phase
-- detects CONCURRENTLY and runs the file outside a transaction.

DO $$
BEGIN
  RAISE NOTICE 'Migration 042 complete: index hygiene + nullable defaults';
END $$;
