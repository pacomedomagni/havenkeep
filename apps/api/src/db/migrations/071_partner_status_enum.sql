-- Audit Ch10-W054: replace the overloaded `is_active` boolean on partners
-- with an explicit three-state status. The boolean conflated two distinct
-- "false" reasons (never approved vs explicitly rejected) which the dashboard
-- couldn't disambiguate.
--
-- The boolean stays for backwards-compat queries (the audit doc's "no backfill"
-- rule applies at the API contract layer; the dashboard now reads the new
-- `status` column and the API surfaces both fields). New code paths must use
-- `status`.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'partner_status') THEN
    CREATE TYPE partner_status AS ENUM ('pending', 'active', 'rejected');
  END IF;
END
$$;

ALTER TABLE partners
  ADD COLUMN IF NOT EXISTS status partner_status NOT NULL DEFAULT 'pending';

-- Map the existing boolean into the new column. After this runs, both
-- `is_active` and `status` are kept in sync by the route handlers; readers
-- should prefer `status`.
UPDATE partners
SET status = CASE WHEN is_active THEN 'active'::partner_status ELSE 'pending'::partner_status END
WHERE status IS NULL OR (is_active = TRUE AND status <> 'active') OR (is_active = FALSE AND status = 'active');

CREATE INDEX IF NOT EXISTS idx_partners_status ON partners(status);
