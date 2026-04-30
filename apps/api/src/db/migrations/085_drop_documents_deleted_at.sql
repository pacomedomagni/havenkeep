-- Migration 085: drop documents.deleted_at + idx_documents_user_not_deleted.
--
-- Audit H-D3: mig 043 added documents.deleted_at TIMESTAMPTZ + a partial
-- index `idx_documents_user_not_deleted ... WHERE deleted_at IS NULL`,
-- intending soft-delete semantics. Two years on, no code path writes
-- to the column (verified by grep across apps/api/src/), and every
-- DELETE handler is a hard-delete.
--
-- The partial index is therefore identical in coverage to a full index
-- (every row has deleted_at = NULL), and the column is dead schema.
-- CLAUDE.md Rule 3 forbids dead code — drop both.
--
-- If product later wants soft-delete-with-recovery on documents, that
-- needs to be a deliberate feature decision (UI + grace-window UX +
-- the storage-cleanup cron has to skip rows whose deleted_at is set).
-- Adding the column without that wiring was the original Rule 3
-- violation; this migration corrects it.

DROP INDEX IF EXISTS idx_documents_user_not_deleted;
ALTER TABLE documents DROP COLUMN IF EXISTS deleted_at;

DO $$
BEGIN
  RAISE NOTICE 'Migration 085 complete: documents.deleted_at + partial index dropped (H-D3)';
END $$;
