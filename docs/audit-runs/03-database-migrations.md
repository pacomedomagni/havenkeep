# Audit Run 03 — Database Layer (schema, migrations, audit chain, idempotency, encryption)

**Scope:** `apps/api/src/db/schema.sql`, all 100+ migrations, `db/index.ts` (pool), `db/migrations/run-migration.ts` (runner), `utils/oauth-encryption.ts`. Application logic, routes, services intentionally out of scope.

**Date:** 2026-05-10

---

## CRITICAL

### C1 — Migration runner's "non-transactional" detection regex anchors on file start, not line start, so it never fires for any real-world file

**File:** `apps/api/src/db/migrations/run-migration.ts:14-19, 26-31`

```ts
const NON_TXN_PATTERNS: RegExp[] = [
  /^\s*ALTER\s+TYPE\s+\w+\s+ADD\s+VALUE\b/i,
  /^\s*CREATE\s+(UNIQUE\s+)?INDEX\s+CONCURRENTLY\b/i,
  ...
];
function fileNeedsAutoCommit(sql: string): boolean {
  const stripped = sql.replace(/\/\*[\s\S]*?\*\//g, '');
  return NON_TXN_PATTERNS.some((re) => re.test(stripped));
}
```

The regexes use only the `i` flag — **not** the `m` (multiline) flag. Without `m`, `^` matches the start of the **string**, not the start of each line. The strip pass only removes `/* … */` block comments, not `-- …` line comments. Every migration in this repo opens with a `-- Migration NNN:` header, so the SQL string never starts with whitespace + `ALTER` / `CREATE`. The regex therefore returns `false` for every file in the tree.

Verified empirically against migrations 021, 030a, 042, 096, 098 — `fileNeedsAutoCommit()` returns `false` for all of them. CLAUDE.md's claim that "the runner auto-detects ALTER TYPE ADD VALUE and CREATE INDEX CONCURRENTLY and runs those files outside transactions" is **false in implementation**.

**Why this hasn't blown up yet:**
- PostgreSQL 12+ allows `ALTER TYPE … ADD VALUE` inside a transaction as long as the new value isn't *referenced* in the same transaction. Every existing `ALTER TYPE` migration (021, 022, 023, 025, 030a, 098, 096, 014, 008, 011) only adds values without referencing them. Mig 030b does reference `'reversed'` but lives in a separate file (per the comment in 030a:1-19 explaining exactly this split), so it commits in its own transaction *after* 030a commits.
- There are **no** `CREATE INDEX CONCURRENTLY` migrations in the tree currently. Mig 042 mentions CONCURRENTLY only inside a comment (line 51-55), so the broken regex doesn't matter.

**Why it's a Critical bug regardless:** the safety net is silently disarmed. The next contributor who:
1. Adds an `ALTER TYPE … ADD VALUE` and references the new value in the same file (forgetting the 030a/030b split convention), OR
2. Adds a `CREATE INDEX CONCURRENTLY` (perfectly reasonable for a large existing table), OR
3. Adds a `REINDEX … CONCURRENTLY` or `DROP INDEX CONCURRENTLY`

…will see the migration fail with `25001: cannot run inside a transaction block` on every replica simultaneously, and the lock-bearing replica will keep retrying.

**Fix:** either add the `m` flag and split SQL by lines (more correct: skip line-comments first), or scan line-by-line. Suggested:

```ts
const NON_TXN_PATTERNS: RegExp[] = [
  /^\s*ALTER\s+TYPE\s+\w+\s+ADD\s+VALUE\b/i,
  /^\s*CREATE\s+(UNIQUE\s+)?INDEX\s+CONCURRENTLY\b/i,
  ...
];
function fileNeedsAutoCommit(sql: string): boolean {
  // Strip block comments first so a SQL keyword inside /* ... */ doesn't trip detection.
  const stripped = sql.replace(/\/\*[\s\S]*?\*\//g, '');
  for (const rawLine of stripped.split('\n')) {
    const line = rawLine.replace(/--.*$/, '');  // strip line-comments
    if (NON_TXN_PATTERNS.some((re) => re.test(line))) return true;
  }
  return false;
}
```

---

### C2 — `audit_logs.id` UUID + `created_at` ordering means `verify_audit_chain()` can flag false positives on rows inserted in the same wallclock microsecond

**Files:**
- `apps/api/src/db/migrations/004_audit_system.sql:78-82` (`id UUID PRIMARY KEY DEFAULT uuid_generate_v4()`)
- `apps/api/src/db/migrations/065_audit_log_hash_chain.sql:31-34, 73`
- `apps/api/src/db/migrations/082_audit_chain_advisory_lock_fix_casts.sql:26-29`

The trigger reads the predecessor row by:
```sql
SELECT this_hash INTO v_prev FROM audit_logs ORDER BY created_at DESC, id DESC LIMIT 1;
```

The verifier walks the chain by:
```sql
SELECT * FROM audit_logs ORDER BY created_at ASC, id ASC
```

Two issues:
1. **Tie-breaker mismatch with `id`**: `id` is a random UUID (`uuid_generate_v4()`), so the secondary sort `id DESC`/`id ASC` produces a *different* deterministic order between rows that share `created_at` (microsecond-precision TIMESTAMPTZ — collisions happen under high load). The trigger picks "max id" as predecessor; the verifier walks "min id first". For two rows A and B with the same `created_at`:
   - Trigger inserting B sees predecessor = MAX(A,B−1) — by id ordering, that's A if `A.id > B.id` was already inserted.
   - Verifier walking A then B expects B.this_hash = sha256(A.this_hash || …).

   Because the advisory lock (mig 082:24) serializes inserts, *only one row* exists when each trigger runs. So the trigger's "max id" lookup at insert time always returns the latest committed row — by *commit order*, not by id ordering. The verifier walking by `(created_at ASC, id ASC)` may then encounter the rows in a different order than they were committed.

   **Concrete failure case:** T1 commits row R1 with id=`AAA…`, then T2 commits row R2 with id=`000…` and same `created_at`. Trigger lookup at T2 returned R1 (the only row). R2.prev_hash = R1.this_hash. Verifier walks `(created_at ASC, id ASC)` and sees R2 first (id=`000` < `AAA`). It computes R2.this_hash with v_prev=NULL, gets a different value → flags R2 as broken.

2. **Per-microsecond collision risk**: Postgres `TIMESTAMPTZ` is microsecond resolution. `NOW()` returns the transaction start time (constant within a transaction), so two single-statement audit inserts from two separate `pool.query()` calls in the same microsecond would tie. With the advisory lock serializing them, this is more likely than less (the second waits, then both commit "around" the same wallclock instant).

**Severity rationale:** Critical because the audit chain is the system's tamper-evidence contract; false positives on a busy day make the verify function untrustworthy as a forensic tool — exactly the failure mode mig 080's commit message warned about ("denial-of-confidence attack").

**Fix:** add a strictly-monotonic insert-order column (BIGSERIAL `seq` or use `clock_timestamp()` for inserted_at + an FK to a sequence). Trigger picks predecessor by `seq DESC`; verifier walks by `seq ASC`. UUIDs as randomized PKs are fine for masking enumeration but fundamentally unfit as a chain-ordering key.

---

### C3 — `verify_audit_chain()` skips rows with `this_hash IS NULL` so any pre-mig-065 row silently disappears from verification

**File:** `apps/api/src/db/migrations/065_audit_log_hash_chain.sql:94-95`, also `075:83`:

```sql
IF r.this_hash IS NOT NULL AND r.this_hash <> v_expected THEN
  -- (mig 075 uses IS DISTINCT FROM, equivalent treatment)
```

The verifier flags a row only when `this_hash` is non-null and mismatched. Mig 065 added the column with no backfill, so every audit row from migrations 004–064 has `this_hash IS NULL`. The verifier walks past them silently and starts the chain at the first post-065 row.

But more importantly: **a deletion attack works**. An attacker with the `audit_cleaner` role (or with raw psql access via the migration runner's user) can `UPDATE audit_logs SET this_hash = NULL WHERE id = 'compromising-row-id'`. The immutable trigger from mig 031 prevents UPDATE for the api role — but `audit_cleaner` from mig 099 has SELECT + DELETE, no UPDATE explicit grant on audit_logs, and tables are append-only via the trigger that exempts `audit_cleaner` (031:25). So an `audit_cleaner` member can UPDATE → set `this_hash` to NULL → and verify_audit_chain() now passes.

Verify mig 031 trigger: `IF current_user = 'audit_cleaner' OR pg_has_role(current_user, 'audit_cleaner', 'MEMBER') THEN RETURN COALESCE(NEW, OLD);` — yes, `audit_cleaner` can UPDATE.

**Fix:** verify should treat any `this_hash IS NULL` post-mig-065 as a chain break. Cleanest: backfill once during mig 065 by computing the hash for every existing row (forward chain), then `ALTER TABLE audit_logs ALTER COLUMN this_hash SET NOT NULL`. Existing rows then can't be NULL'd.

---

## HIGH

### H1 — `audit_logs_immutable` trigger allows `audit_cleaner` to UPDATE audit rows; the role's intent was DELETE-only

**File:** `apps/api/src/db/migrations/031_audit_logs_immutable.sql:25`

```sql
IF current_user = 'audit_cleaner' OR pg_has_role(current_user, 'audit_cleaner', 'MEMBER') THEN
  RETURN COALESCE(NEW, OLD);
END IF;
```

The trigger fires on `BEFORE UPDATE OR DELETE`. The `audit_cleaner` exemption returns the row for both ops — UPDATE and DELETE. The migration comment says "Retention cleanup is the only legitimate DELETE path; it runs as that role." Intent is DELETE-only, but the implementation allows UPDATE too. This is the prerequisite for the deletion attack in C3.

**Fix:** scope the exemption by `TG_OP`:
```sql
IF TG_OP = 'DELETE' AND (current_user = 'audit_cleaner' OR pg_has_role(...)) THEN
  RETURN OLD;
END IF;
RAISE EXCEPTION ...;
```

---

### H2 — Pool config lacks `application_name` and `keepalives` knobs; long-lived advisory-lock holders are invisible to ops

**File:** `apps/api/src/db/index.ts:64-75`

The pool is configured with `max`, `idleTimeoutMillis`, `connectionTimeoutMillis`, and `statement_timeout`. No `application_name`, no `tcp_keepalives_idle/_interval/_count`, no SSL CA verification beyond the optional `DB_SSL_CA_FILE` path.

Consequences:
1. `pg_stat_activity` rows from the api show `application_name = ''` (empty), so an operator looking at PG locks can't tell which process holds the migration advisory lock (`MIGRATION_LOCK_KEY = 0x4D47524E`) or the audit-chain lock (`687638440097`) — they look identical to any other api connection.
2. With no TCP keepalives, a container that gets killed mid-transaction can leak a connection that holds an advisory lock for hours (until the OS TCP timeout, which on Linux defaults to ~2h).
3. Pool size is fixed at 20 (default) — no `min`. On a cold container, every request synchronously connects, and `connectionTimeoutMillis: 5000` means slow PG can produce 5s+ p95 spikes during deploys.

**Severity rationale:** High because the migration runner's session-scoped advisory lock (`pg_advisory_lock`, run-migration.ts:164) **is** released on connection drop — that's correct — but only after the OS notices the disconnect. With no keepalive, operators have a long window where a crashed runner blocks every other replica's boot.

**Fix:** add `application_name: 'havenkeep-api'` (or read from `process.env.HOSTNAME`), `keepAlive: true`, `keepAliveInitialDelayMillis: 30_000`. Document in a registry comment alongside `MIGRATION_LOCK_KEY` what other process names use the pool.

---

### H3 — `withMigrationLock` releases on connection return but doesn't call `pg_advisory_unlock` on `pool.end()` after success

**File:** `apps/api/src/db/migrations/run-migration.ts:157-177, 220-222`

```ts
async function withMigrationLock<T>(fn: () => Promise<T>): Promise<T> {
  const lockClient = await pool.connect();
  try {
    await lockClient.query(`SELECT pg_advisory_lock($1)`, [MIGRATION_LOCK_KEY]);
    try {
      return await fn();
    } finally {
      await lockClient.query(`SELECT pg_advisory_unlock($1)`, [MIGRATION_LOCK_KEY]).catch(() => {});
    }
  } finally {
    lockClient.release();
  }
}
```

The unlock is best-effort and within the inner `finally`, so it always runs. Then `lockClient.release()` returns the client to the pool. After `main()` succeeds, `pool.end()` runs (line 221), draining the pool. The advisory lock is session-scoped, so it's released either on explicit `pg_advisory_unlock` (here) or when the session ends (pool drain). Good.

But there's a subtle issue: between `lockClient.release()` (line 175) and `pool.end()` (line 221), the connection lives in the idle pool. If the pool is recycled (idle timeout) before drain, the connection closes naturally and the lock is gone. If a *different* operation grabs that client first (impossible in this script — only one main(), but conceivable if the runner is ever embedded), the new operation inherits a session that just held the lock. Cosmetically harmless given current usage, but the design is fragile.

The bigger concern: the `pg_advisory_lock` call is wrapped to no timeout (`SELECT pg_advisory_lock($1)`) and uses the blocking variant. If a partial migration crashes the *first* runner mid-DDL **and** that runner's connection didn't fully die (e.g., zombie process), the second runner blocks forever on the lock.

**Fix:** use `pg_try_advisory_lock` with retry/backoff; log every 30s the runner is waiting, and surface a hard error after 10 minutes.

---

### H4 — `decryptToken` walks all candidate keys even on real auth failures; no observability for "wrong key" vs "tampered ciphertext"

**File:** `apps/api/src/utils/oauth-encryption.ts:80-102`

```ts
for (const key of candidates) {
  try {
    const decipher = crypto.createDecipheriv(ALGO, key, iv);
    decipher.setAuthTag(tag);
    const dec = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
    return dec.toString('utf8');
  } catch (err) {
    lastErr = err;
  }
}
throw lastErr ?? new Error('OAuth token decryption failed');
```

Three concerns:
1. **No telemetry on legacy-key hits.** When a row decrypts under a legacy key, the function silently succeeds. Operators have no signal of "how many rows are still on the old key" — so the "rotate key" runbook can't tell when it's safe to drop a legacy entry. This is the *only* way to know rotation is done.
2. **`lastErr` leaks Node's `gcm: Unsupported state or unable to authenticate data`** to the caller via `throw`. This is descriptive enough that anyone catching it can distinguish "wrong key" from "missing config" — but the error chain is only useful for the last-tried key. If primary fails, legacy[0] fails, legacy[1] fails — you only see legacy[1]'s error, which doesn't tell you that the primary failed too.
3. **Timing channel.** Each candidate key tries the full `createDecipheriv → setAuthTag → final()` cycle. GCM authentication failure happens at `final()` for non-auth-tag-mismatch errors but at `setAuthTag()` time only for length issues. A small timing measurement could distinguish "primary key tagged-mismatch" from "primary key wasn't tried" — useful for an attacker who has access to the wire and is trying to fingerprint key rotation. Not directly exploitable, but worth noting.

**Fix:**
- Add a `decryptionsByKeyIndex` counter (gauge) that the metrics endpoint exposes — `havenkeep_oauth_decrypt_legacy_total` lets ops see when legacy=0 and the legacy entry can be dropped.
- Log `which key index succeeded` at debug level on success; log `tried N keys, all failed` at warn on full failure.

---

### H5 — `audit_logs_assign_hash()` payload includes `created_at::text` which Postgres formats with TZ-dependent precision

**File:** `apps/api/src/db/migrations/082_audit_chain_advisory_lock_fix_casts.sql:50`

```sql
COALESCE(NEW.created_at::text, '')
```

`TIMESTAMPTZ::text` formats with the session's `TimeZone` GUC — `2026-05-10 12:34:56.789012+00` vs `2026-05-10 08:34:56.789012-04` for the same instant. The verifier (mig 075:81) reads `r.created_at::text` under whatever TimeZone GUC the verifier session has set.

If the api-pool sessions have one TZ (`UTC`, the typical default) and an admin running `verify_audit_chain()` from psql has another (`America/New_York`), the verifier produces a different string than the trigger did → every chain row appears broken.

**Why this hasn't blown up:** the api server connections inherit the cluster default TimeZone (usually `UTC` on managed PG, including DigitalOcean), and the cron's `cleanup_old_audit_logs` runs via the same connection pool. But operator triage from psql is a likely scenario.

**Fix:** force TZ in the format. Either:
```sql
COALESCE(to_char(NEW.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US'), '')
```
or store/hash the underlying epoch microseconds as bigint:
```sql
COALESCE(EXTRACT(EPOCH FROM NEW.created_at)::bigint::text, '')
```

Either way, both writer and verifier must agree.

---

### H6 — `cleanup_old_audit_logs()` is owned by `audit_cleaner` per mig 099 but `audit_cleaner` is `NOLOGIN` per mig 031

**Files:** `apps/api/src/db/migrations/031_audit_logs_immutable.sql:13-16`, `099_cleanup_audit_logs_owner_audit_cleaner.sql:35`

Mig 031 creates `CREATE ROLE audit_cleaner NOLOGIN;`. Mig 099 reassigns the function to that role and runs `SECURITY DEFINER`. SECURITY DEFINER executes the function as the *owner* (audit_cleaner). NOLOGIN means audit_cleaner can't log in directly, which is fine for SECURITY DEFINER — but the owner still has to *exist* and be valid for permission checks. Postgres allows SECURITY DEFINER under a NOLOGIN role; this is correct.

The actual concern: who calls the function? The api role calls `cleanup_old_audit_logs()` — that requires `EXECUTE` on the function. After mig 099's `ALTER FUNCTION ... OWNER TO audit_cleaner`, the function's default `EXECUTE` grant chain may shift (existing GRANTs are preserved but defaults to PUBLIC are stripped on owner change in some PG versions).

**Verification needed:** confirm that the api user still has `EXECUTE` on `cleanup_old_audit_logs()` after mig 099. The migration doesn't `GRANT EXECUTE ON FUNCTION cleanup_old_audit_logs() TO havenkeep_api` — it only does `REVOKE ALL FROM PUBLIC` (in mig 031:61). If 099's reassignment dropped a previously-implicit EXECUTE, the cron's call would 42501.

**Fix:** add `GRANT EXECUTE ON FUNCTION cleanup_old_audit_logs() TO {api_role}` to mig 099 explicitly. The migration runner connects as the api role; this is straightforward to verify in staging by running the cron manually.

---

### H7 — `request_idempotency` cleanup uses `expires_at < NOW()` index range scan but no upper bound; daily cron eventually scans 24h worth

**Files:**
- `apps/api/src/db/migrations/078_request_idempotency.sql:28-29` (index)
- `apps/api/src/middleware/idempotency.ts:151-156`

```ts
DELETE FROM request_idempotency WHERE expires_at < NOW()
```

Index `idx_request_idempotency_expires` is on `expires_at` (no predicate). The DELETE scans the index range up to NOW(), then deletes matched rows. With a 24h TTL and steady traffic, the table holds at most ~1 day of replays — bounded growth is fine. But the daily cleanup deletes the entire trailing day in one SQL statement, holding row locks on every matched row. Under a sustained 24h replay-flood, the table could carry millions of rows; the DELETE then blocks for minutes.

Bigger concern: the cleanup is run by `index.ts:249` (cron) but there's no batching or `LIMIT` on the DELETE, and no `ANALYZE` after.

**Severity rationale:** High because under a DoS-style replay attempt against any idempotent endpoint, the table can fill before the next cron — the server would still serve correct responses but the pool would clog on the cleanup transaction.

**Fix:** chunk the DELETE: `DELETE … WHERE id IN (SELECT id FROM request_idempotency WHERE expires_at < NOW() LIMIT 10000)` in a loop. Also: add a partial unique index on `(user_id, route_key, expires_at)` to make the existing-row lookup at insert time O(1) rather than indexing on the PK alone.

---

## MEDIUM

### M1 — Audit-chain trigger reads `NEW.created_at::text` but the column is NOT NULL with DEFAULT NOW(); the COALESCE fallback is dead code

**File:** `apps/api/src/db/migrations/082_audit_chain_advisory_lock_fix_casts.sql:50`

```sql
COALESCE(NEW.created_at::text, '')
```

`audit_logs.created_at` is `TIMESTAMPTZ NOT NULL DEFAULT NOW()` (mig 004:108). PostgreSQL applies column defaults *before* BEFORE INSERT triggers fire. So `NEW.created_at` is always non-null at trigger time — the COALESCE branch is unreachable. The empty-string fallback exists for symmetry with the verifier, but the verifier reads from already-inserted rows where `created_at` is always set.

Cosmetic but: dead-code in a tamper-evidence trigger is exactly the kind of "looks defensive but isn't" pattern that hides bugs. CLAUDE.md Rule 1 ("never leave tech debt"). Either drop the COALESCE on `created_at` or wire it consistently.

---

### M2 — `partner_gifts.chargeback_status` regex CHECK accepts arbitrary 64-char snake_case strings; no length floor

**File:** `apps/api/src/db/migrations/089_chargeback_status_regex.sql:21`

```sql
CHECK (chargeback_status IS NULL OR chargeback_status ~ '^[a-z][a-z0-9_]{0,63}$')
```

Allows `'a'` (1 char) through any 64-char snake_case string. Stripe's defined statuses are all 5+ chars (`won`, `lost`, `warning_*`, `under_review`). The regex bound is correct in spirit (permissive to accept future Stripe values) but allows nonsense like `'a'` or `'x_'` to land. The auditor's intent (see migration comment 6-12) was "accept future Stripe additions"; a length floor of 3 would still meet that goal while rejecting obvious garbage.

**Severity:** Medium — defense-in-depth concern, not a current exploit.

**Fix:** `'^[a-z][a-z0-9_]{2,63}$'` (4+ chars total).

---

### M3 — Mig 062's `savings_feed_anonymize_on_user_delete` BEFORE DELETE trigger fires before all FK SET NULL paths complete

**File:** `apps/api/src/db/migrations/062_maintenance_dedup_and_savings_feed_anonymize.sql:60-73`

The trigger:
```sql
BEFORE DELETE ON users
FOR EACH ROW EXECUTE FUNCTION savings_feed_anonymize_on_user_delete();
```

…runs `UPDATE savings_feed SET user_city=NULL, user_state=NULL WHERE user_id = OLD.id`. Then the FK CASCADE/SET NULL fires (user_id → SET NULL).

If the user has *no* savings_feed rows, this is a no-op. If they have many (popular user), the BEFORE-trigger updates them, then the SET NULL kicks in and updates them *again* (now setting user_id to NULL on rows that were already touched). Two writes per row. With mig 094-style index hygiene this is fine; with a multi-thousand-row history it doubles the lock window for the user delete.

**Severity:** Medium — performance + redundancy, not correctness.

**Fix:** combine into one path: drop the trigger and have the application-level purge service do `UPDATE savings_feed SET user_city=NULL, user_state=NULL, user_id=NULL WHERE user_id = $1` before `DELETE FROM users`. Simpler and atomic in the same transaction.

---

### M4 — Mig 045's `schema_version` row is inserted from a presence-of-3-tables proxy, not from "schema.sql actually completed"

**File:** `apps/api/src/db/migrations/045_schema_version.sql:26-36`

```sql
IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'users')
   AND EXISTS (SELECT 1 FROM pg_class WHERE relname = 'items')
   AND EXISTS (SELECT 1 FROM pg_class WHERE relname = 'partners')
THEN
  INSERT INTO schema_version (phase, pg_version) VALUES ('base', ...) ON CONFLICT DO NOTHING;
END IF;
```

The first three tables in schema.sql are `users`, `homes`, `items` — `partners` doesn't exist in schema.sql at all (it's first introduced in migration 002:151). So in a *fresh* bootstrap from current schema.sql, only `users` and `items` exist after schema.sql; `partners` only exists after mig 002 ran.

This means: when the runner replays schema.sql against a fresh DB, then runs mig 002 (which creates partners), then runs mig 045 — at mig 045 time, all three tables exist and the row is inserted. Good. But if any future hand-restored DB has only schema.sql + mig 045 (skipping mig 002), the `partners` test fails and the row is never inserted — the runner re-replays schema.sql forever. Edge case but possible.

**Severity:** Medium because the proxy isn't actually checking what it claims (its own existence is the only true signal that mig 045 ran). The ensure-base check at run-migration.ts:62-76 reads "any row with phase='base' means base done" — but base is determined by schema.sql alone, while mig 045's row insertion depends on a downstream-migration table. Conflated.

**Fix:** insert `('base', …)` unconditionally in mig 045, since its own execution proves schema.sql + 001..044 have all run successfully. The 3-table guard adds nothing.

---

### M5 — The audit-trigger advisory lock key (687638440097) is not registered in any central registry; each new lock-using site documents itself ad hoc

**File:** `apps/api/src/db/migrations/run-migration.ts:142-155` (registry comment), `082_audit_chain_advisory_lock_fix_casts.sql:24` (uses `687638440097`), `services/account-purge.service.ts` (`0xa00d_4a13`), and the cap-refresh-tokens lock referenced in the runner comment.

The runner comment lists "audit-chain advisory lock (mig 080: 687638440097), the account-purge lock (account-purge.service.ts: 0xa00d_4a13), and the cap-refresh-tokens lock." But there's no centralized constant file. Adding a new lock requires:
1. Picking a number not in use anywhere.
2. Manually grepping for it.
3. Documenting it.

This invites collision — two future authors picking 0xA00D... values that overlap.

**Fix:** create `apps/api/src/db/advisory-locks.ts`:
```ts
export const ADVISORY_LOCKS = {
  MIGRATION_RUNNER: 0x4D47524E,
  AUDIT_CHAIN: 687638440097n,
  ACCOUNT_PURGE: 0xa00d_4a13,
  REFRESH_TOKEN_CAP: ...,
} as const;
```
…and import from it everywhere. SQL-only files reference the value by comment (`-- advisory-locks.ts:AUDIT_CHAIN`). Worth doing now before a fourth lock joins.

---

### M6 — Mig 037's partial unique on `LOWER(email) WHERE status='subscribed'` doesn't survive case-canonicalization mismatch

**File:** `apps/api/src/db/migrations/037_newsletter_double_optin.sql:43-45`

```sql
CREATE UNIQUE INDEX idx_newsletter_subscribed_email
  ON newsletter_subscribers(LOWER(email))
  WHERE status = 'subscribed';
```

Indexes `LOWER(email)` for the `status='subscribed'` partition. Good for "no duplicate confirmed subscribers" — but the `email` column itself is `VARCHAR(255)` with no CITEXT/CHECK enforcing lowercase. A row inserted with `Foo@Bar.com` and another with `foo@bar.com` collide at index time only — the application has to use `LOWER(email)` consistently or `WHERE email = $1` lookups will miss the row.

Verified by the index definition: this is the *correct* shape if the application always queries with `LOWER(email)`. But mig 070 (line 144-148) defines a regex CHECK on `contact_submissions.email` using case-insensitive `~*` matching — different column, different table, but indicates the codebase has mixed conventions.

**Severity:** Medium; depends on whether route handlers always call `LOWER()`. Audit-of-routes territory.

---

### M7 — `webhook_events_high_water` PRIMARY KEY (source, subject_id) but no FK to `webhook_events` — orphan rows possible if events are pruned

**File:** `apps/api/src/db/migrations/050_webhook_ordering_and_dispute.sql:36-43`

The high-water table's purpose is to gate replay ordering. There's no FK to `webhook_events.event_id`, so if the daily webhook cleanup removes a row referenced by `last_event_id`, the high-water row keeps that orphan id forever. Not strictly a bug — the high-water row is doing its job (rejecting older events) — but it's a data-quality blemish.

**Fix:** either add a `last_event_id` length cap and accept orphans (current behavior), or add `FOREIGN KEY (last_event_id) REFERENCES webhook_events(event_id) ON DELETE SET NULL` once `webhook_events.event_id` has its own UNIQUE constraint.

---

### M8 — Mig 097 leaves `BEFORE UPDATE` blocked on `warranty_claim_state_history` but uses the same shared function `warranty_claim_state_history_immutable()` that mig 060 created with a hard `RAISE EXCEPTION`

**Files:** `apps/api/src/db/migrations/060_warranty_claim_state_machine.sql:56-66`, `097_warranty_claim_state_history_allow_cascade_delete.sql:17-21`

Mig 060 created the trigger with `BEFORE UPDATE OR DELETE`. Mig 097 dropped+recreated it as `BEFORE UPDATE`. The function body still says `RAISE EXCEPTION 'warranty_claim_state_history is append-only'` — accurate for UPDATE, misleading if anyone were to re-add DELETE. Not currently a bug.

**Severity:** Medium (cosmetic risk for next maintainer).

**Fix:** rename function to `..._reject_update()` or add a `TG_OP` check + tailored message:
```sql
RAISE EXCEPTION 'warranty_claim_state_history is append-only (op=%)', TG_OP;
```

---

### M9 — `documents.file_size` was widened to BIGINT (mig 070:36) but mig 093's CHECK uses raw `>= 0` without a max upper bound

**File:** `apps/api/src/db/migrations/093_documents_file_size_check.sql:14-15`

```sql
CHECK (file_size >= 0)
```

BIGINT max is 2^63-1 (~9.2 EB). The Joi validator caps inbound at 10MB. A buggy multer middleware bypassing Joi could land any value up to BIGINT max. The CHECK only enforces non-negativity. If we trust the application, fine; but the table is defense-in-depth. A `<= 5_368_709_120` (5 GB, generous ceiling) would catch obvious bugs.

**Severity:** Medium — depth-in-defense concern.

---

### M10 — `cleanup_old_audit_logs()` deletes `info` rows older than 1 year and `warning/error/critical` older than 3 years, but doesn't account for the audit chain — deleting a row breaks every subsequent verification

**File:** `apps/api/src/db/migrations/099_cleanup_audit_logs_owner_audit_cleaner.sql:24-32`

```sql
DELETE FROM audit_logs WHERE created_at < NOW() - INTERVAL '1 year' AND severity = 'info';
DELETE FROM audit_logs WHERE created_at < NOW() - INTERVAL '3 years' AND severity IN (...);
```

Removing any row from a hash chain breaks every row after it: row N+1's `prev_hash` was computed against row N's `this_hash`; if N is gone, recomputation now starts from N-1's `this_hash` — but row N+1 was inserted with the old chain head, so its stored `this_hash` no longer matches.

Net effect: the first call to `cleanup_old_audit_logs()` after the chain is established will silently break the chain. `verify_audit_chain()` will report every row younger than the deletion as broken. There's no "rebase" step.

**Severity:** Medium — no current production impact (the chain shipped 2026-04-25; cleanup deletes rows >1 year, so first triggering is ~2027-04-25). But this is a time-bomb: the cleanup feature contradicts the chain feature.

**Fix:** the chain has to support tombstoning — when a row is deleted by cleanup, replace its content with `{deleted, original_hash}` so the verifier still walks correctly. Or: split audit_logs into `audit_logs_active` (chained, append-only-no-delete) and `audit_logs_archive` (snapshotted with their last `this_hash` preserved as a chain anchor). Either way needs a design pass.

---

### M11 — The audit-chain payload includes `ip_address::text` which Postgres formats with subnet notation; `'192.0.2.1'::inet::text = '192.0.2.1'` but `'192.0.2.1/24'::inet::text = '192.0.2.1/24'` — chain hash is sensitive to a column type detail

**File:** `apps/api/src/db/migrations/082_audit_chain_advisory_lock_fix_casts.sql:44`

```sql
COALESCE(NEW.ip_address::text, '')
```

`audit_logs.ip_address` is `INET` (mig 004:98). INET supports a CIDR mask; the application currently writes `req.ip` which is a bare IP. `text` cast preserves the mask if present.

If a future change writes IPs *with* mask (e.g., for partner-IP-allowlist diagnostics), the hash format changes, and any cross-version chain compatibility breaks.

**Severity:** Medium — forward-compatibility footgun.

**Fix:** use `host(NEW.ip_address)` which always returns the bare IP without mask. Or document that `ip_address` is always a /32.

---

### M12 — `partner_commissions` partial index on (created_at) WHERE status='pending' is correct for the auto-approve sweep but doesn't include `partner_id` — the cron then filters per-partner inside the index range

**File:** `apps/api/src/db/migrations/095_partner_commissions_payout_support.sql:19-21`

```sql
CREATE INDEX IF NOT EXISTS idx_partner_commissions_pending_age
  ON partner_commissions (created_at)
  WHERE status = 'pending';
```

The auto-approve cron queries `WHERE status='pending' AND created_at < NOW() - INTERVAL '30 days'`. The partial index nails the predicate; the range scan returns rows in date order. If the cron also filters per-partner (it shouldn't for auto-approve, but the dashboard's "pending older than 30 days for partner X" view would), the index has to do a heap fetch per row to check `partner_id`.

**Severity:** Medium — depends on actual query patterns; the migration's stated cron is fine as-is.

---

## LOW

### L1 — `update_updated_at_column()` is redefined in mig 001, schema.sql:225, and mig 040:157; three sources of truth

The function body is consistent across all three (`NEW.updated_at = NOW(); RETURN NEW`), but the *flags* differ:
- Mig 001 (line 1-9): no `SECURITY INVOKER`, no `SET search_path`.
- schema.sql:225-235: `SECURITY INVOKER`, `SET search_path = pg_catalog, public`.
- Mig 040:156-167: same as schema.sql.

Re-running the migrations from scratch ends up with the schema.sql / mig 040 version (last writer wins via CREATE OR REPLACE). On an existing DB that pre-dates mig 040, the un-pinned version from mig 001 may persist if the schema.sql-DO-block guards prevented re-creation. This is the kind of drift mig 040 was meant to clean up, and it does — eventually — but only if mig 040 actually ran.

**Severity:** Low — current state is consistent on any DB that's run mig 040.

---

### L2 — `idle_in_transaction_session_timeout` is set via string interpolation (`SET idle_in_transaction_session_timeout = ${IDLE_IN_TX_MS}`)

**File:** `apps/api/src/db/index.ts:83`

```ts
await client.query(`SET idle_in_transaction_session_timeout = ${IDLE_IN_TX_MS}`);
```

`IDLE_IN_TX_MS` comes from `intFromEnv` which validates `Number.isFinite(n) && n >= 0`, so no injection risk. But the pattern is brittle — if someone "improves" `intFromEnv` to accept strings, the SET becomes injection-prone. SETs do parameterize (`SET … TO $1` doesn't work; you have to use `SET LOCAL` or `SET session_authorization` properly). For this specific knob, `client.query('SET … = $1', [IDLE_IN_TX_MS])` won't work due to PG's parser; the safer form is `SET … TO ${parsedAndChecked}` which is what we have.

**Severity:** Low — current code is safe. Note for the next maintainer to keep the type guard.

---

### L3 — `documents` table has `idx_documents_item_id` and `idx_documents_user_id` (schema.sql:171-172) plus `idx_documents_user_item` from mig 005 (line 21) — `(user_id, item_id)` covers `(user_id)` so the bare index is redundant

After mig 094 dropped the redundant newsletter index, this `(user_id)` survivor is the next candidate. Negligible storage impact; pure hygiene.

**Severity:** Low — index hygiene follow-up.

---

### L4 — `email_scans.error_message` and `email_scans.completion_message` (mig 088) — no CHECK enforcing mutual exclusivity

**File:** `apps/api/src/db/migrations/088_email_scans_completion_message.sql`

The migration adds `completion_message` to use only on success; `error_message` is for failures. There's no CHECK like:
```sql
CHECK (error_message IS NULL OR completion_message IS NULL)
```

A future writer could populate both. Defense-in-depth.

**Severity:** Low.

---

### L5 — `apple_sign_in_nonces` has no FK to users (it's keyed only by nonce hash)

**File:** `apps/api/src/db/migrations/077_apple_sign_in_nonces.sql:18-21`

The table is intentionally not user-scoped (the nonce comes pre-auth, before the user is known). Cleanup runs by `expires_at`. No issue; documenting for completeness.

---

### L6 — `verify_audit_chain()` is `STABLE` but does heap reads of every row; on a large table this is O(N) and times out under default `statement_timeout=30s`

**File:** `apps/api/src/db/migrations/075_audit_hash_chain_enum_cast.sql:55-92`

The function is marked `STABLE` (correct — it doesn't modify data) but iterates the entire `audit_logs` table. With ~10M rows, the function runs for tens of seconds; with the api pool's `statement_timeout = 30000`, a `SELECT * FROM verify_audit_chain()` from the api crashes mid-walk.

Operators running this from psql would have a longer timeout. Not currently exposed as an API endpoint, so the practical impact is low.

**Severity:** Low — operational detail. If the function ever gets a route, add a `LIMIT/OFFSET` parameter.

---

## VERIFIED CORRECT

- **V1 — Mig 098 (`ALTER TYPE warranty_purchase_status ADD VALUE IF NOT EXISTS 'cancelling'`)**: works inside a transaction on PG12+, value is not referenced in the same file. Same pattern as mig 030a. `apps/api/src/db/migrations/098_warranty_purchase_status_add_cancelling.sql:18`.
- **V2 — Mig 087 (`ALTER SEQUENCE/TABLE … TYPE bigint`)**: `webhook_events.id INT4 → BIGINT` is a metadata-only change in PG (sequence already returns int8 internally; the column type widening is no rewrite if all values fit, which they do). `apps/api/src/db/migrations/087_webhook_events_bigint.sql:13-14`.
- **V3 — Mig 050 webhook_event_high_water uniqueness**: PRIMARY KEY (source, subject_id) is correct — one ordering anchor per stream. `apps/api/src/db/migrations/050_webhook_ordering_and_dispute.sql:36-43`.
- **V4 — Mig 084 user_mfa schema**: `secret_iv VARCHAR(32)` (line 38) is wider than the CHAR(24) in `user_oauth_integrations` (mig 038) — both decode correctly via `oauth-encryption.ts decryptToken` because `Buffer.from(b64.trim(), 'base64')` handles either. The mfa columns don't space-pad (VARCHAR), so trim is a no-op; oauth ones do (CHAR), so trim is needed. Both work.
- **V5 — Mig 092 partners is_active/status invariant**: `CHECK ((is_active = TRUE) = (status = 'active'))` is a clean equivalence — covers both directions, allows is_active=FALSE+status='pending' (correct for unapproved) and is_active=FALSE+status='rejected' (correct). `apps/api/src/db/migrations/092_partners_is_active_status_invariant.sql:23`.
- **V6 — Mig 088 email_scans.completion_message** is added without backfill, which is correct: error_message holding success notes from old rows can stay as-is (the alert query now correctly filters).
- **V7 — `request_idempotency` ON CONFLICT DO NOTHING semantics**: `apps/api/src/middleware/idempotency.ts:130`. The middleware reads first; only the *miss* path inserts. Race: two concurrent requests with same key both miss, both compute the response, both INSERT, the second's INSERT is no-op due to `ON CONFLICT (user_id, route_key, idempotency_key) DO NOTHING`. The persisted response is whichever inserted first — both callers see their own (correctly-computed) response from the route handler. Subsequent replays see the persisted one. Mostly correct, with one nit: a near-simultaneous double-send may produce two route-handler executions, which the comment at idempotency.ts:25-27 acknowledges and points to route-level uniqueness as the backstop.
- **V8 — Mig 030a/030b split**: the deliberate two-file pattern for `ALTER TYPE … ADD VALUE` followed by a CHECK referencing the new value is correct. PG requires the value commit before reference. Migrations are applied one file at a time via the runner's per-file BEGIN/COMMIT. `apps/api/src/db/migrations/030a_commission_reversed_enum.sql:1-19` documents the rationale.
- **V9 — Mig 100's GRANT SELECT to audit_cleaner**: required because PG evaluates the WHERE clause of a DELETE under SELECT privilege. Necessary follow-up to mig 099's restructure. `apps/api/src/db/migrations/100_audit_cleaner_select_grant.sql`.
- **V10 — `oauth-encryption.ts` IV uniqueness + GCM auth**: 12-byte IVs from `crypto.randomBytes` (line 68) are unique with overwhelming probability for any practical volume; GCM auth tag is checked at `decipher.final()`. Encrypt path is correct.
- **V11 — Mig 028 RESTRICT/SET NULL strategy**: warranty_purchases/claims `user_id ON DELETE RESTRICT` was deliberate (paid records survive user delete), then mig 083 changed to SET NULL with denormalized email — that's a real fix (RESTRICT was blocking GDPR purges), executed correctly. `apps/api/src/db/migrations/083_warranty_purge_anonymization.sql`.
- **V12 — Schema migration tracking via SHA256**: the runner stores SHA256 of every applied file (run-migration.ts:33-46) and warns on drift (line 199-204). Doesn't auto-rerun, surfaces the drift correctly.

---

## OUT OF SCOPE

- Route logic (audit chain *callers*, route handlers' use of `idempotency` middleware, oauth-encryption call sites in services). Other agents own.
- Mobile, dashboard, marketing, infra/Caddy, deploy scripts.
- Stripe webhook handler logic (only the `webhook_events` table schema is in scope).
- Application-level rate limiting and CSRF (covered by other audit runs).

---

## Summary of severities

| Severity | Count |
|----------|-------|
| Critical | 3 |
| High     | 7 |
| Medium   | 12 |
| Low      | 6 |
| Verified-correct | 12 |

**Top recommended fixes (in order):**
1. **C1** — fix `fileNeedsAutoCommit` regex to scan line-by-line. Trivially small change, prevents future foot-guns.
2. **C2** — add a monotonic sequence column to `audit_logs` and use it for chain ordering instead of `(created_at, id)`.
3. **C3 / H1** — backfill `audit_logs.this_hash` for pre-mig-065 rows + `NOT NULL` it; scope `audit_logs_immutable` exemption to DELETE only.
4. **M10** — design the audit-chain retention story before `cleanup_old_audit_logs` actually starts deleting (timeline: ~2027).
5. **H2** — set `application_name` and TCP keepalives on the pool; document advisory-lock keys in a single TS file (M5).
6. **H4** — add legacy-key-hit metric so OAuth key rotation has a definitive "all rows migrated" signal.
