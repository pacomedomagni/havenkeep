-- Migration 112: add 'user.plan_reactivate' to the audit_action enum.
--
-- The TypeScript AuditAction union (audit.service.ts) and routes/users.ts
-- both reference `user.plan_reactivate` — it's emitted when a soft-deleted
-- ('suspended') user re-verifies a premium entitlement (e.g. an App Store
-- restore re-grants premium on the recovered account). The value was never
-- added to the PG enum (migration 004 has plan_upgrade / plan_downgrade
-- but not plan_reactivate; 025/096/104 never added it either). Without it,
-- the audit INSERT fails with 22P02 → the plan row has already been
-- updated by a prior statement, so the user gets a 500 *after* the change
-- committed, and no audit row is written for a security-relevant event.
--
-- ALTER TYPE ADD VALUE cannot run inside a transaction; the migration
-- runner auto-detects this and runs the file outside its BEGIN/COMMIT.

ALTER TYPE audit_action ADD VALUE IF NOT EXISTS 'user.plan_reactivate';

DO $$
BEGIN
  RAISE NOTICE 'Migration 112 complete: audit_action gained user.plan_reactivate';
END $$;
