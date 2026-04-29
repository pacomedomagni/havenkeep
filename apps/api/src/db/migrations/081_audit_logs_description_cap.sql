-- Migration 081: cap audit_logs.description (S-LO-05)
--
-- Most callers pass short descriptions but some interpolate user-named
-- content (e.g. "Created home: <name>"). The validators cap inputs but
-- a misconfigured caller could still write a multi-KB row. Hard-cap at
-- 4000 chars (matches the longest legitimate description we use today
-- with comfortable headroom).

-- Trim any pre-existing rows that exceed the cap. Idempotent: rows
-- already shorter than 4000 chars are a no-op.
UPDATE audit_logs
SET description = LEFT(description, 4000)
WHERE description IS NOT NULL
  AND char_length(description) > 4000;

ALTER TABLE audit_logs
  DROP CONSTRAINT IF EXISTS chk_audit_logs_description_size;
ALTER TABLE audit_logs
  ADD CONSTRAINT chk_audit_logs_description_size
  CHECK (description IS NULL OR char_length(description) <= 4000);
