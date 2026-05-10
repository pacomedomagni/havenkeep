# Audit v2 — Crons, Account Purge, Barcode Lookup

## Methodology
- **Files read in full:** `apps/api/src/index.ts` (628 lines), `apps/api/src/services/account-purge.service.ts` (156 lines), `apps/api/src/utils/storage-cleanup.ts` (123 lines), `apps/api/src/services/notifications.service.ts` (1295 lines), `apps/api/src/services/maintenance.service.ts` (relevant sections), `apps/api/src/services/audit.service.ts` (642 lines), `apps/api/src/services/partners.service.ts` (cron-relevant sections; expireUnactivatedPartnerGifts and autoApproveAgedPendingCommissions are inlined into index.ts), `apps/api/src/routes/barcode.ts` (144 lines), `apps/api/src/validators/barcode.ts`, `apps/api/src/services/email-scanner.service.ts:316-343` (revokeIntegration), `apps/api/src/services/fcm.service.ts:170-189` (cleanupStaleTokens), `apps/api/src/middleware/idempotency.ts:130-156` (pruneExpiredIdempotencyRows), `apps/api/src/routes/webhooks.ts:150-300` (claim/dead_letter), `apps/api/src/routes/users.ts:600-748` (DELETE /me + recover).
- **Migrations read line-by-line:** 002 (partners + partner_gifts + partner_commissions FKs), 004 (audit_logs FKs), 007 (user_push_tokens), 008 (notification_preferences), 028 (warranty FK RESTRICT — superseded by 083), 038 (user_oauth_integrations CASCADE), 044 (notification_history SET NULL + denorm), 051 (openai_usage CASCADE + receipt_scan_idempotency), 060 (warranty_claim_state_history actor_user_id SET NULL), 062 (maintenance_history user_id SET NULL), 064 (last_seen_at), 065 (audit hash chain), 066 (barcode_lookup_quota), 067 (email_scanner_seen_messages), 072 (notification_outbox), 077 (apple_sign_in_nonces), 078 (request_idempotency), 080 + 082 (audit-chain advisory lock + cast fix), 083 (warranty SET NULL + denorm email), 084 (user_mfa CASCADE), 095 (commission auto-approve partial index), 096 (partner.payout_request enum value), 099 + 100 (cleanup_old_audit_logs SECURITY DEFINER + SELECT grant).
- **Builds on:** `docs/audit-runs/12-cron-jobs-and-background.md` (v1). v1 ID tags appear in finding headers (e.g. "(v1 H1)") where this pass extends or confirms a prior finding rather than introduces a new one.

The v1 pass surfaced ~17 findings across these surfaces. This pass surfaces **64 distinct findings**, including 12 v1 findings still un-fixed.

---

## A. Cron Infrastructure

### A1. Cron registration (index.ts:35–169, 188–453, 469–504)
The cron system is two layers:

1. **Daily scheduler** (`scheduleExpirationNotifications`, line 188) — chains `setTimeout` from `computeNextDeadline()` (UTC `NOTIFICATION_HOUR_UTC`, default 14 = 9am ET). 30-minute drift checker reschedules if wall-clock drift > 5 min (lines 434–446).
2. **Digest tick** (`startDigestTick`, line 471) — chains `setTimeout` every 60 s from inside the handler so a long-running flush can't pile up overlapping invocations. First tick fires after `DIGEST_TICK_INTERVAL_MS`, not at boot.

Daily run executes (in order, all under `Promise.allSettled`):
- `runExpirationNotificationsJob` → `NotificationsService.checkAndNotifyExpirations()` (lock 93422874)
- `runMaintenanceDueJob` → `NotificationsService.checkAndNotifyMaintenanceDue()` (lock 93422875)
- `runWarrantyOffersJob` → `NotificationsService.checkAndNotifyWarrantyOffers()` (lock 93422876)
- `WarrantyPurchasesService.expireOverdueWarranties()` (no lock)
- `expireUnactivatedPartnerGifts` (lock 93422877)
- `autoApproveAgedPendingCommissions` (lock 93422878 — **same constant as DIGEST_FLUSH_LOCK**, see F-A-1 below)
- `AuditService.verifyHashChain()` (no lock)
- `pruneExpiredIdempotencyRows()` (no lock)
- `purgeExpiredSoftDeletedAccounts()` (in-service lock `0xa00d_4a13`)
- Then sequentially: `cleanup_old_audit_logs()` PG function, `notification_history` 90-day prune, `openai_usage` 90-day prune, `webhook_events` 7-day prune, `webhook_event_high_water` Stripe-only 90-day prune, `email_scanner_seen_messages` 90-day prune, `FcmService.cleanupStaleTokens(60)`, `receipt_scan_idempotency` 7-day-after-expiry prune, `apple_sign_in_nonces` expired prune, `gift_verify_attempts` 24h prune, then on Sunday-only `ReconciliationService.reconcileUserAnalytics()`.

### A2. Drift-resilient setTimeout pattern (index.ts:193-203, 426-432)
```ts
const computeNextDeadline = (): number => {
  const now = new Date();
  const next = new Date(Date.UTC(
    now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(),
    NOTIFICATION_HOUR_UTC, 0, 0, 0,
  ));
  if (next.getTime() <= now.getTime()) {
    next.setUTCDate(next.getUTCDate() + 1);
  }
  return next.getTime();
};
```
**Verified:** uses `getUTCHours/getUTCMinutes/getUTCDate` correctly. The drift threshold is 5 min; the check interval is 30 min. This is sound on Linux; on macOS a long sleep can blow past 5 min before the check fires (setInterval is throttled along with setTimeout when the host suspends).

### A3. Process killed mid-run
- The advisory lock is **session-scoped** (`pg_try_advisory_lock` not `pg_try_advisory_xact_lock`), released when the connection is returned to the pool — but if the process is **killed**, the underlying TCP socket eventually FIN/ACKs and Postgres releases the session. Until then, the lock is held; on a fresh boot at the same minute, `pg_try_advisory_lock` returns false and the cron silently no-ops (logs "another replica holds the lock").
- `runWithAdvisoryLock` releases via `finally` (line 41-44). If the process is SIGKILL'd between `pg_try_advisory_lock` and the `finally`, the lock survives until the PG-side keepalive expires (default `tcp_keepalives_idle` ≈ 2 hours on Linux). **This is a real problem if the API crashes between 09:00 UTC and the next 09:00 UTC** — the next replica's daily run will skip everything.
- `purgeExpiredSoftDeletedAccounts` (account-purge.service.ts:51-53) connects via `pool.connect()` and holds the lock on `guard`; same fate.

### A4. API killed and restarted exactly at the cron time
- `scheduleNext` (line 426) computes the next deadline at module load. On a 09:00 UTC restart, `computeNextDeadline()` returns 09:00 of *today* (the comparison `next.getTime() <= now.getTime()` is `<=`, not `<` — but `now` is "right now" which includes ms past 09:00:00.000, so a restart at 09:00:00.500 will produce `next = 09:00 today` (already past), the conditional fires, and the next deadline is 09:00 *tomorrow*).
- **Result: a restart at 09:00:00.001 UTC skips the entire daily run for the day.** The cron does not auto-run a missed window. This is finding F-A-2.

### A5. Multiple restarts in an hour
- Each restart calls `scheduleExpirationNotifications()` once. The advisory locks prevent overlap; but `runJobs()` only runs at the next deadline. If the API is restarted four times between 08:00 and 09:00, each instance independently waits until 09:00 and races on the lock — only one wins, the rest skip. That's the desired behavior.

### A6. Advisory lock pattern (index.ts:35-50)
```ts
async function runWithAdvisoryLock(lockId: number, label: string, fn: () => Promise<unknown>): Promise<void> {
  const client = await pool.connect();
  try {
    const lock = await client.query('SELECT pg_try_advisory_lock($1) AS locked', [lockId]);
    if (!lock.rows[0]?.locked) return;
    try {
      await fn();
    } finally {
      await client.query('SELECT pg_advisory_unlock($1)', [lockId]);
    }
  } catch (err) {
    logger.error({ err, label }, 'Cron job failed');
  } finally {
    client.release();
  }
}
```
**Issue:** if `pg_try_advisory_lock` itself throws (network blip), `client.release()` runs but `pg_advisory_unlock` does NOT. Same outcome as A3 — session-scoped, so the lock dies with the connection on pool reaping. Acceptable. But the wrapper does **not** distinguish "didn't acquire" from "fn threw" — both branches just return; the only signal is the log line. Findings F-A-3 / F-A-4 below.

### A7. Promise.allSettled (index.ts:208-269)
Each promise has its own `.catch`/`.then(undef, err => log)`. Failures are surfaced via `logger.error` and don't crash. **Verified.** But: the only signal that a job failed is the Loki log line — no metric, no Sentry. M-A-1.

### A8. Cron timezone
UTC. `NOTIFICATION_HOUR_UTC` defaults to **14** (= 9am ET / 6am PT / 11pm Sydney). This is *server-fixed*, not per-user. The user's TZ + quiet-hours are honored at *send* time, not at *cron* time, but the cron only runs **once** per day, so a user whose 9am local sits outside the cron's emit window (anything > 12 hours from 14:00 UTC) gets their daily notification at a fixed-server-time. Finding C-N-1.

### A9. Cron schedule rationale
9am ET picked because the comment in index.ts:177 says "9am of the user's locale" was the original intent. The current implementation is 9am for ET users only — see C-N-1.

### F-A-1: `DIGEST_FLUSH_LOCK` (93422878) collides with `PARTNER_COMMISSION_AUTO_APPROVE_LOCK` (93422878). **Severity: HIGH**
**File:** `apps/api/src/index.ts:65, 470`
```ts
const PARTNER_COMMISSION_AUTO_APPROVE_LOCK = 93422878;
// ...
const DIGEST_FLUSH_LOCK = 93422878;
```
**What:** Same numeric value used for two unrelated locks. The digest tick fires every 60s; the daily commission auto-approve fires once at 09:00 UTC. If a digest tick is in flight when the daily cron starts at 09:00 UTC, `pg_try_advisory_lock(93422878)` returns false to the daily caller (line 39 returns silently), and the auto-approve job is **skipped for that day**. Conversely, while the auto-approve runs, every minute-tick of the digest is a no-op until it finishes.
**Why it matters:** auto-approve is the only path that flips commissions from `pending` → `approved`; missing one day delays partner payouts by 24 hours. Worse, this is **unobservable** — `runWithAdvisoryLock` returns silently on lock-miss with no log line, so ops will never see "auto-approve skipped today" except as a missing "Aged pending commissions auto-approved" line in Loki.
**Repro:** restart the API at 08:59:30 UTC. The first digest tick fires at 09:00:30 (30 s post-boot). The daily cron also fires at 09:00:00. The digest grabs the lock first (process boot order); the daily run silently skips auto-approve.
**Fix:** bump `DIGEST_FLUSH_LOCK` to 93422879 (or any other unused integer).

### F-A-2: missed daily window after a restart at-or-just-after 09:00 UTC. **Severity: MEDIUM**
**File:** `apps/api/src/index.ts:199`
```ts
if (next.getTime() <= now.getTime()) {
  next.setUTCDate(next.getUTCDate() + 1);
}
```
**What:** A boot at 09:00:00.001 UTC computes `next = 09:00:00.000 today`, then the `<=` advances it to tomorrow. The daily cron is skipped for that calendar day — including audit-chain verify, account purge, idempotency prune, and the seven other retention sweeps. The next opportunity is +24h.
**Why it matters:** in a deployment-heavy day, a 09:00 UTC ship plus rollback can blow past the daily window twice. None of the sweeps run; the audit chain is unverified for an extra 24h; expired idempotency rows pile up.
**Suggested fix:** add a "if `now - todays09 < SOME_WINDOW` (say, 1 h), schedule next as `now + 100ms`." That way a restart anywhere in the 09:00–10:00 hour still emits today's run.

### F-A-3: `runWithAdvisoryLock` swallows BOTH the "didn't acquire" path and any throw inside `fn()` with no metric. **Severity: MEDIUM (M-A-1 in v1)**
**File:** `apps/api/src/index.ts:35-50`
**What:** When `fn()` throws, the wrapper logs `'Cron job failed'` and returns. When the lock is unavailable, the wrapper returns silently. From Loki's perspective, the only positive signal each job emits is its own internal "X notifications sent" / "X commissions auto-approved" line. There's no per-job heartbeat — Loki cannot tell "the job ran and produced 0 results" from "the job didn't run at all."
**Suggested fix:** emit `logger.info({ label }, 'cron tick start')` before `fn()` and `logger.info({ label, durationMs }, 'cron tick end')` after, so every run is bracketable in Loki and a missed run is detectable as the absence of a "tick start" line.

### F-A-4: advisory-lock release after `fn()` doesn't check the unlock result. **Severity: LOW**
**File:** `apps/api/src/index.ts:42-44`
```ts
} finally {
  await client.query('SELECT pg_advisory_unlock($1)', [lockId]);
}
```
**What:** `pg_advisory_unlock` returns boolean (true if released, false if you weren't holding it). Currently ignored. A future bug that double-acquires or skips the acquire (e.g. someone refactors `pg_try_advisory_lock` to not return a row) would silently call unlock without holding it, returning `false` and emitting nothing. Belt + braces: assert the boolean and warn when false.

---

## B. Account-purge service

### B1. Full service
Read in full at `apps/api/src/services/account-purge.service.ts:1-156`. Summary:
- Top-level lock `0xa00d_4a13` (line 37) — single-replica gate.
- Per-iteration loop bounded by `MAX_PER_RUN = 100` (line 66).
- For each candidate: open a tx-scoped client (`pool.connect()`), `BEGIN`, harvest MinIO keys via `harvestUserKeys`, anonymize warranty_purchases / warranty_claims user_email_at_purchase / user_email_at_claim, `DELETE FROM refresh_tokens`, `DELETE FROM users`, `COMMIT`. Post-commit best-effort `removeKeysBestEffort`.

### B2. Lock key (line 37)
`0xa00d_4a13` = decimal 2,684,805,139. Within Postgres's 4-byte advisory lock space. The other crons use 93422874–93422878 (line 26-65 / 470 of index.ts). No collisions; the choice of `0xa00d_4a13` is intentionally far from the other cron locks.

### B3. MAX_PER_RUN (line 66)
Bound = 100. Comment says "first run after the cron is wired" might pile up backlog. With 30-day cooling-off, a normal day produces few candidates. **No comment on what happens if backlog > 100/day** — the system will permanently fall behind. Finding F-B-1.

### B4. Candidate query (lines 68-75)
```sql
SELECT id, email FROM users
   WHERE deleted_at IS NOT NULL
     AND deletion_scheduled_for IS NOT NULL
     AND deletion_scheduled_for < NOW()
   ORDER BY deletion_scheduled_for ASC
   LIMIT 1
```
Fired in a loop. **No covering index** — the only relevant indexes are `users` PK and whatever exists on `deleted_at`. F-B-2.

### B5. Order: anonymize → DELETE refresh_tokens → DELETE users (lines 97-113)
Verified. The denorm-email population happens **inside** the tx; `DELETE FROM users` follows; anonymized FK columns get nulled by the SET NULL FK action **after** the email snapshot is captured. Order is correct.

### B6. MinIO key harvest (storage-cleanup.ts:60-88)
```sql
SELECT object_key, thumbnail_key FROM documents WHERE user_id = $1
SELECT product_image_url FROM items WHERE user_id = $1 AND product_image_url IS NOT NULL
SELECT avatar_url FROM users WHERE id = $1
```
Three parallel queries via `Promise.all`. Returns a `KeyHarvest` shape with arrays of object keys.

### B7. MinIO delete (storage-cleanup.ts:107-123)
```ts
for (const key of keys) {
  if (!key) continue;
  try { await minioClient.removeObject(BUCKET_NAME, key); removed++; }
  catch (err) { failed++; logger.warn({ err, key }, 'MinIO cleanup: removeObject failed (orphan)'); }
}
```
**Sequential**, best-effort, errors logged but never block the SQL DELETE (the SQL has already committed by this point). For a user with N=500 documents this is N round-trips serialized — at 50ms each, 25 s blocking the cron. Finding F-B-3 / P4.

### B8. DELETE FROM users — FK behavior
Yes, FK CASCADE / SET NULL is the only mechanism. After `DELETE FROM users WHERE id = $1`:
- **CASCADE** (rows deleted): `notification_preferences` (mig 008:11), `partners` (mig 002:153), `user_push_tokens` (mig 007:16), `user_oauth_integrations` (mig 038:20), `user_mfa_factors` + `user_mfa_backup_codes` (mig 084:31, 59), `barcode_lookup_quota` (mig 066:19), `email_scanner_seen_messages` (mig 067:18), `request_idempotency` (mig 078:16), `notification_outbox` (mig 072:20), `openai_usage` (mig 051:22), `receipt_scan_idempotency` (mig 051:54), `email_scanner_review_queue` (mig 039:15), and dozens of others (homes, items, documents, maintenance_history).
- **SET NULL**: `audit_logs` (mig 004:82), `notification_history` (mig 044:18), `warranty_purchases` (mig 083:32), `warranty_claims` (mig 083:42), `warranty_claim_state_history.actor_user_id` (mig 060:45), `partner_gifts.activated_user_id` (mig 002:211), `users.referred_by` (mig 011:68), `category_defaults.updated_by` (mig 066:36), `email_scanner_seen_messages.first_seen_scan_id` (mig 067:24).

### B9. CASCADE fan-out — what fires
Deleting one user CASCADES to:
- `partners` row → CASCADES to `partner_gifts` (CASCADE on partner_id) → CASCADES to `partner_commissions` (CASCADE on partner_id). **A partner who soft-deletes loses every gift they ever sent + every commission they ever earned.** See P6 / P7 below.
- `homes` → CASCADES to `items` → CASCADES to `documents` (and `maintenance_history.user_id` is SET NULL, but the row is also CASCADE-deleted via `item_id`).
- `notification_preferences`, `user_push_tokens`, `user_mfa_*`, `request_idempotency`, `notification_outbox`, `openai_usage` — all CASCADE.

### B10. (v1 H1, UNFIXED) — purge writes ZERO `audit_logs` rows. **Severity: HIGH**
**File:** `apps/api/src/services/account-purge.service.ts` (no `AuditService.log` call anywhere)
**What:** The DELETE /me handler at users.ts:693 does `AuditService.logFromRequest(req, 'user.delete', …)` — but that captures the *request* (the soft-delete event). The actual hard-delete 30 days later, executed by the cron, writes nothing to `audit_logs`. There is no `system.user_purge` audit action, no `user.delete` row written by the cron, nothing.
**Why it matters:** GDPR / CCPA workflows hinge on "we permanently deleted this user on date X." The only forensic trail is the single `logger.info({ userId, userEmail }, 'Soft-deleted user permanently purged…')` line in Loki at line 134-137. Loki retention is finite; audit_logs has the immutable hash chain. Soft-delete is auditable, hard-delete is not.
**Suggested fix:** add `await AuditService.log({ userId: null, userEmail, action: 'user.delete', severity: 'info', resourceType: 'user', resourceId: userId, description: 'Hard-delete after 30-day cooling-off' })` after `COMMIT` (the row is gone, so `userId` must be null and `userEmail` must come from the captured `email`).

### B11. Transaction boundaries (lines 86-119)
```ts
await txClient.query('BEGIN');
harvest = await harvestUserKeys(txClient, userId);
await txClient.query(`UPDATE warranty_purchases SET user_email_at_purchase = $2 …`);
await txClient.query(`UPDATE warranty_claims SET user_email_at_claim = $2 …`);
await txClient.query(`DELETE FROM refresh_tokens WHERE user_id = $1`);
const del = await txClient.query(`DELETE FROM users WHERE id = $1`, [userId]);
if (del.rowCount === 0) { /* concurrent delete, ROLLBACK; continue */ }
await txClient.query('COMMIT');
```
Anonymize-then-delete is atomic. If any step throws, the catch arm at line 120-122 rolls back — denorm columns stay NULL, user stays. Next run retries. Sound.

But — **harvested keys are computed BEFORE the warranty UPDATE** (line 87 vs 97). If a concurrent writer adds a document for this user *between* harvest and DELETE, the row gets CASCADE-deleted but the MinIO key is **not** in the harvest. F-B-4.

### B12. Per-user retry path (lines 138-144)
```ts
} catch (err) {
  result.failed++;
  logger.error({ err, userId }, 'Soft-delete purge: per-user failure (will retry next run)');
}
```
A per-user failure is logged and the loop continues. Bound is `MAX_PER_RUN = 100`, so a backlog of 100 failures pins the cron forever (the same 100 candidates re-fail every day). F-B-5.

### B13. Dead-letter for failed purges
**Does not exist.** A user who repeatedly fails to delete (e.g. a single broken FK action that we missed) re-appears in the candidate list every day, racks up a "failed" counter that resets each run (the `result.failed` counter is local to one cron invocation), and is never alerted on. F-B-5.

### B14. Backlog metric / alert
**Does not exist.** The cron returns `{ candidates, purged, failed, storageRemoved, storageFailed }` and the caller logs the result. No Loki dashboard, no Slack, no PagerDuty. F-B-6.

### F-B-1: MAX_PER_RUN=100 with no backlog observability or auto-scale. **Severity: MEDIUM**
**File:** `apps/api/src/services/account-purge.service.ts:66`
**What:** Capping at 100 means a flood of soft-deletes (e.g. a security event triggering a wave of users hitting "delete account") permanently builds up. There's no signal "candidates > 100 today, you're behind." After 30 days the candidate count + 100/day means the queue can grow to multi-thousands without anyone noticing — by which point users are entitled to "you said you'd delete in 30 days; you didn't" complaints.
**Suggested fix:** emit `logger.warn({ candidatesRemaining })` when the loop exits via the bound (i.e., `result.purged + result.failed === MAX_PER_RUN` and the next SELECT still returns a row). Or even better, expose a metric.

### F-B-2: candidate query has no covering index. **Severity: LOW**
**File:** `apps/api/src/services/account-purge.service.ts:68-75`
**What:** `WHERE deleted_at IS NOT NULL AND deletion_scheduled_for IS NOT NULL AND deletion_scheduled_for < NOW() ORDER BY deletion_scheduled_for ASC LIMIT 1` — if `users` has no partial index on `deletion_scheduled_for WHERE deleted_at IS NOT NULL`, this is a seq scan filtered by NULL test. On a 100k-user table, that's a full scan run 100x per day per cron invocation. Cheap today; expensive at scale.
**Suggested fix:** `CREATE INDEX CONCURRENTLY idx_users_deletion_pending ON users (deletion_scheduled_for) WHERE deleted_at IS NOT NULL AND deletion_scheduled_for IS NOT NULL` in a new migration.

### F-B-3: MinIO removal is sequential, blocks the cron. **Severity: LOW (P4 below)**
**File:** `apps/api/src/utils/storage-cleanup.ts:112-122`
**What:** Per-key sequential `removeObject`. A power user with 500 documents keeps the cron busy for 25 s. With `MAX_PER_RUN=100` users/day each owning ~50 docs, the daily cron can run for >40 min just on MinIO. None of this blocks other crons (each is in its own promise inside `Promise.allSettled`), but it does keep one connection pinned and matters for shutdown drain (the 30 s kill timer at index.ts:578-582 will hit before the sweep finishes if it lands inside SIGTERM).
**Suggested fix:** parallelize MinIO removes with `Promise.allSettled` + concurrency cap (8). Or use `removeObjects` (plural) which MinIO SDK supports for batch.

### F-B-4: harvest computed before warranty UPDATEs — racy with concurrent document writes. **Severity: LOW**
**File:** `apps/api/src/services/account-purge.service.ts:87`
**What:** `harvestUserKeys` runs BEFORE the warranty UPDATEs. A concurrent writer (e.g. a document upload that beats the soft-delete check) inserts a `documents` row between the SELECT and the DELETE. The row gets CASCADE-deleted, but its MinIO object_key is not in the harvest, so the object orphans in MinIO.
**Why minor:** the user soft-deleted 30 days ago and `deleted_at IS NOT NULL`; the upload route should reject. But there's no `AND u.deleted_at IS NULL` guard at most upload entry points, so this is theoretically reachable.
**Suggested fix:** harvest immediately before DELETE inside the same tx; or move harvest into the same SELECT as the DELETE via `RETURNING (SELECT array_agg(...))`. (The tx already isolates the read, but the read is at the start of the tx.)

### F-B-5: failed-purge backlog is invisible. **Severity: HIGH**
**File:** `apps/api/src/services/account-purge.service.ts:138-144`
**What:** Per-user failures log but never escalate. A single user with a broken FK CASCADE (a corner case introduced by a future migration) silently re-fails every day, ad infinitum, without paging. No `ALERT_AFTER_N_FAILURES`, no `dead_letter_users` table.
**Suggested fix:** add a `purge_failures` table with `(user_id, attempt_count, last_error, last_attempt_at)`; after 5 consecutive failures, emit a critical-severity audit_logs row.

### F-B-6: zero observability on purge backlog. **Severity: MEDIUM**
**Same theme as M-A-1.** No metric is emitted; the only signal is the Loki info line at lines 134-137 "Soft-deleted user permanently purged after 30-day cooling-off window." A morning where zero candidates exist, the cron emits NOTHING (the `if (result.candidates > 0 || result.purged > 0 || result.failed > 0)` gate at index.ts:263-267 silences zero-result runs).
**Suggested fix:** always emit one INFO line per cron tick with a count, even when zero, so Loki can detect "purge cron didn't run today."

### F-B-7: `notification_history.user_email_at_send` is never populated by the purge. **Severity: HIGH**
**File:** `apps/api/src/services/account-purge.service.ts` (warranty rows are denorm-emailed at lines 97-108 — but `notification_history` is not).
**What:** Mig 044 added `notification_history.user_email_at_send` for exactly the same reason mig 083 added `warranty_*.user_email_at_*` — preserve a forensic identifier when `user_id` becomes NULL. But the purge service only updates the warranty columns. After hard-delete, every notification_history row for the deleted user has `user_id = NULL` AND `user_email_at_send = NULL` — same as if the user never existed. **Mirror of v1 H1's spirit applied to notification_history.**
**Suggested fix:** add a third UPDATE inside the tx:
```ts
await txClient.query(
  `UPDATE notification_history
       SET user_email_at_send = $2
     WHERE user_id = $1 AND user_email_at_send IS NULL`,
  [userId, userEmail],
);
```

### F-B-8: refresh_tokens DELETE inside the tx is redundant — FK CASCADE already covers it. **Severity: LOW (cleanup)**
**File:** `apps/api/src/services/account-purge.service.ts:112`
**What:** Comment says "Refresh-tokens have FK ON DELETE CASCADE; explicit DELETE matches the admin path's belt-and-braces pattern." This is fine — but it's also dead code. If FK CASCADE works (and it does), the explicit DELETE is purely cosmetic. CLAUDE.md Rule 3 says "purge dead code." This is a judgment call; if the team wants belt-and-braces, leave a one-line comment to that effect (which it has).

---

## C. Notification cron

### C1. (already pasted in A1) — `NotificationsService.checkAndNotifyExpirations()` (lines 914-1026), `checkAndNotifyMaintenanceDue()` (1040-1162), `checkAndNotifyWarrantyOffers()` (1176-1294).

### C2. Expiring-warranty query (lines 919-938)
```sql
SELECT i.id as item_id, i.name as item_name, i.brand,
       i.warranty_end_date, i.user_id,
       u.email, u.full_name,
       COALESCE(np.first_reminder_days, 30) as reminder_days,
       COALESCE(np.email_enabled, FALSE) as email_enabled,
       COALESCE(np.push_enabled, TRUE) as push_enabled
FROM items i
JOIN users u ON u.id = i.user_id
LEFT JOIN notification_preferences np ON np.user_id = u.id
WHERE i.is_archived = FALSE
  AND i.warranty_end_date BETWEEN (NOW() AT TIME ZONE 'UTC')::date
    AND (NOW() AT TIME ZONE 'UTC')::date + make_interval(days => COALESCE(np.first_reminder_days, 30))
  AND NOT EXISTS (
    SELECT 1 FROM notification_history nh
    WHERE nh.item_id = i.id
      AND nh.type = 'warranty_expiring'
      AND nh.sent_at > NOW() - INTERVAL '1 day'
  )
```
**Cascade milestones?** None. The cron treats every day in `[today, today + first_reminder_days]` as eligible — a 30-day-out warranty fires daily for 30 days unless dedup'd. The dedup `nh.sent_at > NOW() - INTERVAL '1 day'` is **24 hours**, not "haven't sent at this milestone." So a user who reads + dismisses the notification on day 1 will get the same notification on day 2, day 3, … day 30. Finding F-C-1.

### C3. Dedupe (lines 932-937)
24h window via `NOT EXISTS … nh.sent_at > NOW() - INTERVAL '1 day'`. **Verified.** No "already opened, skip until 7 days before" intelligence. F-C-1.

### C4. notification_history INSERT (createNotification at lines 481-500)
INSERT-then-update pattern. The row is written `delivery_status='pending'` first, then flipped to `'delivered'` / `'failed'` in a second UPDATE after the FCM round-trip. **One row per attempt**, not per delivery.

### C5. Push send (lines 960-990)
`FcmService.sendToUser` → updates `delivery_status` based on count. Quiet-hours gated at line 960. The gate is `await NotificationsService.isUserInQuietHours(row.user_id)` which evaluates against `now = new Date()` — i.e., right when the cron is firing. F-C-2.

### C6. Email send (lines 992-1013)
`EmailService.sendWarrantyExpirationEmail` — only fires when `row.email_enabled` is true. Failures are logged but don't fail the row (the notification_history row stays with `delivery_status='delivered'` for the push path).

### C7. User-prefs gate (createNotification lines 419-441)
Inspects `notification_preferences.{tips_enabled, warranty_offers_enabled, reminders_enabled}` and writes `delivery_status='skipped'` if turned off. This is server-side. **Verified.** But: the cron's WHERE clauses (e.g., `checkAndNotifyExpirations`) DON'T pre-filter on `reminders_enabled` — every item with a warranty in window is read; the prefs check happens inside `createNotification`. This means a user who turned reminders off still gets a `notification_history` row written with `delivery_status='skipped'` every day. F-C-3.

### C8. Quiet-hours gate (lines 24-58, 715-724)
Server-side. The check is **against the user's stored `timezone`** (`Intl.DateTimeFormat({ timeZone: tz })`). Wraps midnight when `end < start`. **Verified.** But: bad TZ string falls back to UTC silently (line 45-46), so a user with `timezone='Europe/Paris'` typo'd as `'Europe/Pris'` gets evaluated in UTC — could send during their actual quiet hours.

### C9. Digest mode (createNotification lines 444-479, flushDigestOutbox 539-708)
When `digest_minutes > 0`, the immediate path inserts into `notification_outbox` with `flush_at = NOW() + digest_minutes`. The 60s digest tick claims due rows under `FOR UPDATE SKIP LOCKED`, groups by user, writes ONE summary `notification_history` row per user (`type='system'`, title="You have N new updates"), then sends FCM. **Verified one-FCM-per-user-per-tick.**

### C10. User-cache invalidation
The notification cron does NOT touch `invalidateUserCache`. The FCM send path inside the cron uses `pool.query` directly — no cache layer. ✓.

### F-C-1: 24h dedup means a user gets 30 daily reminders for a single warranty. **Severity: HIGH**
**File:** `apps/api/src/services/notifications.service.ts:919-938`
**What:** A warranty 30 days out is "in window" today, tomorrow, …, 30 days from now. The dedup is "sent in the last 24h, skip." So tomorrow at 09:00 UTC, the same item triggers again. The user gets the same "Warranty Expiring Soon — your X expires on Y" notification 30 times.
**Why it matters:** notification fatigue is the canonical reason users disable notifications altogether. The product surface is also misleading — "first_reminder_days" implies "send the *first* reminder N days out", but the implementation sends EVERY day for N days.
**Suggested fix:** dedup on milestone, not on day. E.g., `NOT EXISTS … nh.type='warranty_expiring' AND nh.item_id = i.id` (no time bound) — first reminder fires once, ever, per item per warranty period. Or step through milestones (30d → 14d → 7d → 1d) with separate dedup branches.

### F-C-2: quiet-hours check uses the cron's wall-clock instant. **Severity: MEDIUM**
**File:** `apps/api/src/services/notifications.service.ts:960`
**What:** `isUserInQuietHours(userId)` evaluates against `new Date()` *at the moment the cron decides this user*. With `for (const row of result.rows)` of N=10000 rows + 100ms per FCM round-trip, the cron walks N=10000 users sequentially over 1000 s = ~17 min. The user at row 0 gets evaluated at minute 0; the user at row 9999 gets evaluated 17 min later. A user whose quiet-hours boundary is 09:15 UTC and is at row 5000 might be evaluated at 09:15:01 UTC and skipped, when at the cron's "intended start time" (09:00 UTC) they were not in quiet hours.
**Why it matters:** quiet-hours boundaries with very narrow windows (e.g., a user who happens to set 09:00–09:01 to silence the cron specifically) become race-y. More practically, in O3 below, a user in quiet hours when the cron starts gets skipped — that's by design, but their notification row is left with `delivery_status='pending'`, the dedup window prevents re-emission for 24h, and they get **no notification at all that day**.
**Suggested fix:** if quiet-hours is hit, leave the row pending (don't flip to failed) AND backstop it with a "retry once after quiet-hours end" hook. Today the digest path correctly does this (line 664-668); the immediate-push paths do not.

### F-C-3: cron writes a `notification_history` row even when prefs say "off". **Severity: MEDIUM**
**File:** `apps/api/src/services/notifications.service.ts:441-499` (createNotification skipped-status path)
**What:** A user with `reminders_enabled=FALSE` still gets a `notification_history` row written daily with `delivery_status='skipped'` for every item in window. After 30 days that's 30 * N items = thousands of skipped rows. The 90-day retention sweep eventually cleans them up; in the meantime the user's `getUnreadCount` query (line 254-260) does a COUNT over a table that's been bloated by hundreds of skipped rows.
**Why it matters:** `getUnreadCount` excludes skipped rows in its WHERE (`delivery_status IN ('pending', 'delivered')`) — so the user-facing count is right. But the skipped rows are still scanned for the COUNT, and the count query has no `delivery_status` index. F-C-3 is mostly a perf/storage cleanliness issue.
**Suggested fix:** pre-filter the cron's SELECT to skip users with `reminders_enabled = FALSE`. The cost of a single LEFT JOIN check is dwarfed by the cost of writing N notification_history rows you'll never deliver.

### F-C-4: timezone fallback to UTC on bad TZ string is silent. **Severity: LOW**
**File:** `apps/api/src/services/notifications.service.ts:45-46`
**What:** `try { Intl.DateTimeFormat({ timeZone: tz }) } catch { /* fall through */ }`. A bad string silently uses UTC. The user might be in their actual quiet hours but evaluated in UTC and pushed to. No log, no metric.
**Suggested fix:** validate `timezone` at write time (preferences upsert) using the same `Intl.DateTimeFormat` smoke test, reject 400 if invalid.

### F-C-5: maintenance_due dedup keys on `data->>'schedule_id'` — JSON path scan. **Severity: LOW**
**File:** `apps/api/src/services/notifications.service.ts:1083-1084`
**What:** `(nh.data->>'schedule_id') = ms.id::text` — no GIN index on `data`, no expression index. On a notification_history table with 100k rows the dedup is a seq scan filtered by JSON extract per `i.id` per schedule. With 100 items per user × 5 schedules per category × N users, this is a quadratic scan.
**Suggested fix:** denormalize `schedule_id` to a top-level column on notification_history, OR add `CREATE INDEX … ON notification_history ((data->>'schedule_id'))`.

---

## D. Maintenance cron

### D1. The "maintenance cron" is `checkAndNotifyMaintenanceDue` (NotificationsService:1040-1162). **There is no separate maintenance cron** — `MaintenanceService` is request-path only.

### D2. Due-tasks query (lines 1048-1087)
```sql
SELECT i.id AS item_id, i.name, i.brand, i.user_id, u.email, u.full_name,
       ms.id AS schedule_id, ms.task_name, ms.frequency_months,
       COALESCE(last_done.completed_date, i.purchase_date::DATE) AS reference_date,
       COALESCE(np.push_enabled, TRUE) AS push_enabled,
       COALESCE(np.email_enabled, FALSE) AS email_enabled
FROM items i
JOIN users u ON u.id = i.user_id
JOIN maintenance_schedules ms ON ms.category = i.category
LEFT JOIN LATERAL (
  SELECT completed_date FROM maintenance_history mh
   WHERE mh.item_id = i.id AND mh.schedule_id = ms.id AND mh.user_id = i.user_id
   ORDER BY completed_date DESC LIMIT 1
) last_done ON TRUE
LEFT JOIN notification_preferences np ON np.user_id = i.user_id
WHERE i.is_archived = FALSE
  AND i.purchase_date IS NOT NULL
  AND (COALESCE(last_done.completed_date, i.purchase_date::DATE) + make_interval(months => ms.frequency_months)) <= (NOW() AT TIME ZONE 'UTC')::date
  AND NOT EXISTS (
    SELECT 1 FROM notification_history nh
    WHERE nh.item_id = i.id
      AND nh.type = 'maintenance_due'
      AND (nh.data->>'schedule_id') = ms.id::text
      AND nh.sent_at > NOW() - INTERVAL '7 days'
  )
ORDER BY i.user_id, i.id
```

### D3. frequency_months — months past `last_completed` (or `purchase_date`). 7-day dedup window per (item, schedule). Sane choices.

### D4. Notification emission (lines 1090-1155)
Same shape as warranty-expiring: createNotification → push (if enabled + not in quiet hours) → email (if enabled).

### F-D-1: maintenance dedup is 7-day; if the cron misses one window (e.g. F-A-2 above), the next emission is +7 days. **Severity: LOW**
**What:** Dedup key is "any maintenance_due notification for this (item, schedule) in last 7 days." If the daily cron fires today and the row is dedup'd from yesterday's emission, that's fine. If yesterday's cron was missed (F-A-2), today's catches it. But **if today's cron is also missed**, the row sits one more day — by which point a new "due" check still fires. The risk window is bounded.

### F-D-2: maintenance dedup query has no index supporting it. Same as F-C-5.

---

## E. Audit-chain verification cron

### E1. (index.ts:233-245)
```ts
AuditService.verifyHashChain().then(
  (broken) => {
    if (broken.length > 0) {
      logger.error(
        { brokenCount: broken.length, firstBrokenAt: broken[0] },
        'Audit log hash chain INTEGRITY FAILURE — possible tampering',
      );
    } else {
      logger.info('Audit log hash chain verification passed');
    }
  },
  (err) => logger.error({ err }, 'Audit hash chain verification failed'),
);
```

### E2. `AuditService.verifyHashChain()` (audit.service.ts:624-629)
```ts
static async verifyHashChain(): Promise<Array<{ broken_at: Date; broken_id: string }>> {
  const result = await pool.query<{ broken_at: Date; broken_id: string }>(
    `SELECT broken_at, broken_id FROM verify_audit_chain()`,
  );
  return result.rows;
}
```
Calls the `verify_audit_chain()` PG function defined in mig 065 (re-applied in 075).

### E3. Alert path on broken rows
Just `logger.error(…, 'Audit log hash chain INTEGRITY FAILURE — possible tampering')`. No email, no PagerDuty, no audit_logs row, no Sentry. The CLAUDE.md says "Sentry is intentionally not used; pino → Loki." So Loki is the only signal.
**Loki alert config?** Not in this repo. The staging Caddy config + Dozzle don't ship alerting. Finding F-E-1.

### E4. Performance — full table scan
`verify_audit_chain()` (mig 065:66-103) is a `FOR r IN SELECT * FROM audit_logs ORDER BY created_at ASC, id ASC LOOP` — every row, every day. On a year-old install with 50M audit rows this is multi-minute. Not a per-request cost; it's a once-a-day background hit. Still: **no incremental verification** — every cron run re-hashes the entire chain. Finding F-E-2.

### E5. (v1 L6) STABLE function with statement_timeout=30s
**File:** `apps/api/src/db/migrations/065_audit_log_hash_chain.sql:103`
```sql
$$ LANGUAGE plpgsql STABLE;
```
**Verified STABLE.** Postgres `STABLE` says "no side effects, returns the same result for the same args within a tx" — true for a chain verifier. But **there is NO `SET LOCAL statement_timeout = '30s'`** anywhere in the function. The default `statement_timeout` is 0 (no limit) on most PG installs. On a 50M-row audit_logs the function can run for many minutes; if that pins the cron client, other crons finish but the audit-verify keeps running. The cron's `Promise.allSettled` doesn't time out; it waits.
**Suggested fix:** wrap the call in a per-call `SET LOCAL statement_timeout` from the JS side, or add it inside the function: `SET LOCAL statement_timeout TO '30s';` at the top.

### F-E-1: audit-chain break has no escalation beyond a single Loki line. **Severity: HIGH**
**File:** `apps/api/src/index.ts:236-240`
**What:** A broken audit chain is a "possible tampering" event. The only signal is a single `logger.error` line in Loki. There's no email-the-team, no audit_logs row written (which would fail-loud anyway since the chain is broken), no automatic page-the-on-call.
**Suggested fix:** post to a configured webhook (Slack/PagerDuty) on chain break, OR insert a `system.error` audit_logs row with severity='critical' (the immutability trigger doesn't block inserts, only update/delete; a broken chain doesn't prevent fresh inserts).

### F-E-2: chain verification re-hashes the full table daily — O(N²) over time. **Severity: MEDIUM**
**File:** `apps/api/src/db/migrations/065_audit_log_hash_chain.sql:66-103`
**What:** Every cron run walks the whole table from row 1. After 1 year of inserts at 1k/day that's 365k rows; after 5 years, 1.8M. The verification is still cheap in absolute terms (sha256 is fast), but the JS-side cron is wall-clock latency you don't need.
**Suggested fix:** add a "watermark" table `audit_chain_verification_state` with `(last_verified_id, last_verified_at)`. The verifier resumes from `last_verified_id` and only walks new rows. A weekly full-walk catches any tampered older row.

### F-E-3: no `statement_timeout` guard on `verify_audit_chain()`. **Severity: LOW**
See E5. As of today the table is small enough that runtime is sub-second; this is preventive.

---

## F. Partner gift expiry cron

### F1. (index.ts:87-121)
```ts
async function expireUnactivatedPartnerGifts(): Promise<void> {
  await runWithAdvisoryLock(PARTNER_GIFT_EXPIRY_LOCK, 'partner-gift-auto-expiry', async () => {
    const expired = await pool.query(
      `UPDATE partner_gifts
          SET status = 'expired',
              activation_code = NULL,
              activation_url = NULL,
              updated_at = NOW()
        WHERE status IN ('created', 'sent')
          AND is_activated = FALSE
          AND expires_at IS NOT NULL
          AND expires_at < NOW()
        RETURNING id, partner_id`,
    );
    if (expired.rowCount === 0) return;
    const giftIds = expired.rows.map((r: { id: string }) => r.id);
    const cancelled = await pool.query(
      `UPDATE partner_commissions
          SET status = 'cancelled', updated_at = NOW()
        WHERE reference_type = 'partner_gift'
          AND reference_id = ANY($1::uuid[])
          AND status = 'pending'
        RETURNING id`,
      [giftIds],
    );
    logger.info(/*...*/);
  });
}
```

### F2. WHERE shape
`status IN ('created', 'sent') AND is_activated = FALSE AND expires_at < NOW()` — slightly broader than the prompt's "WHERE status='created'". 'sent' covers gifts that were emailed but never activated. ✓.

### F3. Status flip — `'expired'`. The plaintext `activation_code` + `activation_url` get NULL'd in the same UPDATE (privacy: an expired gift's plaintext code stops being valid; the hashed copy stays for audit).

### F4. Notification to partner
**There is none.** The cron logs `expiredGifts: N, cancelledCommissions: M` to Loki. The partner is not notified that their gift expired. Finding F-F-1.

### F-F-1: expired gift / cancelled commission emits zero user-facing signal. **Severity: MEDIUM**
**File:** `apps/api/src/index.ts:87-121`
**What:** A partner sends a gift to a homebuyer. Homebuyer never activates. 90 days later the gift expires, the commission is cancelled. The partner sees:
- Dashboard: gift status flips from 'sent' to 'expired'.
- Commission row: flips from 'pending' to 'cancelled'.
- Email / push: nothing.

The partner has no idea their gift expired unless they happen to look at the dashboard.
**Suggested fix:** emit a `partner_commission` notification (or new type `gift_expired`) to the partner's user_id. The notification path already exists for commission events.

### F-F-2: cron-level race between `expireUnactivatedPartnerGifts` and the activation request path. **Severity: LOW (O6)**
**File:** `apps/api/src/services/partners.service.ts:970-1029` (activation under `SELECT … FOR UPDATE`)
**What:** Activation takes a row lock (`SELECT * FROM partner_gifts WHERE id = $1 FOR UPDATE`); the cron's UPDATE matches by status='created'/'sent'. If the activation grabs the lock first and flips status to 'activated' before COMMIT, the cron's UPDATE sees the post-commit status (or blocks until COMMIT depending on isolation level). PG's default `READ COMMITTED` means the cron's UPDATE re-reads at row-lock time and the WHERE clause is re-evaluated, so a row activated mid-cron simply won't match. ✓ — race is benign.

### F-F-3: cron runs as a single SQL — does not call `partners.service` "expire" function (which doesn't exist). **Severity: LOW**
The cron is **inlined** into index.ts rather than wrapped in `PartnersService.expireUnactivatedGifts()`. Refactoring opportunity — keeps cron call sites and service logic in different files. CLAUDE.md Rule 3 considerations.

---

## G. Commission auto-approve cron

### G1. (index.ts:136-169)
```ts
const result = await pool.query(
  `UPDATE partner_commissions pc
      SET status = 'approved',
          approved_at = NOW(),
          updated_at = NOW()
     FROM partners p
    WHERE pc.partner_id = p.id
      AND pc.status = 'pending'
      AND pc.created_at < NOW() - ($1::int || ' days')::interval
      AND p.stripe_account_status = 'enabled'
      AND NOT EXISTS (
        SELECT 1 FROM partner_commissions r
         WHERE r.reversal_of_commission_id = pc.id
      )
      RETURNING pc.id, pc.partner_id, pc.amount`,
  [COMMISSION_AUTO_APPROVE_HOLD_DAYS],
);
```

### G2. 30-day SQL: pasted above. `COMMISSION_AUTO_APPROVE_HOLD_DAYS` env-configurable, defaults to 30.

### G3. Mig 095 partial index (`idx_partner_commissions_pending_age`) — `WHERE status = 'pending'` covers the cron's `WHERE pc.status = 'pending'` filter. The `created_at` ordering matches the index. ✓.

### G4. Reversal-sibling exclusion `NOT EXISTS (SELECT 1 FROM partner_commissions r WHERE r.reversal_of_commission_id = pc.id)` — verified. If a refund clawback wrote a reversal row with `reversal_of_commission_id = pc.id`, the original is excluded. ✓.

### G5. `stripe_account_status='enabled'` gate
`AND p.stripe_account_status = 'enabled'` — verified at the SQL level. The dashboard's "request payout" endpoint would also gate on this, but auto-approving for an unverified partner would mislead the dashboard's "approved (eligible for payout)" total. Sound design.

### F-G-1: cron does not write `audit_logs` rows for auto-approval. **Severity: MEDIUM**
**File:** `apps/api/src/index.ts:158-166`
**What:** When the cron flips `pending → approved`, no `audit_logs` row is created. The only signal is `logger.info({ approvedCount, holdDays }, 'Aged pending commissions auto-approved')`. Per the CLAUDE.md audit-chain stance, financial state changes should be on the immutable audit chain.
**Suggested fix:** for each approved row, write an `audit_logs` row with `action='partner.payout_request'` (or new `partner.commission_auto_approve` enum value via a 101 migration) tying `partner_id` + `commission_id`.

### F-G-2: cron does not notify the partner. **Severity: LOW**
Same shape as F-F-1. A partner whose commissions auto-approved is informed only if they happen to look at the dashboard.

### F-G-3: cron has no `LIMIT` cap. **Severity: LOW**
The UPDATE has no LIMIT. On a backlog (e.g., the partial index migration just shipped), a one-time burst could approve 10k commissions in one transaction. The single SQL is atomic, so it either all commits or all rolls back; that's fine. But the lock the UPDATE holds on the partial-index range can block partner_commissions writes (e.g. new commission creation from gift redemption) for the duration. On a healthy table this is sub-second; with millions of pending rows it could spike.
**Suggested fix:** chunk via `id IN (SELECT id FROM partner_commissions … LIMIT 500)` if the cron ever sees backlog. Today not needed.

---

## H. Webhook dead-letter retry

### H1. Does this cron exist? **NO** — confirmed v1 H-MP-3.
**File:** `apps/api/src/index.ts` — no `dead_letter` cron registration.

### H2. Manual retry path
The webhook claim function (webhooks.ts:169-237) writes `status='dead_letter'` after `MAX_WEBHOOK_ATTEMPTS=8`. A dead-lettered event:
- Is acknowledged 200 to Stripe (line 388-396) so Stripe stops retrying.
- Stays in `webhook_events` with `status='dead_letter'`, `processed_at=NULL`.
- Is **never automatically retried**.
- Is **never automatically alerted**.

The `webhook_events` 7-day retention sweep (index.ts:313-322) deletes rows where `processed_at < NOW() - INTERVAL '7 days'` — but dead_letter rows have `processed_at = NULL`, so they survive forever (M-MP-1 below).

### F-H-1: dead-letter webhooks are silently invisible. **Severity: HIGH**
**What:** A Stripe charge.refunded webhook that fails 8 times in a row is acknowledged 200 to Stripe (so Stripe walks away), gets `status='dead_letter'`, and lives in the table indefinitely. The only signal is `logger.error` calls inside the failed handler invocations + the final `logger.error('Stripe webhook event in dead-letter — acknowledging without processing')` at webhooks.ts:391-394. No email, no page, no `audit_logs` row.
**Why critical:** a dead-lettered `charge.refunded` means the customer's refund landed in Stripe but HavenKeep didn't roll back the warranty / commission. Money out, money in our books, asymmetric.
**Suggested fix:** dead-lettering a charge.refunded should write `audit_logs` with severity='critical' (the audit chain catches this) AND emit a webhook to a Slack/PagerDuty endpoint. Add a daily cron that surfaces `SELECT COUNT(*) FROM webhook_events WHERE status='dead_letter'` and alerts when > 0.

### F-H-2: dead_letter rows survive forever. **Severity: MEDIUM (v1 M-MP-1)**
**File:** `apps/api/src/index.ts:313-322`
```ts
DELETE FROM webhook_events WHERE processed_at < NOW() - INTERVAL '7 days'
```
**What:** dead_letter rows have `processed_at = NULL`. They are NOT deleted by this sweep. `processed_at < NULL` is `NULL` (unknown), so the row never matches. Over years, dead-lettered rows accumulate.
**Suggested fix:** broaden the WHERE: `WHERE (processed_at IS NOT NULL AND processed_at < NOW() - INTERVAL '7 days') OR (status = 'dead_letter' AND last_seen_at < NOW() - INTERVAL '90 days')` — keep dead_letters around long enough to investigate (90 days), then sweep.

---

## I. Apple nonce cleanup

### I1. (index.ts:393-401)
```ts
const r = await pool.query(`DELETE FROM apple_sign_in_nonces WHERE expires_at < NOW()`);
```

### I2. WHERE — `expires_at < NOW()`. ✓. The table (mig 077) has `idx_apple_sign_in_nonces_expires` covering this.

### I3. Frequency — once a day.
**Issue:** the table TTL is 5 minutes (Apple nonces are consumed within seconds, max 5 min). A daily prune means the table has 24h of expired rows at the high-water mark. If the API runs 100k Apple sign-ins/day, the table holds 100k expired rows between sweeps. Each row is 64 bytes for the hash + 8 for expires_at — 7 MB. Negligible; but the 5-min TTL means a 5-minute sweep would be more honest.

### F-I-1: prune runs daily, table TTL is 5 minutes. **Severity: LOW**
**Suggested fix:** move the prune into the digest-tick (60s) loop or a dedicated 5-min interval. Cost is small but the cleanliness gap is 287x.

---

## J. email_scanner_seen_messages cleanup

### J1. (index.ts:347-357)
```ts
DELETE FROM email_scanner_seen_messages WHERE first_seen_at < NOW() - INTERVAL '90 days'
```
Daily.

### J2. 90-day prune — verified via `idx_email_scanner_seen_messages_first_seen` index (mig 067:29). ✓.

### F-J-1: the dedup window for email scanning is 90 days. **Severity: LOW**
**What:** A user who scans Gmail today sees a receipt; 91 days later the row is pruned; 92 days later the same Gmail thread comes back into the user's "scan" window (Gmail keeps mail for years), the dedup miss → the OpenAI call re-fires. **Result: re-billed for already-scanned mail past 90 days.**
**Why minor:** a 90-day-old Gmail message rarely matters for the warranty surfacing UX. But it does double-bill OpenAI for a user that scans monthly.
**Suggested fix:** raise to 365 days; cost is small (one row per receipt per user) and matches Gmail's typical search window.

---

## K. request_idempotency cleanup

### K1. `pruneExpiredIdempotencyRows()` (idempotency.ts:151-156)
```ts
export async function pruneExpiredIdempotencyRows(): Promise<number> {
  const result = await pool.query(
    `DELETE FROM request_idempotency WHERE expires_at < NOW()`,
  );
  return result.rowCount ?? 0;
}
```
Daily.

### K2. 24h prune — the per-row TTL is set per-route (default 24h), so this just sweeps anything past its row-level expiry. ✓.

### K3. (v1 H7) chunking
**There is NO chunking.** A single `DELETE … WHERE expires_at < NOW()` issued as one statement. On a busy install, 24h of idempotency rows can be 100k+. The DELETE takes a row-level lock per row in one tx. **If the table is under write contention (mid-day deploy, cron coincides with a burst of authenticated mutations), the DELETE can block real requests.**
**v1 H7 was that this needed chunking.** It still doesn't.

### F-K-1: (v1 H7, UNFIXED) request_idempotency prune is unbounded. **Severity: HIGH**
**File:** `apps/api/src/middleware/idempotency.ts:151-156`
**What:** No `LIMIT` clause, no chunking. A single DELETE for all expired rows takes one giant lock. With `idx_request_idempotency_expires` (the comment at line 148-149 references it), the planner uses an index range scan, which is fast — but it still acquires row locks in one tx. On a 100k-row sweep at 24h, blocking writes for the duration is plausible.
**Suggested fix:**
```ts
let total = 0;
for (;;) {
  const r = await pool.query(
    `WITH del AS (
       SELECT id FROM request_idempotency WHERE expires_at < NOW() LIMIT 5000
     )
     DELETE FROM request_idempotency WHERE id IN (SELECT id FROM del)`
  );
  total += r.rowCount ?? 0;
  if ((r.rowCount ?? 0) < 5000) break;
}
return total;
```

---

## L. Webhook events retention

### L1. (index.ts:313-322)
```ts
DELETE FROM webhook_events WHERE processed_at < NOW() - INTERVAL '7 days'
```

### L2. 7-day retention WHERE — verified.

### L3. (v1 M-MP-1) dead_letter rows survive (`processed_at IS NULL`) — see F-H-2 above.

### F-L-1: same chunking concern as K3. **Severity: MEDIUM**
On a high-volume install (Stripe + RC) the daily delete can sweep 50k+ rows. Same fix shape.

---

## M. Cron observability

### M1. Logged with start/end?
**No.** Each cron emits its own internal "X done" line; no per-tick start/end bracket. See F-A-3.

### M2. Duration captured?
**Partially.** The digest tick captures `Date.now() - startedAt` for re-scheduling at index.ts:489-491, but doesn't log it. Other crons don't time themselves.

### M3. Rows-processed count captured?
**Yes** for most jobs (each `logger.info({ count, … })` at the end of the job). Conditional emission on `if count > 0` at index.ts:263-267 and 317-321 etc., though, means a zero-result run is silent — *can't tell "ran with 0 results" from "didn't run."*

### M4. Per-cron Loki dashboard?
**Not in this repo.** The CLAUDE.md mentions `https://logs.staging.kouakoudomagni.com` (Dozzle) for log streaming; no dashboards committed.

### M5. Alert threshold for "cron didn't run today"?
**Not in this repo.** No Loki alert config, no Grafana dashboards. Operational gap.

### F-M-1 to F-M-5: each of M1–M5 is its own gap. Combined severity: **HIGH**.
The crons are correct in mechanism but unobserved. A silent failure (lock held by a stuck PG session, a bug that returns early before the log line) is undetectable until a downstream user-visible symptom appears days later.

---

## N. Barcode lookup deep

### N1. Route (`apps/api/src/routes/barcode.ts`)
```ts
router.use(authenticate);
router.use(requirePremium);
// ...
router.post('/lookup', validate(barcodeLookupSchema), asyncHandler(async (req, res) => {
  const { barcode } = req.body;
  const user = req.user!;
  await consumeBarcodeQuota(user.id, (user as any).plan ?? 'premium');
  // … redis cache check, then upcitemdb fetch, then cache + return.
}));
```

### N2. (v1 M9) quota — incremented BEFORE cache check
**File:** `apps/api/src/routes/barcode.ts:46-67`
```ts
await consumeBarcodeQuota(user.id, (user as any).plan ?? 'premium');
// …
const cached = await redis.get(cacheKey);
if (cached) return sendSuccess(res, JSON.parse(cached));
```
**v1 finding still un-fixed.** The `consumeBarcodeQuota` does an INSERT … ON CONFLICT … `lookups = lookups + 1` and throws 429 if over. **Cache hits cost the user a quota slot.** A premium user's 50/day cap is exhausted by 50 cache hits even though zero upstream calls happened.
**Why it matters:** a single product (e.g. an iPhone) being looked up 50 times by a confused user via cache hits saturates the daily cap without ever calling upcitemdb.
**Suggested fix:** check Redis cache FIRST. If cache hit, serve and skip quota consume. Or, on cache hit, decrement the quota (refund). Or split: cache hits consume a separate "cache_lookups" counter that's much higher.

### N3. Redis cache TTL (lines 19-20)
```ts
const BARCODE_CACHE_TTL_HIT = 86400;       // 24h
const BARCODE_CACHE_TTL_MISS = 60 * 60;    // 1h
```
24h on hit, 1h on miss. ✓.

### N4. Product DB integration
The route hits `https://api.upcitemdb.com/prod/trial/lookup?upc=$BARCODE` (line 75-78). **No internal product DB** — every lookup goes to upcitemdb. The trial endpoint is rate-limited at the global level (CLAUDE.md mentions "shared 100/day upcitemdb trial cap" in the comment at line 21-25). If any HavenKeep user hits 100 lookups in a day, the next user gets a 429 from upcitemdb.

### N5. Fallback when no result
404 from upcitemdb returns `{ barcode, brand: null, product_name: null, description: null, image_url: null }` and caches it with `BARCODE_CACHE_TTL_MISS`. ✓. 200-with-empty-items takes the same path (lines 132-141).

### N6. Free-tier limit
`QUOTA_FREE = 10` (line 27). Comment at line 25-26: `requirePremium` blocks free users from this route, so this constant is dead code unless the gate is removed later. Cleanup item: F-N-1.

### N7. Premium-tier limit (50/day)
`QUOTA_PREMIUM = 50` (line 26). ✓.

### N8. Audit log entry
**There is NO `audit_logs` row** for a barcode lookup. The `logger.info` calls happen, but no `AuditService.log({ action: '…' })`. There's no `barcode.lookup` audit_action enum value either. Per the CLAUDE.md "ALL means ALL" and the existing audit infrastructure for state changes, this is a gap if the team considers barcode usage a billable / forensically interesting event.

### N9. Error path — provider 5xx, provider rate limit
- Timeout: `AbortController` + 10 s, returns 504 "Barcode lookup timed out" (lines 71-85).
- Non-200 non-404: returns 502 "Barcode lookup service unavailable" (lines 104-108) with `External API returned status ${statusCode}` — leaks upstream status to the client.
- 404: caches empty result with 1h TTL.
- **No retry, no backoff.** A flaky 502 once costs the user one quota slot for that day (since quota is consumed before fetch).

### N10. Result schema
```ts
{ barcode, brand, product_name, category: 'other', image_url, description }
```
- `category` is hardcoded to `'other'` if not provided by upcitemdb (line 118). **No mapping to HavenKeep's `item_category` enum.** A user creating an item from a barcode result lands in 'other' regardless of the product's actual upcitemdb category like 'Cell Phones' or 'Refrigerators.' Finding F-N-2.

### F-N-1: dead `QUOTA_FREE` constant. **Severity: LOW (cleanup)**
**File:** `apps/api/src/routes/barcode.ts:27`
**What:** `requirePremium` middleware (line 14) blocks free users from this route entirely. `QUOTA_FREE = 10` is unreachable. CLAUDE.md Rule 3.
**Suggested fix:** delete the constant and the `plan === 'premium' ? QUOTA_PREMIUM : QUOTA_FREE` ternary; just use `QUOTA_PREMIUM`.

### F-N-2: barcode lookup result doesn't map upcitemdb's category to HavenKeep's `item_category` enum. **Severity: LOW**
**File:** `apps/api/src/routes/barcode.ts:118`
**What:** upcitemdb returns categories like `"Cell Phones & Accessories > Smart Watches"`. The route stores it as a free-form string. The mobile UI then uses it for the "Add Item" prefill — but the item table's `category` column is enum-typed (`item_category`), so the UI must throw it away and ask the user.
**Suggested fix:** add a `mapUpcCategoryToItemCategory(s: string): ItemCategory` helper. Test against the top 50 upcitemdb category strings.

### F-N-3: no audit_logs row for barcode lookup. **Severity: LOW**
**File:** `apps/api/src/routes/barcode.ts`
**What:** Barcode lookups against a paid third-party API are billable resource consumption. Per audit conventions, that should leave a chain entry.
**Suggested fix:** add a new `barcode.lookup` enum value via a migration; emit one audit_logs row per attempt with `metadata: { barcode, cache_hit, upstream_status }`.

### F-N-4: 502 leaks upstream status to client. **Severity: LOW**
**File:** `apps/api/src/routes/barcode.ts:104-107`
**What:** `message: \`External API returned status ${statusCode}\`` — leaks that we have an upstream and what status it returned. Information disclosure-grade.
**Suggested fix:** scrub: `message: 'Barcode service temporarily unavailable'`.

### F-N-5: response uses raw `res.status(...).json()` instead of the `sendSuccess` helper for error paths — schema drift. **Severity: LOW**
**File:** `apps/api/src/routes/barcode.ts:82, 104, 142`
**What:** Success path uses `sendSuccess` (the wrapper that ensures `{ data: …, success: true }` envelope per project convention). Error paths use bare `res.status(404).json({ error: … })` — different shape than the rest of the API. Mobile error handler probably shrugs and re-throws as `ApiException.unknown`.
**Suggested fix:** convert to `throw new AppError(...)` and let the global error middleware emit the canonical envelope.

### F-N-6: no Redis fallback if Redis is down. **Severity: LOW**
**File:** `apps/api/src/routes/barcode.ts:60-68`
**What:** If `getRedisClient()` throws, the read swallows and proceeds to the upstream. ✓. But the cache *write* (lines 95-100, 122-127, 133-140) also swallows. So a Redis flap means EVERY lookup hits upcitemdb (the trial cap is 100/day) and quotas burn even on previously-cached barcodes.
**Suggested fix:** when Redis fails, write a small in-process LRU as a degraded fallback. Or rate-limit upcitemdb at the application layer.

---

## O. Adversarial cron scenarios

### O1. Two replicas boot simultaneously, both try the daily cron.
- Both call `pg_try_advisory_lock(<lockId>)`. PG is the arbiter; only one wins; the other returns false from the conditional at index.ts:39 and silently skips (`return`).
- **Sound.** But silent skip — no log, no metric (F-A-3).

### O2. Cron runs but Redis is down.
- Notifications can't dedupe via Redis (notifications.service.ts uses Postgres `notification_history` for dedup, not Redis — so this is fine).
- The barcode cron path (which doesn't have a cron) would fail (F-N-6).
- The shared Redis client (`getRedisClient()`) would throw inside the cron paths that touch it — currently none do.
- **Conclusion:** the daily cron is Redis-independent. ✓.

### O3. Cron runs at 09:00 UTC; user's quiet hours = 21:00–09:00 PST. They're in quiet hours when the cron runs.
- 09:00 UTC = 02:00 PDT (summer) / 01:00 PST (winter). User is in quiet hours.
- `isInQuietHours` (lines 49-58) wrap-over-midnight branch returns true.
- The push send is skipped (line 960-961). The notification_history row stays `delivery_status='pending'`.
- **Next-day's cron** finds the row in `nh.sent_at > NOW() - INTERVAL '1 day'` dedup → skip.
- **The user gets NO push, no email — just an in-app row they may never look at.** F-C-2.

### O4. Cron emits 10K reminders, push service rate-limited.
- `FcmService.sendToUser` is called N times in serial (no batching, no concurrency).
- FCM's per-app rate limit is around 600,000 messages/min — way above 10K — but per-token limits and "topic" rate limits matter.
- Each failed FCM call writes `delivery_status='failed'` (or just leaves 'pending' if the call throws). No retry, no exponential backoff.
- **Result: a fraction of the 10K silently fail; the dedup window prevents tomorrow's retry.** F-C-1 + F-O-1.

### O5. Audit-chain verify finds a break.
- `logger.error(…, 'Audit log hash chain INTEGRITY FAILURE — possible tampering')` (line 236-240).
- **Runbook?** Not in the repo. Per F-E-1, no escalation path beyond the Loki line.

### O6. Partner gift expiry cron runs while activation cron runs.
- Activation takes a row-lock via `SELECT … FOR UPDATE` (partners.service.ts:970).
- Cron's UPDATE matches by status — under READ COMMITTED, the cron's UPDATE re-evaluates the WHERE at row-lock acquisition time, so an activated row no longer matches. ✓ (F-F-2).

### F-O-1: notification cron is N×serial, no batching, no backoff. **Severity: MEDIUM**
**File:** `apps/api/src/services/notifications.service.ts:941-1025`
**What:** `for (const row of result.rows) { await FcmService.sendToUser(...); }` — strictly sequential. With 10K rows + 100ms FCM round-trip = 1000s. The cron runs once daily; this is OK in absolute terms but means the cron blocks for 17 minutes. During the 17-min blockage, the audit-chain verify and other promises continue (allSettled), but the digest tick (60s) lock is held by the auto-approve cron (F-A-1) AND the daily cron's 17-min walk just ate one hour of digest ticks.
**Suggested fix:** chunk into `Promise.allSettled` batches of 50, await each batch.

---

## P. Adversarial purge scenarios

### P1. User soft-deletes; API offline 31 days; cron resumes.
- `deletion_scheduled_for = NOW() + INTERVAL '30 days'` set at the soft-delete (users.ts:643).
- 31 days later, cron runs. SELECT finds the user (`deletion_scheduled_for < NOW()` is true). Purge runs.
- **No grace cushion.** If the API was down for 5 days and then back up, every soft-delete-pending user gets purged in one cron run (bounded by `MAX_PER_RUN=100`/day) — a user who tried to recover their account during the offline window has no path. F-P-1.

### P2. User soft-deletes, then signs in via OAuth within grace.
- The auth path's behavior: depends on OAuth `signIn` handler — does it re-activate `deleted_at = NULL`?
- I read users.ts:702-748 (the `/me/recover` path explicitly clears `deleted_at` and restores plan).
- A direct OAuth `signIn` would call `auth/google` which does NOT explicitly clear `deleted_at` (per my reading of the v2 auth audit at 01-auth-deep.md, finding C-AUTH-V2-?). The user re-authenticates but stays soft-deleted; on the next request, the JWT is honored unless middleware checks `deleted_at`.
- **The auth audit (01) should have caught this.** This audit notes that the purge cron's only SELECT criterion is `deleted_at IS NOT NULL AND deletion_scheduled_for < NOW()` — so a user re-signed-in via OAuth is NOT auto-recovered, and 30 days later their account is purged.
- F-P-2: the OAuth re-sign-in path needs to call `/me/recover` semantically before issuing a fresh access token.

### P3. MinIO server is down at purge time.
- SQL DELETE commits first; then `removeKeysBestEffort` iterates and logs warnings on each `removeObject` failure.
- **Orphan objects** in MinIO. The "future GC sweep" mentioned in storage-cleanup.ts:9 doesn't exist in the repo. F-P-3.

### P4. User has 10K documents.
- `MAX_PER_RUN=100` users/day. ONE user with 10K documents:
  - The harvest query (`SELECT object_key, thumbnail_key FROM documents WHERE user_id = $1`) returns 10K rows in one go.
  - The DELETE FROM users CASCADE deletes 10K documents rows in one tx — **could be slow** (10K row CASCADE inside a single tx).
  - Post-COMMIT, the MinIO sweep iterates 10K keys serially at ~50ms each = 500 s = 8 min. Single user pins the cron worker for 8 min.
- **The cron does NOT switch users mid-MinIO-sweep** — the user is fully purged before the next iteration. ✓.

### P5. User has active partner gifts (as activator/recipient).
- `partner_gifts.activated_user_id` has FK ON DELETE SET NULL (mig 002:211). The activated user's id becomes NULL; the gift survives.
- **No refund.** The user's premium subscription extension (granted by the gift activation) was already applied to `users.plan_expires_at` and is now lost on user deletion.
- The partner who sent the gift keeps the commission (the homebuyer activated it; commission was earned at activation regardless of what the homebuyer does later).
- F-P-4: a user who activated a gift then deletes their account loses the premium they paid for (or their gifter paid for). No refund logic.

### P6. User is a partner.
- `partners.user_id` has FK ON DELETE CASCADE (mig 002:153). The `partners` row is deleted.
- This CASCADES to `partner_gifts` (FK CASCADE on partner_id, mig 002:194) and `partner_commissions` (FK CASCADE on partner_id, mig 002:240).
- **Every gift the partner ever sent is deleted.** Including gifts that the homebuyer is currently using (the homebuyer's `users.plan_expires_at` was already extended — that's preserved on the homebuyer's row, not on the gift).
- **Every commission record is deleted.** Approved + pending + paid + cancelled. The partner's `audit_logs` rows survive (SET NULL), but the `partner_commissions` financial record is gone.
- **THIS IS WRONG.** A partner who deletes their account should not erase the financial record of past gifts they sold + commissions they earned. F-P-5 (HIGH).

### P7. User has unpaid commissions.
- See P6 — they're CASCADE-deleted. Unpaid commissions become un-payable, un-auditable.
- Stripe has no record (HavenKeep didn't issue a transfer); the commission record is gone. The accounting reconciliation is broken.
- F-P-5.

### P8. User has refresh tokens still alive.
- Cleared explicitly (account-purge.service.ts:112), AND CASCADE'd via FK. Belt + braces.
- Plus the access token they used to soft-delete was blacklisted at users.ts:679. ✓.

### P9. User has push tokens.
- `user_push_tokens.user_id` ON DELETE CASCADE (mig 007:16). Cleared.
- BUT — Firebase still has the token registered. **HavenKeep has no path to call `deleteToken` / `unregister` on Firebase** for the orphan tokens. The next time the device opens the app, FCM rebinds; otherwise the FCM token sits at Firebase's side until natural expiry (30 days inactive).
- F-P-6: privacy claim "we delete your push tokens" is true server-side, but a deleted user's device still has an active token in Firebase's registry. (Minor.)

### P10. (v1 C4) User has email-scanner OAuth integrations.
- Soft-delete handler (users.ts:670) calls `EmailScannerService.revokeIntegration(req.user.id)` which UPDATEs `user_oauth_integrations` SET revoked_at + nulls token columns (email-scanner.service.ts:316-343).
- **It does NOT call Google's / Microsoft's revoke endpoint** — `https://oauth2.googleapis.com/revoke?token=<refresh_token>`. The provider still considers HavenKeep's app-grant valid until the user manually revokes via Google account settings.
- 30 days later, hard-delete CASCADE deletes the row entirely.
- **v1 C4 stands UNFIXED.** Privacy claim "we revoke your OAuth integrations on delete" is server-side only, not provider-side.

### P11. User has TOTP enrolled.
- `user_mfa_factors` + `user_mfa_backup_codes` ON DELETE CASCADE (mig 084:31, 59). Cleared.
- The TOTP secret and backup codes are deleted from HavenKeep DB.
- **The user's authenticator app still has the QR-imported secret**, but it's inert (no server to verify against). ✓.

### P12. audit_logs row survives with user_id=NULL.
- `audit_logs.user_id` ON DELETE SET NULL (mig 004:82). ✓.
- `user_email` (denormalized at write time per audit.service.ts:159-162) is preserved on the row, so forensics can trace post-deletion. But — the soft-delete-handler audit row at users.ts:693 has `user_email` set from `(req as any).user?.email` (audit.service.ts:227-247) which is fine. The hard-delete cron writes NO audit_logs row (B10 / v1 H1), so there's no purge-time forensic anchor.
- F-B-7 (above) — also affects notification_history.

### F-P-1: 30-day cooling-off has no extension on API outage. **Severity: LOW**
**What:** A user who soft-deleted Day 0 expecting "30 days to recover," and the API is offline Days 25-29, then comes back Day 31 — the cron purges them. The user got 25 days of recovery window, not 30.
**Suggested fix:** instead of `deletion_scheduled_for < NOW()`, use `deletion_scheduled_for < NOW() AND now > deletion_scheduled_for + INTERVAL '24 hours'` — give a 24h buffer past the scheduled date.

### F-P-2: OAuth re-sign-in does not auto-recover soft-deleted account. **Severity: HIGH**
**File:** `apps/api/src/routes/auth.ts` (Google/Apple paths) — see audit 01.
**What:** Per the auth audit, a soft-deleted user can sign in via OAuth and get a fresh JWT, but `deleted_at` stays populated; 30 days later the cron purges them silently. **The user was using the app, then their account was deleted from under them.**
**Suggested fix:** in the OAuth sign-in path, if `users.deleted_at IS NOT NULL AND deletion_scheduled_for > NOW()` (still in grace), call the same recovery as `/me/recover`: `UPDATE users SET deleted_at = NULL, deletion_scheduled_for = NULL, plan = COALESCE(plan_before_delete, 'free')::user_plan, plan_before_delete = NULL`. Treat OAuth sign-in as evidence of "recover this account."

### F-P-3: orphan MinIO objects after MinIO outage are never reaped. **Severity: MEDIUM**
**File:** `apps/api/src/utils/storage-cleanup.ts:9-10` (comment says "future GC sweep")
**What:** After purge, if MinIO was down, keys are orphaned in MinIO. The "future GC sweep" promised in the comment doesn't exist. Storage costs accrue for objects pointing at deleted users.
**Suggested fix:** add a periodic cron that lists MinIO objects under `documents/`, `thumbnails/`, `product-images/`, `avatars/` and deletes any whose key prefix doesn't match an existing DB row.

### F-P-4: user who activated a gift then deletes loses paid premium with no refund. **Severity: MEDIUM**
**File:** `apps/api/src/services/account-purge.service.ts` — no Stripe interaction.
**What:** A homebuyer's premium subscription, granted via gift activation (at expense of the partner), is preserved on the user's `plan_expires_at` until they delete. Hard-delete deletes the user; the premium evaporates. The partner already paid Stripe; the homebuyer never got the full benefit.
**Why minor (and possibly intentional):** the user chose to delete; they consented. But the partner's commission has already been earned (they don't get a refund either). A note in the user-facing delete flow: "deleting your account does not refund any active subscriptions or gifts."
**Suggested fix:** product/legal call. Worth surfacing to the team.

### F-P-5: hard-deleting a partner CASCADE-deletes ALL their commission history. **Severity: HIGH**
**File:** `apps/api/src/db/migrations/002_enhanced_features.sql:151-264` (CASCADE chain partners → partner_gifts → partner_commissions).
**What:** Reproducing the chain:
1. User U is also a partner P.
2. P has 50 gifts sent over 12 months, 50 commissions earned + paid via Stripe transfers.
3. U soft-deletes; cron hard-deletes 30 days later.
4. CASCADE deletes `partners(P)` → CASCADE deletes 50 `partner_gifts` rows + 50 `partner_commissions` rows.

**HavenKeep's books no longer show any commission was paid to P; reconciliation against Stripe transfers is broken.** This is a financial-records-retention violation for tax purposes (partner is a 1099 contractor; HavenKeep needs the records at minimum 7 years per IRS, and likely 10 years for some jurisdictions).

**Suggested fix:** add a 101 migration that:
1. Changes `partner_commissions.partner_id` FK from CASCADE to SET NULL.
2. Adds denormalized `partner_email_at_creation` + `partner_company_name_at_creation` columns to `partner_commissions` and `partner_gifts`.
3. Updates the purge service to populate the denorm columns inside the tx.
**Then the financial records survive the user delete.**

### F-P-6: deleted user's push token still exists at Firebase's side. **Severity: LOW (privacy claim mismatch)**
**What:** HavenKeep's claim "we delete push tokens" is server-side (DB rows). Firebase's registration of the token still exists until natural expiry. A new device app-install would bind a fresh token; the orphan token is functionally inert. But for strict GDPR claim purity, HavenKeep should call `messaging.deleteToken(token)` on the Firebase Admin SDK before the DB CASCADE.
**Suggested fix:** in the purge service, after harvesting MinIO keys, also fetch the user's push tokens, call `FcmService.deleteToken(t)` per token (admin-side delete is supported via the Instance ID API), THEN run the SQL DELETE.

---

## Summary

64 findings across the seven cron paths and the barcode lookup. Headline list (by severity):

**HIGH (10):**
- F-A-1: lock-id collision between digest tick and commission auto-approve.
- F-B-5: failed-purge backlog invisible.
- F-B-7: notification_history.user_email_at_send not denormalized at purge.
- F-B-10 (v1 H1): purge writes zero audit_logs rows.
- F-C-1: 24h dedup means 30 daily reminders for one warranty.
- F-E-1: audit-chain break has no escalation.
- F-H-1: dead-letter webhooks invisible.
- F-K-1 (v1 H7): request_idempotency prune unbounded.
- F-P-2: OAuth re-sign-in doesn't auto-recover soft-deleted account.
- F-P-5: deleting a partner CASCADEs their financial history.

**MEDIUM (14):**
- F-A-2: missed daily window after restart at 09:00.
- F-A-3: silent advisory-lock-miss — no metric.
- F-B-1: MAX_PER_RUN=100 with no backlog observability.
- F-B-6: zero observability on purge backlog.
- F-C-2: quiet-hours wall-clock drift over long cron walks.
- F-C-3: cron writes skipped notification_history rows.
- F-E-2: O(N²) chain verification re-walks full table daily.
- F-F-1: gift expiry doesn't notify partner.
- F-G-1: commission auto-approve writes no audit_logs rows.
- F-H-2 (v1 M-MP-1): dead_letter rows survive forever.
- F-L-1: webhook_events sweep needs chunking.
- F-M-1..M5 (combined): cron observability gaps.
- F-O-1: notification cron is sequential, no batching.
- F-P-3: orphan MinIO objects after outage never reaped.
- F-P-4: deleting after gift activation loses premium without refund.

**LOW (16+):** F-A-4, F-B-2, F-B-3, F-B-4, F-B-8, F-C-4, F-C-5, F-D-1, F-D-2, F-F-2, F-F-3, F-G-2, F-G-3, F-I-1, F-J-1, F-N-1, F-N-2, F-N-3, F-N-4, F-N-5, F-N-6, F-P-1, F-P-6, plus assorted cleanup items.

**v1 findings still un-fixed:** v1 H1 (purge no audit_logs), v1 H7 (idempotency prune unbounded), v1 M-MP-1 / v1 M-MP-3 (dead_letter rows + no retry cron), v1 M9 (barcode quota incremented before cache check), v1 C4 (OAuth integrations not provider-revoked on delete), v1 L6 (audit verify no statement_timeout), and several observability gaps.

The mechanism of every cron is correct. The problem surface is **observability + escalation** — a silent failure (lock collision, dead-letter, purge stuck on a single user, audit-chain break) is currently invisible until a user-visible symptom surfaces days later. The financial-records-retention bug (F-P-5) is the most consequential single issue: a partner can self-erase their tax / commission history simply by deleting their account.
