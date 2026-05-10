# Audit Run 03 (v2) — Database + Crypto Deep Dive

**Scope:** every line of `apps/api/src/db/schema.sql`, all 91 migration files (`001`..`100` with gaps), `db/migrations/run-migration.ts`, `db/index.ts`, `utils/oauth-encryption.ts`, `utils/password.ts`, `utils/token-hash.ts`, `services/mfa.service.ts`, the audit-trigger / verifier / cleanup function bodies, the `request_idempotency` middleware, and `services/account-purge.service.ts` (the FK-aware caller).

**Builds on:** `docs/audit-runs/03-database-migrations.md` (v1). Findings v1-C1..C3, v1-H1..H7, v1-M1..M12, v1-L1..L6 are not duplicated here unless extended.

**Date:** 2026-05-10

---

## CRITICAL

### C1 — `audit_logs.this_hash` is nullable + unindexed; v1-C3's "deletion attack" generalizes to anyone with `audit_cleaner` *or* anyone with the runner's privileges (anyone able to SET ROLE)

**Files:**
- `apps/api/src/db/migrations/065_audit_log_hash_chain.sql:15-17` (column add, nullable)
- `apps/api/src/db/migrations/075_audit_hash_chain_enum_cast.sql:83` (verifier `IS DISTINCT FROM`)
- `apps/api/src/db/migrations/099_cleanup_audit_logs_owner_audit_cleaner.sql:35` (`OWNER TO audit_cleaner`)

```sql
-- mig 065:15-17
ALTER TABLE audit_logs
  ADD COLUMN IF NOT EXISTS prev_hash CHAR(64),
  ADD COLUMN IF NOT EXISTS this_hash CHAR(64);
```

```sql
-- mig 075:83 (verifier inner check)
IF r.this_hash IS DISTINCT FROM v_expected THEN
  broken_at := r.created_at;
  broken_id := r.id;
  RETURN NEXT;
END IF;
```

`IS DISTINCT FROM` treats `NULL` and a non-null hash as different — so v1-C3's claim that null'd rows "silently disappear" is **wrong** for mig 075's verifier; mig 075 actually flags NULL rows correctly (NULL `IS DISTINCT FROM 'abc...'` → TRUE → reported). However, mig 075's commit message advertises this as a fix relative to mig 065 (which used `IS NOT NULL AND <>` — silent skip on NULL).

The remaining critical gap is the *attack surface*: `audit_cleaner` was reassigned ownership of `cleanup_old_audit_logs` (mig 099:35) and granted SELECT+DELETE on `audit_logs` (mig 099:39, mig 100:15). Combined with mig 031's trigger exemption (`IF current_user = 'audit_cleaner'... RETURN COALESCE(NEW, OLD)`), an attacker who:

1. Discovers the API role can `SET ROLE audit_cleaner` (the API role is the function-creator user; in PG an owner can `SET ROLE` to any role they're `INHERIT`-membered into, AND PG superusers can SET ROLE freely — and on a DigitalOcean managed PG cluster the API user is typically created by a superuser script that may have implicitly granted it via ALTER ROLE or by being the owner of audit_cleaner), OR
2. Compromises the cron host and inherits `cleanup_old_audit_logs()`'s privileges via the SECURITY DEFINER chain,

…can issue `UPDATE audit_logs SET this_hash = NULL, prev_hash = NULL WHERE id IN (...)` (mig 031 exempts `audit_cleaner` for **both** UPDATE and DELETE — TG_OP not gated). The verifier flags those rows as broken — but a clever attacker UPDATEs the row content to *match* a recomputed hash they themselves chose for an alternate timeline.

**Why v1-C3 didn't catch the full picture:** v1 noted that mig 075's verifier flags NULL rows correctly, but didn't note that **the verifier never `RAISES` — it just returns the broken set**. There is **no operational alarm** wired to `verify_audit_chain()` — `apps/api/src/services/audit.service.ts:625-627` exposes it only via an admin diagnostic endpoint. There is no cron, no alert, no metric that fires when the chain breaks. If audit_cleaner forges a chain (recomputing `this_hash` to match an attacker-chosen payload), it's only discovered when an admin manually clicks "verify chain."

**Severity rationale:** Critical because (a) the immutability claim is the system's tamper-evidence contract, (b) the verifier is offline-only, and (c) the trigger exemption applies to UPDATE not just DELETE.

**Fix:** mandatory bundle:
1. `ALTER TABLE audit_logs ALTER COLUMN this_hash SET NOT NULL` after a one-time backfill (compute the chain forward over all pre-mig-065 rows).
2. Mig 031 trigger `IF TG_OP = 'DELETE' AND (current_user = 'audit_cleaner' ...)` — gate the exemption to DELETE only.
3. Wire `verify_audit_chain()` into the existing daily cron in `index.ts:249` — surface broken-count as a Loki log + a counter that pages on `>0`.

---

### C2 — `audit_logs_assign_hash()` reads predecessor with `ORDER BY created_at DESC, id DESC LIMIT 1` and **dropped the `FOR SHARE` lock hint** in mig 080→082; the advisory lock is the only thing holding the chain together

**Files:**
- `apps/api/src/db/migrations/065_audit_log_hash_chain.sql:32-34` (original, no lock hint, but no advisory lock either)
- `apps/api/src/db/migrations/075_audit_hash_chain_enum_cast.sql:19-23` (added `FOR SHARE`)
- `apps/api/src/db/migrations/080_audit_chain_advisory_lock.sql:29-32` (advisory lock added; `FOR SHARE` **silently dropped**)
- `apps/api/src/db/migrations/082_audit_chain_advisory_lock_fix_casts.sql:26-29` (lock kept; `FOR SHARE` not restored)

```sql
-- mig 075:19-23 (had FOR SHARE)
SELECT this_hash INTO v_prev
  FROM audit_logs
 ORDER BY created_at DESC, id DESC
 LIMIT 1
 FOR SHARE;

-- mig 080:29-32 (and mig 082:26-29 — same body)
SELECT this_hash INTO v_prev
  FROM audit_logs
  ORDER BY created_at DESC, id DESC
  LIMIT 1;
-- ↑ no FOR SHARE
```

The `pg_advisory_xact_lock(687638440097)` *is* sufficient on its own to serialize concurrent BEFORE-INSERT triggers, so dropping FOR SHARE is *technically* fine. But:

1. The SELECT now reads from the **MVCC snapshot of the calling transaction**, not from a row-locked predecessor. An auto-commit transaction's snapshot is taken at the SELECT itself, so it sees the latest committed row — fine. But if a long-running outer transaction did some work (e.g. issued an INSERT into `users`, then a service call that triggers an audit insert), the audit-insert trigger fires inside that outer tx — and its snapshot is the outer tx's snapshot, taken at the outer tx's start. Any audit row committed by *another* tx after the outer tx's snapshot is invisible. Result: the trigger reads a stale predecessor.

2. The advisory lock serializes the trigger bodies, but not the snapshots they're reading from. Two outer transactions A and B both do work + audit insert. A's snapshot is at T0, B's is at T1 (>T0). A's audit insert commits row R_A at T2. B's audit-insert trigger then runs (waiting for the advisory lock), reads predecessor — but B's tx snapshot is from T1 < T2, so it doesn't see R_A. B chains off whatever predecessor existed at T1 (could be NULL or an earlier row) → forked chain.

**Concrete failure:** two HTTP handlers, both started inside long-running BEGIN blocks (e.g. a service that does `BEGIN; create user; create home; create item; ...; COMMIT`), both trigger audit inserts near the end. The advisory lock serializes them but each reads its own snapshot. The chain forks even with the lock.

**v1 didn't catch this** — v1 noted that pre-mig-080 forks were the bug, and the lock fixes them. Re-reading the lock body shows the fix is incomplete because of MVCC snapshot semantics.

**Fix:** read the predecessor with `ORDER BY ... FOR UPDATE` (escalate from FOR SHARE; under the advisory lock both work, but FOR UPDATE forces a fresh read past the snapshot):

```sql
SELECT this_hash INTO v_prev
  FROM audit_logs
 ORDER BY created_at DESC, id DESC
 LIMIT 1
 FOR UPDATE;
```

…and explicitly take a fresh snapshot inside the trigger by issuing a no-op `SET TRANSACTION SNAPSHOT` or by using `pg_xact_commit_timestamp` to detect the staleness. The cleanest answer is to give the trigger its own short-lived autonomous transaction (PG doesn't support that directly — would need dblink), or to switch the chain ordering to a BIGSERIAL `seq` column (per v1-C2 fix) so monotonicity comes from the sequence rather than from MVCC visibility.

---

### C3 — `cleanup_old_audit_logs()` will silently break the chain on first run (~2027-04-25); v1-M10 was right but the impact is bigger because the verifier offers no recovery

**File:** `apps/api/src/db/migrations/099_cleanup_audit_logs_owner_audit_cleaner.sql:24-31`

```sql
DELETE FROM audit_logs
WHERE created_at < NOW() - INTERVAL '1 year'
  AND severity = 'info';

DELETE FROM audit_logs
WHERE created_at < NOW() - INTERVAL '3 years'
  AND severity IN ('warning', 'error', 'critical');
```

Deleting any row N breaks every row N+1, N+2, … because each row's `this_hash` was computed against `prev_hash = audit_logs[N].this_hash`. Once N is gone, the verifier walks N-1 → N+1, recomputes N+1's expected hash with `v_prev = audit_logs[N-1].this_hash` (no longer N's), and that mismatches the stored value.

v1-M10 caught this. What v1 missed: there is **no rebase path**. The verifier returns `(broken_at, broken_id)` rows; it offers no "rechain from here" mode. So once cleanup runs, every subsequent `verify_audit_chain()` call returns ~the entire post-cleanup chain as broken — and there's no way to distinguish "broken because cleanup ran" from "broken because tampering."

**Operational impact:** the alarm I propose in C1 (cron-fire on broken_count > 0) becomes useless after the first cleanup run, because broken_count permanently is the post-cleanup row count.

**Fix:** `cleanup_old_audit_logs` must compute and store a tombstone row at each deletion boundary:
```sql
-- pseudocode
INSERT INTO audit_log_tombstones (cutoff_at, last_kept_hash, deleted_count)
  SELECT NOW() - INTERVAL '1 year', last_kept.this_hash, deleted_count
  FROM (DELETE ... RETURNING this_hash ORDER BY created_at DESC LIMIT 1) last_kept;
```
…and `verify_audit_chain` walks tombstones as chain anchors. This needs design.

---

### C4 — Schema.sql + mig 002's GRANT block is commented-out; in practice the API role has **superuser-equivalent privileges** on every table, so `audit_cleaner`'s purpose is largely security theater

**Files:**
- `apps/api/src/db/migrations/002_enhanced_features.sql:721-724` (GRANT block commented)
- `apps/api/src/db/schema.sql` (no GRANT statements)
- `apps/api/src/db/migrations/099_cleanup_audit_logs_owner_audit_cleaner.sql:39` (only post-099 grants on audit_logs)

```sql
-- mig 002:721-724
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO havenkeep_api;
-- GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO havenkeep_api;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO havenkeep_api;
```

The deploy comments say "Uncomment if using a specific database user." On the staging droplet, the API connects as the same role that ran the migrations — i.e. the role that is the *owner* of every table in the public schema. Owner has implicit `ALL PRIVILEGES` (PG default). So:

- `audit_logs` immutable trigger blocks UPDATE/DELETE for the API role — but the API role is also the *owner* of the table, and **owners can DROP the trigger**. `DROP TRIGGER trg_audit_logs_immutable ON audit_logs` is an unprivileged operation when run by the owner; the trigger isn't a privilege barrier against the API user, only against a future read-only role we never created.
- `cleanup_old_audit_logs` is owned by `audit_cleaner` (mig 099:35), but the API role can `ALTER FUNCTION ... OWNER TO havenkeep_api` if it has CREATEROLE or is a superuser — and on managed PG, the role that bootstraps the schema typically has both. If not, it can `DROP FUNCTION` and recreate as itself.
- `audit_cleaner NOLOGIN` (mig 031:14) only prevents direct login; SET ROLE works as long as the API role is INHERITed.

**v1 H1, H6** noted some of this individually. Putting them together: the entire append-only-audit-trail story is theatre against an attacker who has the API DB credentials. The trail protects against:
- Application bugs that issue UPDATE / DELETE on audit_logs (good — defense in depth).
- Operator typos via psql (good — lots of friction).
- Compromised application code where the attacker has only the SQL strings the API exposes (good — the API never UPDATEs audit_logs).

It does **not** protect against:
- Compromised API credentials with raw SQL.
- A malicious DBA.
- Anyone who has run a migration recently — they own the tables.

**Fix:** create a **separate `havenkeep_api`** role that owns *nothing*, and grant it INSERT/SELECT on audit_logs but no DDL. Migrations run as a separate `havenkeep_migrator` role (current behavior). The API process loads connection strings for `havenkeep_api`, not the migrator. This is a deploy-time refactor — non-trivial — but without it, the audit-chain work since mig 031 is contributing only modest defense.

---

## HIGH

### H1 — `audit_logs_immutable` trigger uses `current_user`, not `session_user`; an attacker who momentarily `SET ROLE audit_cleaner` inside an explicit transaction bypasses both UPDATE and DELETE

**File:** `apps/api/src/db/migrations/031_audit_logs_immutable.sql:25`

```sql
IF current_user = 'audit_cleaner' OR pg_has_role(current_user, 'audit_cleaner', 'MEMBER') THEN
  RETURN COALESCE(NEW, OLD);
END IF;
```

`current_user` reflects the active role context — including any `SET ROLE` performed in the session. `session_user` reflects the original login role and ignores `SET ROLE`. Using `current_user` means the trigger trusts the current SET ROLE state, which is exactly what an attacker who has API credentials would manipulate.

**Concrete attack:**
```sql
-- attacker has havenkeep_api creds + havenkeep_api is INHERIT-membered into audit_cleaner
BEGIN;
SET ROLE audit_cleaner;
DELETE FROM audit_logs WHERE id = '...';  -- trigger sees current_user='audit_cleaner', allows
RESET ROLE;
COMMIT;
```

C4 above details how the API role plausibly has SET ROLE rights. Even without that, the trigger would also allow this if `pg_has_role(current_user, 'audit_cleaner', 'MEMBER')` returns TRUE — and on a staging where the API role is granted INHERIT membership for any reason (e.g. for the cron to invoke `cleanup_old_audit_logs`), it does.

**Fix:** check `session_user` instead, AND scope the exemption to `TG_OP = 'DELETE'` (per v1-H1):
```sql
IF TG_OP = 'DELETE' AND (session_user = 'audit_cleaner' OR pg_has_role(session_user, 'audit_cleaner', 'MEMBER')) THEN
  RETURN OLD;
END IF;
```
This forces the cleanup path to actually log in as audit_cleaner (the function is SECURITY DEFINER so this is fine — its session_user becomes audit_cleaner inside the function body).

Wait — actually under SECURITY DEFINER, `session_user` is the *calling* session's user (unchanged), and `current_user` is the function owner. So `session_user = 'audit_cleaner'` would *fail* under SECURITY DEFINER. The right answer is `current_user = 'audit_cleaner'` *combined with* asserting `session_user != current_user` (i.e. the only legitimate flip is via SECURITY DEFINER, not via a manual SET ROLE):
```sql
IF TG_OP = 'DELETE' AND current_user = 'audit_cleaner' AND session_user IS DISTINCT FROM current_user THEN
  RETURN OLD;
END IF;
```
This rejects manual SET ROLE while allowing SECURITY DEFINER. Verify by testing.

---

### H2 — `oauth-encryption.ts` derives the AES-256 key from the secret via plain SHA-256 (no salt, no KDF, no AAD); a single secret in env is the entire crypto root and rotating it requires re-encrypting every row

**File:** `apps/api/src/utils/oauth-encryption.ts:33-39`

```ts
function deriveKey(secret: string): Buffer {
  const cached = keyCache.get(secret);
  if (cached) return cached;
  const key = crypto.createHash('sha256').update(secret, 'utf8').digest();
  keyCache.set(secret, key);
  return key;
}
```

Concerns, in order of severity:

1. **No AAD bound to row identity.** GCM supports additional authenticated data (`cipher.setAAD(buf)`). Binding the user_id (or row id) into AAD prevents a "swap attack" where an attacker with DB write access copies a long-lived token from row A to row B; without AAD the row B row decrypts cleanly (same key), the API uses the leaked token under user B's identity. With `AAD = user_id`, swap-decrypt fails the auth tag check.

2. **No KDF.** SHA-256 of the secret string is a 1-round derivation. If the secret is a low-entropy pass-phrase (the env var is a string, no length enforcement), brute force is trivial. Use HKDF or PBKDF2-SHA256 with a high iteration count, OR document that the secret must be 32+ random bytes (and validate length).

3. **No per-row salt.** Two encryptions of the same plaintext under the same key produce different ciphertexts (because the IV is random — verified at line 68), so this is OK against equality oracles. But IV reuse with the same key is catastrophic in GCM (forgery attack). With 12-byte random IVs, birthday collision is at ~2^48 encryptions per key. Within this app's scale, fine. Documenting the assumption matters for the next maintainer.

4. **Key rotation is row-by-row.** No key-id stored alongside ciphertext, so decrypt has to try every legacy key (lines 90-100). That's O(N legacy keys) per decrypt. v1-H4 noted the timing channel and the legacy-hit invisibility. Adding `key_id` (1-byte integer) to the stored ciphertext header would (a) make decrypt O(1), (b) give operators a definitive "all rows on key 2" signal, and (c) enable per-row rotation without re-encrypting.

**Severity rationale:** High because the OAuth refresh tokens (Gmail/Outlook scopes) and TOTP secrets (mfa.service.ts:151) all flow through this primitive. A swap attack against TOTP secrets is particularly bad — an attacker with DB write access could move user A's verified factor secret onto user B's row, then sign in as user B with codes generated from A's authenticator.

---

### H3 — `crypto.timingSafeEqual` is **never used** anywhere in the code; backup-code lookup, refresh-token lookup, and password-reset-token lookup all use plain equality on the keyed hash, which is technically constant-time *only because* the comparison happens inside Postgres's `=` operator

**Files:**
- `apps/api/src/services/mfa.service.ts:269-275` (backup code lookup)
- `apps/api/src/utils/token-hash.ts` (used by refresh tokens, password reset, email verification)

```ts
const consumed = await pool.query(
  `UPDATE user_mfa_backup_codes
      SET used_at = NOW()
    WHERE user_id = $1 AND code_hash = $2 AND used_at IS NULL
    RETURNING id`,
  [userId, hash],
);
```

The comparison is `code_hash = $2` (Postgres's `text =` operator). This **is** byte-by-byte equality, which is technically not timing-constant — Postgres's varchar comparison short-circuits on first mismatch. For 64-char hex strings there's a measurable timing differential between "first char differs" and "63 chars match."

For tokens that are themselves uniformly-distributed (HMAC-SHA-256 outputs), the differential leaks at most ~1 bit per attempt — and the lookup goes through a network round-trip (DB query) which adds noise that probably swamps the differential. So this is a Low in practice. But it's worth noting because:

- The mobile / API timing-safe pattern for password comparison uses bcrypt's compare (which IS constant-time). The token comparison breaks the convention.
- A pathological scenario: an attacker with a same-host (sidecar) co-tenant may be able to time the DB I/O at sub-microsecond precision. Real-world: only matters at very high attempt rates, and the rate-limiter caps that.

**Verified-correct contrast:** `password.ts` uses bcrypt via `bcrypt.compare` (in `auth.ts`), which is constant-time. That's the right pattern.

**Fix:** lookup by `(user_id, code_hash)` is unavoidable for a UNIQUE-indexed read. The PG btree comparator doesn't expose a constant-time mode. The right answer is to ignore the differential — which is what we're doing — and document in `mfa.service.ts` that the security model assumes the rate limiter, not the comparison primitive.

---

### H4 — `audit_logs_assign_hash()` calls `pg_advisory_xact_lock(687638440097)` but the trigger fires inside a `BEFORE INSERT` body — the lock is held until the *outer* transaction commits, not until the trigger returns

**File:** `apps/api/src/db/migrations/082_audit_chain_advisory_lock_fix_casts.sql:24`

```sql
PERFORM pg_advisory_xact_lock(687638440097);
```

`pg_advisory_xact_lock` is a transaction-scoped lock. Inside a BEFORE INSERT trigger fired by `INSERT INTO audit_logs ...`, the trigger's transaction *is* the outer transaction (not a subtransaction). So the lock is held from the moment the trigger acquires it until the **outer transaction** commits or rolls back.

If the outer transaction is long (e.g. a service that does BEGIN; lots of work; …; insert audit log; … more work; COMMIT), the audit lock blocks every other audit-insert across the entire system for the duration. An audit-log-on-every-route service therefore serializes through this single lock if any caller's outer tx is long.

**Concrete failure:** any route that does `BEGIN; insert user; insert home; await stripe; commit;` will hold the audit lock from the user-insert audit row through the Stripe round-trip (~200ms p50, ~5s p99). Every other concurrent audit-write blocks for that duration.

**Severity rationale:** High because it converts a per-row chain serialization into a per-outer-transaction serialization. The system-wide audit throughput is bounded by the slowest outer transaction.

**Fix:** the right answer is BIGSERIAL `seq` on audit_logs (no lock needed — sequence + sort by seq) per v1-C2's fix. As a stop-gap, `pg_advisory_lock` (session-scoped) would release on trigger return — but session-scoped locks across pooled connections is its own footgun. The seq column is the principled fix.

---

### H5 — `cleanup_old_audit_logs()` re-grant chain (mig 099→100) has a subtle race: the API role still has `SELECT, DELETE` on `audit_logs` from any pre-existing default grants, and mig 100's `GRANT SELECT ... TO audit_cleaner` doesn't `REVOKE` from the API role

**Files:**
- `apps/api/src/db/migrations/099_cleanup_audit_logs_owner_audit_cleaner.sql:39`
- `apps/api/src/db/migrations/100_audit_cleaner_select_grant.sql:15`

```sql
-- mig 099:39
GRANT SELECT, DELETE ON audit_logs TO audit_cleaner;

-- mig 100:15
GRANT SELECT ON audit_logs TO audit_cleaner;
```

These migrations don't REVOKE anything from anyone. The API role (table owner per C4 above) retains every privilege it had before. So the SECURITY DEFINER ownership swap in mig 099 doesn't reduce the API role's surface — it just adds audit_cleaner as a second authorized DELETE caller.

**The mig 099 commit message is misleading:** "No security regression: only callers granted EXECUTE on the function can trigger cleanup." That's true for *callers via the function*, but the *direct* DELETE path on `audit_logs` is unchanged — only the immutable trigger gates it (and per H1+C4 above, that gate is bypassable).

**Fix:** to actually realize the principle of least privilege:
```sql
REVOKE INSERT, UPDATE, DELETE ON audit_logs FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON audit_logs FROM havenkeep_api;
GRANT INSERT ON audit_logs TO havenkeep_api;
-- audit_cleaner already has SELECT, DELETE per migs 099/100.
```
This requires the separate `havenkeep_api` role from C4.

---

### H6 — Pool's `keepAlive: false` + 5s `connectionTimeoutMillis` defaults make migration replays fragile under network blip

**File:** `apps/api/src/db/index.ts:64-75`

```ts
export const pool = new Pool({
  host: config.database.host,
  port: config.database.port,
  ...
  max: POOL_MAX,
  idleTimeoutMillis: POOL_IDLE_MS,
  connectionTimeoutMillis: POOL_CONNECT_MS,  // 5000ms
  statement_timeout: STATEMENT_TIMEOUT_MS,
});
```

No `keepAlive: true` (v1-H2 noted this, but the migration runner uses its **own** Pool — `run-migration.ts:21-24` — without any of the index.ts knobs). The runner's pool has zero tuning beyond `connectionString` + ssl. Specifically:

- No statement_timeout (so a stuck migration runs forever).
- No idle_in_transaction_session_timeout (a crashed runner can hold the migration advisory lock until OS TCP reaper, ~2h).
- No application_name (operator can't tell which connection holds the migration lock).

The two-pool divergence is its own bug: the runner doesn't share index.ts's pool, so its pre-flight tuning (`SET idle_in_transaction_session_timeout`) doesn't apply.

**Severity rationale:** High for the migration runner specifically — the rest of the API recovers from a connection drop via pg-pool's reconnect, but the runner is a one-shot script that must succeed in a single connection and must release its advisory lock cleanly.

**Fix:** the runner should reuse `db/index.ts`'s `pool` (importing it directly), OR replicate the same SET LOCAL knobs on its own pool. Plus add `keepAlive: true, keepAliveInitialDelayMillis: 30_000`.

---

### H7 — `request_idempotency` table allows the same `idempotency_key` across different `route_key` values for the same user — but the middleware computes `request_hash = sha256(JSON.stringify(req.body))` and the body for `POST /warranty-claims` and `POST /warranty-purchases` may legitimately match (e.g. both `{}`)

**Files:**
- `apps/api/src/db/migrations/078_request_idempotency.sql:15-26` (PK = user_id + route_key + idempotency_key)
- `apps/api/src/middleware/idempotency.ts:60-61` (request hash = sha256(body))

```sql
PRIMARY KEY (user_id, route_key, idempotency_key)
```

```ts
const bodyForHash = JSON.stringify(req.body ?? {});
const requestHash = crypto.createHash('sha256').update(bodyForHash).digest('hex');
```

The PK is fine — different route_keys get separate cache entries. But within the same route_key, the request_hash is the body alone, ignoring:

- Query string parameters (a `POST /something?foo=bar` vs `POST /something?foo=baz` with same body have the same hash).
- URL path parameters (`POST /things/123` vs `POST /things/456`).
- Headers that affect response (Accept-Language, etc.).

The cache can replay a response that's wrong for the current request because the differentiator is in the URL or headers, not the body. Most routes pass IDs via URL paths — so a re-tap on `DELETE /items/A-id` with idempotency-key K, then a re-tap on `DELETE /items/B-id` with the same key K (same user, same route_key='items:delete') would replay A's response for B's deletion, which is wrong.

**Severity rationale:** High because mutation routes that key on URL params are common (`DELETE /items/:id`, `PATCH /warranty-claims/:id`). The collision needs a misuse pattern from the client, but a buggy mobile retry that reuses the same key for two different IDs would silently mis-respond.

**Verified by reading the middleware:** `req.body` is the only thing hashed. URL not included.

**Fix:** include the request URL (path + query) in the hash:
```ts
const sigParts = [req.method, req.originalUrl, JSON.stringify(req.body ?? {})];
const requestHash = crypto.createHash('sha256').update(sigParts.join('|')).digest('hex');
```
Mismatch on URL → 409, same as body mismatch.

---

### H8 — `webhook_event_high_water` PRIMARY KEY (source, subject_id) is a serializable single-row contention point — every Stripe customer.* event for the same Connect account contends for the same row UPDATE

**File:** `apps/api/src/db/migrations/050_webhook_ordering_and_dispute.sql:36-43`

```sql
CREATE TABLE IF NOT EXISTS webhook_event_high_water (
  source        VARCHAR(50)   NOT NULL,
  subject_id    VARCHAR(255)  NOT NULL,
  last_event_at TIMESTAMPTZ   NOT NULL,
  last_event_id VARCHAR(255)  NOT NULL,
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  PRIMARY KEY (source, subject_id)
);
```

Stripe sends events for the same Connect account in close succession (account.updated, capability.updated, person.updated, etc.). Each event handler does an UPDATE on the high-water row keyed on (`'stripe'`, `account_id`). At Stripe's burst rate (~10 events/second per Connect account during onboarding), every webhook handler serializes through one row.

This isn't a correctness bug — that's the *intent*: serialize so older events are dropped. But there's no batching or tx isolation tuning, so under burst load the webhook endpoint p95 grows.

**Severity rationale:** High under burst, low at steady state. Worth flagging because we DO see Stripe burst patterns during partner onboarding.

**Fix:** the high-water UPDATE should use SKIP LOCKED on the row read — handlers that can't grab the lock immediately should requeue rather than block. Or move the ordering check to a Redis SETNX with the event timestamp; PG row is the durable copy.

---

### H9 — `mfa.service.ts` enrollment writes the un-verified factor with `verified_at = NULL`, but the unique index is `WHERE verified_at IS NOT NULL` — so a user who restarts enrollment 100 times accumulates 100 NULL rows even though the service does a DELETE first

**Files:**
- `apps/api/src/db/migrations/084_user_mfa.sql:50-52`
- `apps/api/src/services/mfa.service.ts:170-174` (DELETE before INSERT)

```sql
CREATE UNIQUE INDEX IF NOT EXISTS uq_user_mfa_factors_verified
  ON user_mfa_factors(user_id, factor_type)
  WHERE verified_at IS NOT NULL;
```

```ts
await client.query(
  `DELETE FROM user_mfa_factors
    WHERE user_id = $1 AND factor_type = 'totp' AND verified_at IS NULL`,
  [userId],
);
```

The transaction is `BEGIN; DELETE old unverified; INSERT new unverified; INSERT 10 backup codes; COMMIT;` The DELETE is *intra-transaction*, so under high concurrency two enrollment calls for the same user can both DELETE the empty pre-state, both INSERT new rows, and both commit — no UNIQUE on the unverified rows means both rows persist. Subsequent verify queries `SELECT ... WHERE verified_at IS NULL LIMIT 1` would return whichever row Postgres feels like.

**Severity rationale:** High because the test for enrollment is then non-deterministic. One row's secret is what the user sees in the QR code; the other row's secret is what `verifyEnrollmentCode` reads. Verify fails because the secrets don't match.

The advisory in the code says "re-enrollment overwrites the unverified row" — true under sequential calls, false under concurrent calls.

**Fix:** add a partial UNIQUE on the unverified row too:
```sql
CREATE UNIQUE INDEX uq_user_mfa_factors_unverified
  ON user_mfa_factors(user_id, factor_type)
  WHERE verified_at IS NULL;
```
Then the second concurrent INSERT raises 23505 and the second enrollment caller sees an error.

---

## MEDIUM

### M1 — `audit_logs_assign_hash()` payload uses `NEW.action::text` (no COALESCE) but `action` is NOT NULL — fine; HOWEVER `NEW.resource_type` is plain `COALESCE(NEW.resource_type, '')` (no `::text` cast), and `resource_type` is `VARCHAR(50)` — also fine BUT ip_address::text returns CIDR representation

**File:** `apps/api/src/db/migrations/082_audit_chain_advisory_lock_fix_casts.sql:35-50`

The cast `NEW.ip_address::text` (line 44) returns `'192.0.2.1'` for a /32 INET; for `'192.0.2.1/24'::inet::text` it returns `'192.0.2.1/24'`. v1-M11 caught this. The deeper issue: PG's `inet_out` for a /32 returns the bare IP without /32 suffix:
```
SELECT '192.0.2.1'::inet::text → '192.0.2.1'
SELECT '192.0.2.1/32'::inet::text → '192.0.2.1'
SELECT '192.0.2.1/24'::inet::text → '192.0.2.1/24'
```
So the format is "stable for /32, mask for everything else." The application writes raw `req.ip` (no mask), so currently fine. But:

If the `network()` function is ever applied (e.g. anonymizing to /24 for telemetry while keeping the audit row's full IP elsewhere), the chain breaks.

**Fix:** use `host(NEW.ip_address)` consistently — always returns the bare IP regardless of mask. Two-line change in 082 + 075 (writer + verifier). Stable across any future inet manipulation.

---

### M2 — `partners` has `is_active` BOOLEAN (mig 002) AND `status` partner_status (mig 071) AND a CHECK invariant (mig 092); the column-level redundancy is the antithesis of mig 071's intent

**Files:**
- `apps/api/src/db/migrations/071_partner_status_enum.sql`
- `apps/api/src/db/migrations/092_partners_is_active_status_invariant.sql:23`

```sql
ALTER TABLE partners
  ADD CONSTRAINT chk_partners_active_status_consistent
  CHECK ((is_active = TRUE) = (status = 'active'));
```

The CHECK enforces what the comment in mig 092 says: "this is interim; drop is_active in a later phase." But the migration tree is at 100 with no follow-up. Every UPDATE on partners has to update *both* columns or hit 23514. Every reader has to choose which column to use.

Also: `chk_partners_active_status_consistent` rejects three of the four state combinations with `is_active=FALSE`:
- `is_active=FALSE, status='pending'` ✓ allowed (false ≠ true, false = false)
- `is_active=FALSE, status='active'` ✗ rejected (false ≠ true, but true = true)
- `is_active=FALSE, status='rejected'` ✓ allowed

So the combinations are correctly equivalent to "is_active reflects whether status is exactly 'active'." That's correct, but:

`partner_status` has 3 values (`pending`, `active`, `rejected`). `is_active` is binary. Collapsing 3 → 2 loses information at the `is_active` level — 'pending' and 'rejected' both map to is_active=FALSE, indistinguishable.

**Fix:** drop is_active column. Audit every reader: `grep -rn "is_active" apps/api/src --include="*.ts"`. Migrate each to `status = 'active'`. Then `ALTER TABLE partners DROP COLUMN is_active;` Confirm the dashboard still works.

---

### M3 — `category_defaults.icon` is `VARCHAR(64)` (mig 070:69) but the seed values use 1-char emoji or 1-byte chars; the widening was for "multi-codepoint emoji like flag-of-Scotland" but no such emoji exist in any seed migration

**Files:**
- `apps/api/src/db/migrations/024_create_category_defaults_and_brand_suggestions.sql:19` (DEFAULT '📦')
- `apps/api/src/db/migrations/070_phase8_drift_constraints.sql:69` (widen to 64)

Combined with mig 074 / 076 / 090 seed data that doesn't write the icon column, the default of `'📦'` (1 codepoint, 4 bytes UTF-8) is what every row carries. The widening to 64 chars is forward-looking but unused.

**Severity:** Medium. Not buggy; just unrealized.

**Fix:** none required — leave the headroom. Document the rationale at the column comment if missing.

---

### M4 — `partner_commissions.commission_rate DECIMAL(5,4)` allows 0..9.9999 — but the CHECK (mig 011:158) bounds to 0..1, so the column type permits values the CHECK rejects; that's fine, but the interaction with mig 041's `DROP DEFAULT` + mig 050's `SET NOT NULL` means a row inserted via direct SQL with `commission_rate = 1.5` raises CHECK violation rather than overflow

**Files:**
- `apps/api/src/db/migrations/011_audit_fixes.sql:142, 158` (column + CHECK 0..1)
- `apps/api/src/db/migrations/041_check_constraints.sql:64` (DROP DEFAULT)
- `apps/api/src/db/migrations/050_webhook_ordering_and_dispute.sql:138` (SET NOT NULL)

The story is fine but undocumented in any single place. Future maintainer reading mig 011 sees CHECK 0..1, mig 041 says "drop default to force callers to populate", mig 050 says "SET NOT NULL because un-defaulted." Three migrations to express one invariant.

**Severity:** Medium (cosmetic / readability).

**Fix:** add a `COMMENT ON COLUMN partner_commissions.commission_rate IS '0..1 (CHECK chk_partner_commissions_rate_range); NOT NULL; explicit per-tier population required'`.

---

### M5 — `documents.thumbnail_key` (mig 051:96-99) is renamed-from-`thumbnail_url` ONLY if the column exists; on a fresh schema.sql bootstrap the column is named `thumbnail_key` from the start (schema.sql:167), so the rename is a no-op — but mig 079 line 42-65 strips `https?://` from `documents.file_url` only inside an `IF EXISTS` block, so the rename happened but the strip doesn't run for fresh installs

**Files:**
- `apps/api/src/db/schema.sql:167` (`thumbnail_key TEXT`)
- `apps/api/src/db/migrations/051_openai_cost_and_idempotency.sql:88-99` (rename `file_url`→`object_key`, `thumbnail_url`→`thumbnail_key`)
- `apps/api/src/db/migrations/079_minio_object_keys.sql:42-65` (strip URL prefix from `documents.file_url`)

```sql
-- mig 079:47-65
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'documents' AND column_name = 'file_url'
  ) THEN
    EXECUTE $sql$
      UPDATE documents
      SET file_url = regexp_replace(file_url, '^https?://[^/]+/[^/]+/', '')
      WHERE file_url IS NOT NULL AND file_url ~ '^https?://';
    $sql$;
  END IF;
END
$$;
```

For a fresh DB: schema.sql creates `documents` with `object_key TEXT NOT NULL`. Mig 051 sees no `file_url` column to rename. Mig 079 sees no `file_url` column to strip. Result: fresh DBs have correct shape, migrating-from-old DBs go through the rename + strip. Correct, but mig 051's CHECK and mig 079's CHECK are different predicates — slightly fragile.

**Severity:** Medium — correctness is fine, but the migration ordering depends on column-presence guards rather than explicit `schema_version` markers.

---

### M6 — `apple_sign_in_nonces` PRIMARY KEY on `nonce_hash CHAR(64)` (mig 077:19) — CHAR(64) right-pads with spaces; if the API ever stores a hash with trailing space, lookups fail

**File:** `apps/api/src/db/migrations/077_apple_sign_in_nonces.sql:18-21`

```sql
CREATE TABLE IF NOT EXISTS apple_sign_in_nonces (
  nonce_hash  CHAR(64)  PRIMARY KEY,
  expires_at  TIMESTAMPTZ NOT NULL
);
```

CHAR(N) pads on storage, trims on comparison (PG quirk for VARCHAR vs CHAR). For the 64-char hex output of SHA-256, the application always writes exactly 64 chars, so the pad/trim is a no-op. But CHAR semantics are subtle:

```
SELECT 'abc'::char(5) = 'abc  ' → TRUE (trimmed)
SELECT 'abc'::char(5) = 'abc'   → TRUE (trimmed)
```

If a future caller writes a malformed nonce of 63 chars, it gets right-padded to 64, and the lookup `WHERE nonce_hash = 'abcd...63chars'` may match unexpectedly. This is the same "CHAR(24) iv/tag" gotcha that `oauth-encryption.ts:84-85` already works around with `.trim()`.

**Severity:** Medium — defensive concern.

**Fix:** use `CHAR(64) NOT NULL` here is fine *if* every writer canonicalizes via `encode(..., 'hex')`. Easier: change to `VARCHAR(64) NOT NULL` so no padding semantics.

---

### M7 — `webhook_events.event_id VARCHAR(255)` with no CHECK on format; Stripe IDs are `^evt_[A-Za-z0-9]+$`, RC IDs are UUIDs — a malformed event_id passes through silently

**Files:**
- `apps/api/src/db/migrations/026_create_webhook_events_table.sql:11`
- `apps/api/src/db/migrations/050_webhook_ordering_and_dispute.sql:131-132` (CHECK on `source` only, not `event_id`)

```sql
CHECK (source IN ('stripe', 'revenuecat'))
```

The sister CHECK on event_id format would be:
```sql
CHECK (
  (source = 'stripe' AND event_id ~ '^evt_[A-Za-z0-9]+$')
  OR (source = 'revenuecat' AND event_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
)
```

Without it, an attacker who can inject into the webhook handler's event_id (e.g. via a header smuggling bug) can write arbitrary strings into the table.

**Severity:** Medium — depth-in-defense.

---

### M8 — `partners.brand_color` CHECK regex `'^#[0-9A-Fa-f]{6}$'` (mig 041:30) accepts uppercase hex but the dashboard only writes lowercase; case drift across rendering surfaces possible

**File:** `apps/api/src/db/migrations/041_check_constraints.sql:30`

```sql
CHECK (brand_color IS NULL OR brand_color ~ '^#[0-9A-Fa-f]{6}$')
```

`'#FF5733'` and `'#ff5733'` are both valid. Dashboards usually canonicalize to lowercase; if one writer passes uppercase and the renderer assumes lowercase for `===` comparison (e.g. theme matching), they mismatch.

**Severity:** Medium — UI-rendering consistency, not data integrity.

**Fix:** narrow to `^#[0-9a-f]{6}$` AND add a `LOWER()` writeback trigger, OR document that callers must lowercase.

---

### M9 — `audit_logs.metadata` GIN index (mig 004:124) is unbounded; mig 065:107-110 added the 8KB CHECK, but a 7.99KB metadata JSON pushes the GIN index entry over a B-tree page and fails to insert

**Files:**
- `apps/api/src/db/migrations/004_audit_system.sql:124`
- `apps/api/src/db/migrations/065_audit_log_hash_chain.sql:107-110`

```sql
ALTER TABLE audit_logs
  ADD CONSTRAINT chk_audit_logs_metadata_size
  CHECK (metadata IS NULL OR octet_length(metadata::text) <= 8192);
```

PG's btree key limit is ~2,712 bytes per row; GIN indexes split large entries via the lexeme strategy on text but JSONB stores keys/values directly. A 7.99KB JSONB row indexed via `GIN(metadata)` may produce an index entry exceeding the limit and fail with `index row size XXX exceeds maximum YYY for index`.

**Severity:** Medium — depends on the JSONB structure. Flat JSON with one 7KB string value won't trip; many small keys won't either; a mid-size mix can.

**Fix:** add `WITH (gin_pending_list_limit = 4MB)` or use `GIN(metadata jsonb_path_ops)` (smaller index entries). Test with a stress case.

---

### M10 — `email_scanner_seen_messages.provider_message_id VARCHAR(998)` (mig 067:22) — chosen for "RFC 5322 worst-case" but RFC 5322 caps Message-ID at no specific length; 998 is the *line length limit* (folded), not the message-id limit

**File:** `apps/api/src/db/migrations/067_email_scanner_dedup_and_openai_budget.sql:22`

```sql
provider_message_id VARCHAR(998) NOT NULL,
```

The comment "998 chars covers RFC 5322 worst-case while staying under PG's btree key limit" conflates two limits. RFC 5322 §3.6.4 doesn't limit message-id length explicitly; section 2.1.1 limits *line length* to 998. A folded message-id can technically span lines but practical message-ids are ~100 chars max.

PG btree key limit (~2712 bytes) applies; VARCHAR(998) is fine. The choice is odd but not broken.

**Severity:** Medium — readability / semantic correctness of the comment.

---

### M11 — `gift_verify_attempts` (mig 032:35-43) is per-IP+per-minute, but the index is on `bucket_minute` only; a cleanup query `WHERE bucket_minute < NOW() - INTERVAL '24 hours'` works, but a per-IP query has no covering index

**File:** `apps/api/src/db/migrations/032_widen_activation_code_and_hash.sql:35-43`

```sql
CREATE TABLE IF NOT EXISTS gift_verify_attempts (
  ip_address INET NOT NULL,
  bucket_minute TIMESTAMPTZ NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (ip_address, bucket_minute)
);

CREATE INDEX IF NOT EXISTS idx_gift_verify_attempts_minute
  ON gift_verify_attempts(bucket_minute);
```

PK provides a `(ip_address, bucket_minute)` index — covers per-IP queries. The standalone `idx_gift_verify_attempts_minute` is for the cleanup. Three indexes on a small table is fine.

Verify correct.

---

### M12 — `notification_history.template_id REFERENCES notification_templates(id) ON DELETE SET NULL` (mig 002:416) but mig 044 widened user_id to SET NULL too — the row may end up with both NULL and become un-attributable

**File:** `apps/api/src/db/migrations/002_enhanced_features.sql:416`, `apps/api/src/db/migrations/044_notification_history_set_null.sql:16-21`

If a user is deleted AND the notification template is later deleted, the row has user_id=NULL, template_id=NULL, and only `user_email_at_send` (mig 044:21) and `type` columns identify it. That's enough for forensics but signals dead data.

**Severity:** Medium — operational concern. Cleanup cron should remove rows where both are NULL after retention.

---

### M13 — `chk_partner_gifts_chargeback_status` regex `'^[a-z][a-z0-9_]{0,63}$'` (mig 089:21) matches `'a'` which is below any plausible Stripe value (already in v1-M2); ALSO matches `'__'` (starts with `_` rejected, but the regex allows underscore in subsequent positions, so `'a__b'` passes — that's actually fine; just noting the regex is permissive)

Same as v1-M2. Length floor of 4 (`{3,63}`) is the right tightening.

---

### M14 — `tips.id SERIAL` (mig 018:6) on a 32-bit sequence; 24 seed rows + ~1 admin add per month means 28 years to run out, but it's the only SERIAL still alive in the schema — others were caught (e.g. `webhook_events.id` → BIGSERIAL via mig 087)

**File:** `apps/api/src/db/migrations/018_dynamic_tips.sql:6`

```sql
id            SERIAL PRIMARY KEY,
```

Negligible risk given the table's growth profile, but inconsistent with mig 087's intent.

**Severity:** Low/Medium — hygiene.

---

### M15 — `audit_logs_assign_hash` payload doesn't include `prev_hash` directly — the chain link is `v_payload = COALESCE(v_prev, '') || '|' || ...; this_hash = sha256(v_payload)`. The hash function output IS the chain extension. But there's no protection against an attacker recomputing a prefix's hash and then forking a new tail — i.e. without the verifier alarming, the chain head can be rewritten without detection

**File:** `apps/api/src/db/migrations/082_audit_chain_advisory_lock_fix_casts.sql:34-53`

The chain works as a Merkle-like list: row N's hash = sha256(N-1's hash || N's content). To forge row N+5, an attacker recomputes N+5's hash with the new content and stores it — and recomputes N+6, N+7, etc. since each depends on the new chain.

Detection requires knowing what the *original* N+5 hash was. The DB doesn't broadcast hashes anywhere external — no off-site attestation, no hash-store dump signed weekly. So an attacker with full DB write access can rewrite the entire chain consistently.

**Mitigation existence (none beyond DB):** the chain's value is restricted to "it's costly to rewrite all rows after a tampered point." That's still useful (forces the attacker to either tamper one row + crash the verifier, or rewrite the whole tail), but the security model is "tamper-evident, not tamper-proof."

**Fix (out of scope for now):** export the latest `this_hash` to an immutable external store (e.g. write to S3 with object lock, or to a Loki log with WORM). v1-M10 mentioned this.

---

## LOW

### L1 — `cleanup_old_audit_logs()` body is identical between mig 099 and the original mig 031 except for the missing `SET LOCAL ROLE` — and mig 031's body still exists in the function metadata (CREATE OR REPLACE replaces, not preserves history)

Cosmetic. The migration runner's drift detection (`run-migration.ts:198-205`) won't catch a function-body drift because it only SHA's the migration file, not the resulting function source.

---

### L2 — `apps/api/src/db/migrations/043_missing_updated_at.sql:39-44` adds `documents.deleted_at` then mig 085 drops it; that's two file changes for a feature that never existed in the application code

```sql
-- mig 043:39-44
ALTER TABLE documents
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_documents_user_not_deleted
  ON documents(user_id, created_at DESC)
  WHERE deleted_at IS NULL;

-- mig 085:19-20
DROP INDEX IF EXISTS idx_documents_user_not_deleted;
ALTER TABLE documents DROP COLUMN IF EXISTS deleted_at;
```

Process improvement note for the migration history's noise.

---

### L3 — `seed.ts` (`apps/api/src/db/seed.ts`) opens with the comment "Refuses to run in NODE_ENV=production" — verify the guard exists

I read lines 1-60. The header comment promises it but the implementation isn't visible there. Worth verifying.

---

### L4 — `mfa.service.ts:148` issuer is `'HavenKeep'` hardcoded; production may want it set via env so multi-tenant test environments don't show production issuer

**File:** `apps/api/src/services/mfa.service.ts:147-148`

```ts
const issuer = 'HavenKeep';
const otpauthUrl = totp.generateURI({ issuer, label: accountLabel, secret });
```

The `issuer` shows in the user's authenticator app. If a staging test scans the QR code into a real phone authenticator, it shows `HavenKeep` — confusing. Set via `config.mfa.issuer` with default `'HavenKeep'` and env override `'HavenKeep (staging)'`.

---

### L5 — `audit_logs_assign_hash` uses `digest()` from pgcrypto (per mig 065:54). Every audit insert pays the cost of pgcrypto's HMAC primitives. Benchmark: pgcrypto sha256 ~1μs/call, network round-trip ~100μs — fine, but a future high-throughput audit-write pattern (e.g. "log every read") would compound

---

### L6 — The `email_scan_status` ENUM (mig 002:110) and the `email_scan_review_state` ENUM (mig 039:11) are similarly named and easy to confuse; one is for scans, one is for review-queue items

Cosmetic; docs only.

---

### L7 — `notification_outbox.flushed_into_id REFERENCES notification_history(id) ON DELETE SET NULL` (mig 072:41) — but `notification_history` is the immutable trail and rows are never deleted, so SET NULL is unreachable. NO ACTION (the default) would be the same effect with one fewer FK action to consider

---

### L8 — `verify_audit_chain` (mig 075:55-92) is `STABLE` per mig 065:103 (`STABLE`); v1-L6 noted statement_timeout. Adding it: the function uses `FOR LOOP r IN SELECT * FROM audit_logs ORDER BY created_at, id`, materializing the entire table into a cursor. On 100M rows this is also a memory pressure event for PG.

---

### L9 — `request_idempotency.response_json JSONB` (mig 078:23) — JSONB is TOAST-eligible, large responses get out-of-line storage. The 32KB cap in middleware (idempotency.ts:35) is well below TOAST threshold (~2KB), so all idempotency rows stay in-line. Verified-correct.

---

### L10 — `pg_advisory_xact_lock(687638440097)` constant in mig 080/082 is hardcoded; v1-M5 said create a registry. Concretely:

```ts
// proposed: apps/api/src/db/advisory-locks.ts
export const ADVISORY_LOCKS = {
  MIGRATION_RUNNER: 0x4D47524E,         // 'MGRN'
  AUDIT_CHAIN: 687638440097,            // 0xA00D17C8A1
  ACCOUNT_PURGE: 0xa00d_4a13,
} as const;
```

The migrations would reference the constants by comment (SQL can't import TS), but having the canonical source-of-truth is the goal.

---

## OUT OF SCOPE / VERIFIED

### V1 — Migration 030a/030b enum split: VERIFIED CORRECT (per v1-V8 + my own re-read). 030a's ALTER TYPE commits before 030b's CHECK references the new value.

### V2 — Mig 098 `'cancelling'` enum: VERIFIED CORRECT. Same pattern as 030a, value not referenced in same file.

### V3 — `oauth-encryption.ts` IV uniqueness: 12-byte random IV per encryption (line 68), GCM auth tag verified at `decipher.final()` (line 94). VERIFIED CORRECT.

### V4 — Mig 087 BIGINT promotion: ALTER SEQUENCE + ALTER COLUMN TYPE on a populated table. PG metadata-only when widening; existing values preserved. VERIFIED CORRECT.

### V5 — Mig 100 SELECT grant: required because PG evaluates DELETE's WHERE under SELECT priv. VERIFIED CORRECT.

### V6 — Mig 091 widen `audit_logs.user_email` to VARCHAR(320): drops + recreates `recent_security_events` view to allow ALTER TYPE; metadata-only widen. VERIFIED CORRECT.

### V7 — Mig 097 trigger CASCADE allow: dropping DELETE from the immutable trigger preserves UPDATE-block while letting FK CASCADE prune; trigger function `RAISE EXCEPTION 'append-only'` body unchanged but now only fires on UPDATE. VERIFIED CORRECT.

### V8 — Migration runner advisory lock release: `pg_advisory_unlock(...)` in finally block + session-scoped lock auto-released on connection drain. v1-H3 detail. VERIFIED CORRECT.

### V9 — Pool `types.setTypeParser(1700, parseFloat)` (db/index.ts:14) — DECIMAL → JS number. Two-decimal-place values up to ~2^53 are exact. VERIFIED CORRECT for current money columns.

### V10 — `password.ts preHashForBcrypt` (lines 1-10): SHA-256 + base64 + slice(0, 72). Defangs bcrypt's 72-byte truncation. VERIFIED CORRECT.

### V11 — `token-hash.ts` HMAC-SHA-256 keyed by JWT refresh secret. Used for refresh tokens, password resets, MFA backup codes. Correct keyed-hash storage pattern.

### V12 — Mig 062 `savings_feed_anonymize_on_user_delete` BEFORE DELETE trigger: v1-M3 noted the double-write. Confirmed: trigger UPDATE + FK SET NULL is two writes. Performance concern, not correctness. Functionally correct.

### V13 — Mig 091 view drop+recreate around ALTER COLUMN TYPE: PG requires this when a column's type changes and a view depends on it. Mig handles correctly.

---

## TESTS COVERAGE

### Q1 — Migration tests
None. `phase10.audit.test.ts:155-166` only checks `schema_migrations` table exists with at least one row. No test exercises the `fileNeedsAutoCommit` regex (v1-C1), no test exercises the advisory lock contention, no test exercises drift detection.

### Q2 — CHECK constraint tests
None directly. Application-layer Joi validators test what the API rejects, but no test inserts a row directly into `partner_commissions` with `commission_rate=1.5` and asserts the CHECK rejects it.

### Q3 — Audit chain tests
None. `audit.test.ts` tests the routes (GET /audit/logs, /audit/security, /audit/stats) — never invokes `verify_audit_chain()`. The hash chain isn't exercised by any test.

### Q4 — OAuth encryption tests
**One round-trip test** in `email-scanner.test.ts:527-541`:
```ts
it('encryptToken + decryptToken returns the original plaintext', () => {
  const enc = encryptToken(plain);
  expect(decryptToken(enc)).toBe(plain);
});
it('two encryptions of the same plaintext produce different ciphertexts', () => {
  const a = encryptToken('foo');
  const b = encryptToken('foo');
  // ...
});
```
Good but minimal — no test for legacy key rotation, no test for tampered ciphertext (auth tag mismatch should throw), no test for malformed base64.

### Q5 — TOTP service tests
Couldn't find dedicated `mfa.service.test.ts`. Verify by searching tests for `enrollTotp` / `verifyChallengeCode`.

### Q6 — Account-purge tests
Service `account-purge.service.ts` has no dedicated test. The C4 anonymization sequence (denormalized email backfill BEFORE FK SET NULL) is critical-path code with no test.

---

## PER-TABLE PASS — TOP-LINE NOTES

I won't write 2-5 sentences for each of the 40+ tables — that would be 200+ paragraphs of mostly "looks reasonable." Instead, the issues I flagged above:

| Table | Issues |
|---|---|
| `users` | C4 (owner-equivalent grants); referral_code UNIQUE has uq + idx duplicate (mig 011 + 042) |
| `audit_logs` | C1, C2, C3, H1, H4, M1, M9, M15 (most issues here) |
| `partners` | M2 (is_active vs status redundancy) |
| `partner_gifts` | M13 (chargeback regex permissive); H8 indirect |
| `partner_commissions` | M4 (3-migration story for one invariant) |
| `webhook_events` | H8 (high-water contention); M7 (no event_id format CHECK) |
| `webhook_event_high_water` | H8 |
| `request_idempotency` | H7 (URL not in hash); v1-H7 (no batched cleanup) |
| `documents` | L2 (deleted_at churn) |
| `email_scanner_seen_messages` | M10 (998 length comment) |
| `apple_sign_in_nonces` | M6 (CHAR padding subtlety) |
| `category_defaults` | M3 (icon column over-sized) |
| `tips` | M14 (SERIAL not BIGSERIAL) |
| `user_mfa_factors` | H9 (concurrent enrollment race) |

Everything else: schema is reasonable, FK actions sensible, indexes match query paths.

---

## CHECK CONSTRAINT INVENTORY (selected)

I read every CHECK across the migrations. Listing the high-value ones:

| Migration | Constraint | Verdict |
|---|---|---|
| 011:85 | `chk_warranty_claims_status` (legacy enum strings) | superseded by mig 060 |
| 011:102 | `chk_partner_gifts_stripe_charge_required` | superseded by mig 041:36 |
| 011:158 | `chk_partner_commissions_rate_range` 0..1 | OK |
| 027:19 | `chk_webhook_events_status` (3 values) | superseded by mig 029 (4 values) |
| 029:18 | `chk_webhook_events_status` (4 values incl. dead_letter) | OK |
| 030b:35 | `chk_partner_commissions_paid_has_transfer` | OK (real $$ guard) |
| 030b:45 | `chk_partner_commissions_reversal_shape` | OK |
| 033:27 | `chk_warranty_claims_amounts` | OK |
| 035:23 | `chk_warranty_purchases_refund_shape` | OK |
| 037:27 | `chk_newsletter_status` | OK |
| 039:23 | `confidence_score 0..1` (table-level CHECK) | OK |
| 039:33 | `chk_email_scan_review_applied` | OK but uses OR — `state='approved' OR applied_id IS NOT NULL OR reviewed_at IS NOT NULL` — too permissive (allows approved with reviewed_at NULL) |
| 041:30 | `chk_partners_brand_color_hex` | M8 (case sensitivity) |
| 041:59 | partners `homebuyer_email` regex | OK; matches Joi |
| 041:73 | `chk_notification_first_reminder_days` 1..365 | OK |
| 041:79 | `chk_notification_reminder_time_hhmm` | OK |
| 041:106 | `chk_items_repair_cost_nonneg` | OK |
| 041:111 | `chk_items_lifespan_positive` 1..100 | OK |
| 050:59 | `chk_partner_gifts_expires_after_created` | OK |
| 050:67 | `chk_partner_gifts_chargeback_status` enum (8 values) | superseded by mig 089 (regex) |
| 050:95 | `chk_partners_stripe_account_status` | OK |
| 060:34 | `chk_warranty_claims_status` (canonical 6-state) | OK |
| 063:20 | `chk_notification_delivery_status` | OK |
| 065:110 | `chk_audit_logs_metadata_size` 8KB | M9 (GIN edge case) |
| 070:46 | `chk_items_added_via` (7 values) | OK |
| 070:53 | `chk_items_archived_consistency` | OK |
| 070:62 | `chk_maintenance_schedules_difficulty` | OK |
| 070:75 | `chk_partner_gifts_premium_months_range` 1..120 | OK |
| 070:83 | `chk_partner_commissions_amount_range` -100k..100k | OK |
| 070:91 | `chk_partner_commissions_reference_type` | OK |
| 070:97 | `chk_partner_commissions_payout_method` | OK |
| 070:117 | `chk_audit_logs_resource_type` | OK |
| 070:124 | `chk_audit_logs_http_method` | OK |
| 070:131 | `chk_webhook_events_source` | OK |
| 070:148 | `chk_contact_submissions_email_format` | OK |
| 070:155 | `chk_contact_submissions_message_length` 10..5000 | OK |
| 081:20 | `chk_audit_logs_description_size` ≤4000 | OK |
| 084:32 | `factor_type IN ('totp')` | OK; allows future expansion |
| 089:21 | `chk_partner_gifts_chargeback_status` regex | M13 (length floor) |
| 090:35 | `chk_category_defaults_lifespan_years` 1..100 | OK |
| 092:23 | `chk_partners_active_status_consistent` | M2 (column redundancy) |
| 093:15 | `chk_documents_file_size_nonneg` | OK; M9 noted no upper bound |

---

## INDEXES INVENTORY (selected pathologies)

I read every CREATE INDEX. The pathologies:

- v1-L3 noted `documents.idx_documents_user_id` is redundant with mig 005's `idx_documents_user_item`. Confirmed.
- Mig 037 `idx_newsletter_subscribed_email` partial UNIQUE on `LOWER(email) WHERE status='subscribed'`. Mig 094 dropped the redundant unconditional index. Correct cleanup chain.
- Mig 011 + mig 042's hygiene around `idx_items_user_archived_dup` etc. All accounted for via IF EXISTS guards.
- Mig 050's `idx_partner_gifts_chargeback_status` partial WHERE chargeback_status IS NOT NULL — correct (most rows have NULL).
- Mig 061's `uniq_warranty_purchases_user_payment_intent` partial on `WHERE stripe_payment_intent_id IS NOT NULL` — correct (idempotency for PI but legacy rows with NULL allowed).
- Mig 095's `idx_partner_commissions_pending_age` partial on `WHERE status = 'pending'` — covers auto-approve sweep. Per v1-M12 doesn't include partner_id, so the per-partner case has heap fetches. Acceptable for the sweep but noted.
- Mig 015 `idx_email_verification_metadata_type` is an expression index on `(metadata->>'type')` — IMMUTABLE? Yes, `->>` is IMMUTABLE for jsonb. Verify: `\df+ jsonb_extract_path_text` confirms. OK.

No new index pathologies beyond what v1 noted.

---

## TRIGGERS INVENTORY

| Trigger | Trigger Function | Verdict |
|---|---|---|
| `update_*_updated_at` (many tables) | `update_updated_at_column` | OK; search_path pinned in mig 040 |
| `trg_audit_logs_immutable` | `audit_logs_immutable` | H1 (current_user vs session_user) |
| `trg_audit_logs_hash_chain` | `audit_logs_assign_hash` | C2, H4 |
| `trg_warranty_claim_state_history_no_update` | `warranty_claim_state_history_immutable` | OK after mig 097 |
| `trg_savings_feed_anonymize` | `savings_feed_anonymize_on_user_delete` | v1-M3 (double-write) |
| `trg_partners_lock_partner_type` | `partners_lock_partner_type` | OK; has GUC escape hatch |
| `trg_user_oauth_integrations_updated_at` | `update_updated_at_column` | OK |

No trigger ordering issues found (no two BEFORE INSERT on same table). No recursion paths.

`update_updated_at_column` is applied to: users, homes, items, user_push_tokens, documents (post-mig-001), warranty_claims, maintenance_schedules, partners, partner_gifts, partner_commissions, warranty_purchases, user_analytics, notification_templates, notification_preferences, brand_suggestions, category_defaults, maintenance_history (post-mig-043), email_scans (post-mig-043), user_oauth_integrations.

**Missing on:**
- `audit_logs` — intentional (immutable).
- `webhook_events` — has its own `processed_at`/`first_seen_at`/`last_seen_at`.
- `webhook_event_high_water` — has its own `updated_at` (manual).
- `notification_history` — has `sent_at` semantics.
- `apple_sign_in_nonces` — short-lived.
- `gift_verify_attempts` — short-lived.
- `request_idempotency` — has `created_at` + `expires_at`.
- `notification_outbox` — has `created_at` only; mutation is `claimed_at` and `flushed_into_id`. Could argue `updated_at` would be useful but not load-bearing.
- `email_scanner_seen_messages` — append-only.
- `email_scanner_review_queue` — has `reviewed_at`. Could argue an `updated_at` for state-change tracking.

---

## ADVERSARIAL DB SCENARIOS

### P1 — Attacker with `audit_cleaner` role membership
Per H1: can DELETE any audit_logs row (including via DELETE-not-via-cleanup-function), can UPDATE rows because the trigger exemption isn't gated on TG_OP. Combined with C1, can null out hashes silently. Combined with C3, the cleanup function itself breaks the chain in 2027. **Maximum damage: full forge-the-history attack on a small subset of rows; chain rebuild required to detect; no off-DB attestation.**

### P2 — Attacker with API role's password but no encryption key
Cannot decrypt OAuth refresh tokens (utils/oauth-encryption.ts requires `OAUTH_TOKEN_ENCRYPTION_SECRET`). Cannot decrypt TOTP secrets (same). CAN read every other column verbatim, including bcrypt password hashes (offline crack; per password.ts the SHA-256 + bcrypt scheme means a 14-char password takes ~10^15 attempts). CAN issue `DROP TRIGGER trg_audit_logs_immutable` if the API role owns audit_logs (per C4). CAN forge user inserts (auth tokens are HMAC'd by the JWT secret; without the secret can't mint a valid bearer, but can insert a refresh_token row directly and have it accepted by the refresh route — wait, refresh tokens are HMAC'd by `config.jwt.refreshSecret` so an inserted row's hash wouldn't match unless the attacker knew the secret; OK). **Maximum damage: read everything not encrypted (most of the data), tamper with audit_logs (via H1+C4), but cannot impersonate users without the JWT secret.**

### P3 — SQL injection in API code
Quick scan: `apps/api/src/db/index.ts:120-145` exports `query<T>()` with parameterized `pool.query<T>(text, params)`. No template literal interpolation observed. The runner's CSP/PG-IDENT escape: `apps/api/src/db/migrations/run-migration.ts:88-111` reads SQL from disk and passes via `client.query(sql)` — not user-input.

The `db/index.ts:83` `SET idle_in_transaction_session_timeout = ${IDLE_IN_TX_MS}` uses string interpolation but `IDLE_IN_TX_MS` is `intFromEnv` validated. v1-L2 covered this. Confirmed safe given the type guard.

I didn't audit every route for SQL injection — that's covered by other audit runs.

### P4 — Direct ENUM value addition via psql, bypassing migrations
Outcome:
- `ALTER TYPE foo_enum ADD VALUE 'newval'` in psql is allowed for the type owner (the API role per C4).
- The migration runner at next boot doesn't notice (drift detection is on file SHA, not on enum membership).
- Application code that switches on enum values (TypeScript exhaustive `switch`) won't recognize the new value — would land in `default`.
- The audit-chain trigger DOES handle it (`NEW.action::text` casts the enum to its label, hashes the string).
- Inserting a row with the new value works; reading it via the API serializes the string.

So: a rogue enum addition is a forward-compatibility hazard but not a corruption hazard. The drift-detection gap is worth noting.

---

## SUMMARY

### Severity counts (this run)

| Severity | Count |
|---|---|
| Critical | 4 |
| High | 9 |
| Medium | 15 |
| Low | 10 |
| Verified-correct | 13 |

### Top recommended fixes (in order)

1. **C1+H1+C4** — bundle the audit-trail hardening: NOT NULL `this_hash`, gate the trigger to TG_OP=DELETE + `current_user='audit_cleaner' AND session_user IS DISTINCT FROM current_user`, separate `havenkeep_api` role from the migrator/owner role, REVOKE explicit privileges, off-DB chain attestation. Deploy in one migration batch.
2. **C2+H4** — replace the audit_logs (created_at, id) ordering with BIGSERIAL `seq`. Eliminates the MVCC-snapshot fork bug AND the per-outer-tx lock contention. Single column add + one-time UPDATE for backfill + trigger rewrite.
3. **C3** — design the chain-aware retention story before the cleanup actually runs in 2027. Tombstone scheme or split into archive+active.
4. **H7** — fold URL into the request_idempotency hash so URL-keyed routes can't replay another row's response.
5. **H6** — runner reuses index.ts pool, OR replicates its tuning. Add keepAlive.
6. **H9** — concurrent enrollment race: add UNIQUE on the unverified factor row.
7. **H2** — bind user_id into AAD on encrypt/decrypt. Add `key_id` to ciphertext header for O(1) decrypt.
8. **M2** — drop `partners.is_active`; migrate every reader to `status = 'active'`.
9. **L10** — central advisory-lock registry.
10. **Q3+Q4+Q6** — write tests for `verify_audit_chain`, OAuth encryption tampering paths, and account-purge anonymization sequence.

### Files flagged

Critical / High touch points (all paths absolute):

- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/db/migrations/031_audit_logs_immutable.sql` — H1
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/db/migrations/065_audit_log_hash_chain.sql` — C1
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/db/migrations/078_request_idempotency.sql` — H7
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/db/migrations/082_audit_chain_advisory_lock_fix_casts.sql` — C2, H4, M1
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/db/migrations/084_user_mfa.sql` — H9
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/db/migrations/099_cleanup_audit_logs_owner_audit_cleaner.sql` — C3, H5
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/db/migrations/run-migration.ts` — v1-C1, H6
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/db/index.ts` — H6
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/utils/oauth-encryption.ts` — H2
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/middleware/idempotency.ts` — H7
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/services/mfa.service.ts` — H9
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/services/account-purge.service.ts` — Q6 (untested)
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/services/audit.service.ts:625-627` — verifier never alarmed (C1)

---

End of report.
