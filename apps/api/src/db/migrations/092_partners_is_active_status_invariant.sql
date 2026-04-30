-- Migration 092: enforce (is_active = TRUE) ⇔ (status = 'active')
-- on partners with a CHECK constraint.
--
-- Audit M-D4: mig 071 added the partner_status enum but kept the
-- legacy is_active boolean alongside it, with a comment "kept in sync
-- by the route handlers." Eight reader sites still read is_active
-- (admin.ts:73,626,688 etc.) — there is no DB invariant guaranteeing
-- the two stay coherent, so a future writer that flips one without
-- the other (or a manual SQL intervention) silently desyncs every
-- "is partner" check.
--
-- The principled fix is to drop is_active entirely and migrate every
-- reader to status. That's a larger change (Phase 4 mediums set the
-- direction; Phase 5 polish would actually delete the column once
-- callers have migrated). For now, lock the invariant via CHECK so
-- a desync surfaces as a 23514 instead of silent corruption.

ALTER TABLE partners
  DROP CONSTRAINT IF EXISTS chk_partners_active_status_consistent;

ALTER TABLE partners
  ADD CONSTRAINT chk_partners_active_status_consistent
  CHECK ((is_active = TRUE) = (status = 'active'));

DO $$
BEGIN
  RAISE NOTICE 'Migration 092 complete: partners is_active/status invariant CHECK added (M-D4)';
END $$;
