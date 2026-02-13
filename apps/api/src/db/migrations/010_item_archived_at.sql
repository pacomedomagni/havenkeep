-- Add archived_at to items for accurate archive timestamp

ALTER TABLE items
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;

UPDATE items
SET archived_at = COALESCE(archived_at, updated_at)
WHERE is_archived = TRUE;
