-- Migration 106: index for case-insensitive email lookups (H14).
--
-- Several hot paths read `users` by `LOWER(email) = LOWER($1)` —
-- /me/change-email's existing-account check is the most visible.
-- Without a functional index this is a full table scan. Tiny today
-- but the change-email path runs synchronously inside the user
-- request, so even a quarter-second scan turns into user-perceived
-- latency.
--
-- Partial index: LIVE users only. Soft-deleted rows aren't candidates
-- for any of these lookups, and excluding them keeps the index small.

CREATE INDEX IF NOT EXISTS idx_users_lower_email_alive
  ON users (LOWER(email))
  WHERE deleted_at IS NULL;
