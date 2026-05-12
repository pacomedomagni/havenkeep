-- Migration 113: drop the audit_logs.user_id FK (DEFERRED.md §8).
--
-- The contradiction: `audit_logs.user_id` was declared
-- `REFERENCES users(id) ON DELETE SET NULL` (mig 004), AND `user_id::text`
-- is part of the hashed payload that the BEFORE INSERT trigger commits
-- to (mig 065/082/101). When the daily soft-delete-purge cron runs
-- `DELETE FROM users WHERE id = $1` for an expired soft-deleted account,
-- Postgres fires a row-level UPDATE on every `audit_logs` row that
-- referenced that user, setting `user_id` → NULL. Two failure modes:
--
--   • In the intended security config (the API role is NOT a member of
--     `audit_cleaner`), the `audit_logs_immutable` BEFORE UPDATE trigger
--     raises → the user DELETE rolls back → **no user with audit history
--     can ever be hard-deleted**. GDPR erasure silently never completes.
--
--   • If the immutable trigger is bypassable for the API role (the bad
--     security config), the cascade succeeds → mutating `user_id` to
--     NULL changes the hashed payload of those rows → their stored
--     `this_hash` no longer recomputes → `verify_audit_chain()` flags
--     every such row → the daily verifier emails "INTEGRITY FAILURE —
--     possible tampering" after every purge. Self-inflicted alarms.
--
-- Fix (DEFERRED.md §8 option 2, recommended): drop the FK entirely. The
-- `user_id` column stays — it's UUID, it's indexed, it's still part of
-- the hash, and queries that need the user row already `LEFT JOIN` so a
-- dangling-but-stable ID just resolves to NULL on the join side. The
-- denormalised `user_email` column (mig 004) already preserves "who"
-- for purged users — that's where forensic queries should look anyway.
--
-- Existing rows are not modified (`user_id` keeps whatever value it
-- currently holds; rows that previously CASCADE'd to NULL via the old
-- behaviour keep NULL — that's fine). The hash chain is unaffected — the
-- payload formula is unchanged, only the referential constraint goes.
-- No re-baselining required.
--
-- Concurrency: `ALTER TABLE … DROP CONSTRAINT` takes an `ACCESS EXCLUSIVE`
-- lock on `audit_logs`, but only briefly (catalog change, no data
-- rewrite). The deploy.sh migration step blocks API writes for the
-- duration anyway; this is a small added contention window during
-- migration time, not steady-state.
--
-- Operator note: `audit_logs` is owned by `audit_cleaner` (mig 101), so
-- this `DROP CONSTRAINT` requires the migration role to be a superuser
-- or a member of `audit_cleaner` — the *same* prerequisite that let
-- mig 101 reassign ownership in the first place. If 101 applied
-- successfully on a deployment, 113 will too. `verify-audit-isolation.sh`
-- confirms ownership; if it reports `audit_logs owner = havenkeep`
-- (case 3b in the audit deep-dive), 101 never ran and this fix is moot
-- because the chain hardening itself isn't in place — fix that first.

ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS audit_logs_user_id_fkey;

-- The `idx_audit_logs_user_id` and `idx_audit_logs_user_created` indexes
-- from mig 004 are kept — they index the value, not the FK, and remain
-- useful for the admin "show audit history for user X" query.

DO $$
BEGIN
  RAISE NOTICE 'Migration 113 complete: audit_logs.user_id is now a soft pointer (no FK). Purge can complete; chain stays intact.';
END $$;
