-- ============================================
-- Migration 043: Backfill missing updated_at + soft-delete columns
--   (Ch00-DB036..038)
-- Date: 2026-04-25
-- Description: maintenance_history and email_scans were created without
--   updated_at; documents has no deleted_at and CASCADE-on-item-delete
--   means uploaded receipts vanish when the item is removed. Add the
--   missing audit columns + triggers; convert documents.item_id to ON
--   DELETE SET NULL with a soft-delete column.
-- ============================================

-- maintenance_history.updated_at
ALTER TABLE maintenance_history
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_maintenance_history_updated_at') THEN
    CREATE TRIGGER update_maintenance_history_updated_at
      BEFORE UPDATE ON maintenance_history
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

-- email_scans.updated_at
ALTER TABLE email_scans
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_email_scans_updated_at') THEN
    CREATE TRIGGER update_email_scans_updated_at
      BEFORE UPDATE ON email_scans
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

-- documents: soft delete + cascade tightening
ALTER TABLE documents
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_documents_user_not_deleted
  ON documents(user_id, created_at DESC)
  WHERE deleted_at IS NULL;

-- Convert item_id FK to SET NULL so deleting an item parks the receipts
-- rather than wiping them — matches Phase 1's CASCADE strategy for
-- warranty_purchases / warranty_claims.
ALTER TABLE documents
  DROP CONSTRAINT IF EXISTS documents_item_id_fkey;

ALTER TABLE documents
  ALTER COLUMN item_id DROP NOT NULL;

ALTER TABLE documents
  ADD CONSTRAINT documents_item_id_fkey
    FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE SET NULL;

-- documents.updated_at trigger if missing (DB001 mentioned schema.sql lacked it)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_documents_updated_at') THEN
    CREATE TRIGGER update_documents_updated_at
      BEFORE UPDATE ON documents
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

DO $$
BEGIN
  RAISE NOTICE 'Migration 043 complete: updated_at columns + soft-delete on documents';
END $$;
