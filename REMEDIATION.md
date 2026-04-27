# HavenKeep — Remediation Plan

Temporary file. Delete when every item is checked off.

Source: the Tier-C audit run on 2026-04-26. 36 findings, phased so user-visible breakage gets fixed first, contracts and correctness next, polish last. Every item has file:line citations so the work can be picked up cold.

Verification gate per CLAUDE.md Rule 5 — every change must end with all of these green for the apps it touched:
- `apps/api`: `npx tsc --noEmit` + `npm test`
- `apps/partner-dashboard`: `npm run build`
- `apps/mobile`: `flutter analyze` + `flutter test` + `flutter build apk --debug`
- Shared packages: lint + analyze via the consuming app's pipeline

---

## Phase 1 — Stop the bleeding (~2-3 days)

User-visible bugs and data corruption. After Phase 1: users can change their password, file warranty claims that mean something, receive push notifications, and admin numbers are honest.

### 1.1 — Fix password handling for long passwords (S1-C)
- **Files:** `apps/api/src/routes/users.ts` lines 285, 372, 378, 384, 436. `apps/api/src/routes/auth.ts:59` (the helper).
- **Change:** wrap every `bcrypt.compare(password, …)` and `bcrypt.hash(password, …)` in `users.ts` with `preHashForBcrypt(password)`, matching what `auth.ts` already does on register/login/reset. Export `preHashForBcrypt` from `auth.ts` if it isn't already.
- **Verify:** add a unit test that registers a user with an 80-byte password, then walks through change-password, change-email, and account-delete using the same password. All three must succeed.
- **Risk:** none — this brings buggy paths into line with already-working ones. No backfill needed; existing hashes were created via the buggy paths and will continue to verify (the bug is symmetric on the affected sites).

### 1.2 — Conform Dart claim status enum to the server (S1-A)
- **Files:** `packages/shared_models/lib/src/warranty_claim.dart:111-160`. Then every UI file that switches on `ClaimStatus` (grep for `ClaimStatus\.` in `apps/mobile/lib`).
- **Change:** rewrite the Dart enum to `filed | inReview | approved | denied | settled | closed`. Update `_byName` map keys to match server's snake_case (`filed`, `in_review`, `approved`, `denied`, `settled`, `closed`). Update `toJson` and the `case` arms in `displayName`. Search-and-replace UI references — most likely a switch in `apps/mobile/lib/features/warranty_claims/`.
- **Verify:** existing claim screens render without falling back to `pending`. Open a claim end-to-end on a real backend; the status value the API returns should appear verbatim in the app.
- **Risk:** medium. UI code may have hard-coded references to the old values. The Dart analyzer will catch missing cases in exhaustive switches but not string comparisons.

### 1.3 — Register FCM token with backend after permission grant (S1-B)
- **Files:** `apps/mobile/lib/core/services/push_notification_service.dart:107-133`.
- **Change:** the function fetches the token and drops it. There's no `_registerTokenWithBackend` in the file at all. Add a private method that POSTs the token to the API push-token endpoint (the same one `onTokenRefresh.listen` already uses — find that handler and extract the call into a shared private method, then call it from both `requestPermissionAndRegisterToken` and the refresh listener).
- **Verify:** install on a fresh device, grant push permission on first item, send a test push from the API, confirm it arrives.
- **Risk:** low — all the wire infrastructure exists; this is a missing call.

### 1.4 — Filter soft-deleted users + items in admin stats (S1-D, S2-J)
- **Files:** `apps/api/src/routes/admin.ts:105-118` (full stats), `apps/api/src/routes/admin.ts:185-199` (user-activity report).
- **Change:** every `FROM users` gets `WHERE deleted_at IS NULL`. Items don't have soft-delete (only `is_archived`) — leave the items count alone unless the desired metric is "non-archived items," in which case add `WHERE is_archived = FALSE` and update the metric name.
- **Verify:** soft-delete a test user, hit `/admin/stats/full`, confirm `total_users` decreases by 1.
- **Risk:** none.

### 1.5 — Fix reconciliation decimal-to-float drift (S1-E)
- **Files:** `apps/api/src/services/reconciliation.service.ts:63-68` (and any sibling `parseFloat()` calls in the same service).
- **Change:** swap `parseFloat(row.x)` for `decimalToCents(row.x)` (the helper already exists in the codebase — grep for it). Compare integers, not floats. Where the cached value is a decimal string, normalize both sides before equality.
- **Verify:** unit test: store $19.99 in one side, $19.99 in the other, recompute, assert no drift recorded. Run reconciliation on a seeded DB twice; the second run should detect zero drift.
- **Risk:** low — converting on read is a localized change.

### 1.6 — Add partner status field to Dart model (S1-F)
- **Files:** `packages/shared_models/lib/src/partner.dart`. Then `apps/partner-dashboard/src/app/admin/partners/[id]/page.tsx` and any partner detail UI on web.
- **Change:** add `final PartnerStatus status` field to `Partner`, deserialize from `json['status']`. Add an enum `PartnerStatus { pending, active, rejected }` mirroring migration 071. Keep `isActive` for now (don't break callers) but mark in code comments that `status` is the source of truth. On the dashboard, render status alongside / instead of "active/inactive."
- **Verify:** create a partner record with `status='pending'`, fetch it on the dashboard, confirm UI shows "Pending" not "Inactive."
- **Risk:** low if `isActive` is kept; medium if removed (don't remove in this phase — that's a Phase 3 cleanup).

### 1.7 — Prevent push token poisoning (S1-I)
- **Files:** `apps/api/src/routes/users.ts:126-138` (push-token endpoint).
- **Change:** before the upsert, run `SELECT user_id FROM user_push_tokens WHERE fcm_token = $1`. If a row exists for a different user, either (a) delete it (the device has switched accounts — legitimate), or (b) refuse with 409. Recommended: delete it, since users do log into different accounts on the same device. Document the reasoning in a code comment.
- **Verify:** unit test that registers token T for user A, then for user B — A's row should be removed and B's created.
- **Risk:** low.

### 1.8 — Webhook dead-letter atomicity (S1-G)
- **Files:** `apps/api/src/routes/webhooks.ts:73-117`.
- **Change:** wrap the claim/upsert in `BEGIN ISOLATION LEVEL SERIALIZABLE` (or use `SELECT … FOR UPDATE` on the existing row before deciding the new status). Move the threshold logic into the SQL: `status = CASE WHEN attempts + 1 >= $MAX THEN 'dead_letter' ELSE 'pending' END` is fine *if* the row is locked first.
- **Verify:** integration test that fires the same `event_id` twice in parallel from two clients, asserts only one transitions to `dead_letter`.
- **Risk:** medium — txn isolation changes can surface latent races in adjacent code.

### 1.9 — Validate Apple Sign-In nonce (S1-H)
- **Files:** `apps/api/src/routes/auth.ts:978-1170` (Apple endpoint). Mobile side: wherever the Apple Sign-In flow lives (`apps/mobile/lib/features/onboarding/` or similar).
- **Change:** server side, require `nonce` in the request body, hash it with SHA-256, and verify it matches the `nonce` claim in the decoded ID token. Reject if missing or mismatched. Mobile side, generate a random nonce per sign-in attempt, pass the SHA-256 hash to `SignInWithApple.getCredential(nonce: …)`, and POST the *unhashed* nonce in the body. Apple's SDK expects the hashed nonce as input and returns the unhashed one in the credential — confirm with current `sign_in_with_apple` package docs before coding.
- **Verify:** sign in with Apple end-to-end on iOS device. Then attempt a replay (capture the request, resend) — server must reject the second attempt because the nonce has been consumed (store nonces server-side with a short TTL, e.g. 5 minutes in Redis).
- **Risk:** medium — touches both ends. Test path: sign-in success on a fresh device, then a replay attempt. If we don't have Redis available for nonce storage, fall back to a short-lived `apple_sign_in_nonces` table with a cleanup job.

### 1.10 — Generate Idempotency-Key in offline queue (S2-E)
- **Files:** `apps/mobile/lib/core/services/offline_sync_service.dart:382-413`. The repository methods called from there (e.g. `apps/mobile/lib/core/services/items_repository.dart`).
- **Change:** at enqueue time, generate a UUID (`const Uuid().v4()`) and store it on the `OfflineQueueEntry`. Pass it through every repo method that wraps a mutating API call. The Dart `client.dart` already injects the header at line 467-469 — just thread the value through.
- **Verify:** trigger a queued create with the network off, then turn it on. Confirm the `Idempotency-Key` header is present in the request log.
- **Risk:** low — pairs with 1.11.

### 1.11 — Honor Idempotency-Key on warranty claims and purchases (S2-D)
- **Files:** `apps/api/src/routes/warranty-claims.ts`, `apps/api/src/routes/warranty-purchases.ts`. Idempotency machinery: search the API for an existing pattern (other routes already implement it per CLAUDE.md). Most likely there's an `idempotency` middleware or a `requestCache` table.
- **Change:** apply the existing pattern to both routes. If no shared middleware exists, build a minimal one: store `(user_id, idempotency_key) → (status, response_body)` with a 24h TTL. On a repeat key, return the cached response.
- **Verify:** integration test that POSTs the same claim with the same key twice — asserts only one row created and identical responses.
- **Risk:** medium — must not introduce a new race. Use `INSERT … ON CONFLICT DO NOTHING RETURNING …` patterns.

### 1.12 — Acknowledge synced offline-queue entries durably (S2-C)
- **Files:** `apps/mobile/lib/core/services/offline_sync_service.dart:222-327`.
- **Change:** before sending the request, write the entry as `status='in_flight'` with the generated idempotency key. After the server returns, mark `synced` then `clearSyncedActions`. On startup, treat `in_flight` entries as resumable: re-send with the same idempotency key (which is now safe per 1.10 + 1.11). Add a hard cap: drop `in_flight` entries older than 7 days.
- **Verify:** simulate a crash mid-flight (kill the process between server response and ack). On restart, the entry should re-send and the server should return the cached response without duplicating the row.
- **Risk:** medium — depends on 1.10 and 1.11 being shipped first.

---

## Phase 2 — Correctness & contracts (~3-4 days)

Silent corruption, timezone bugs, security defense-in-depth, contract drift. After Phase 2: timestamps are consistent across timezones, the dashboard enforces roles server-side, audit logs verify, partner data stays scoped.

### 2.1 — Compute warranty status in UTC on mobile (S2-A)
- **Files:** `packages/shared_models/lib/src/item.dart:227-247`.
- **Change:** replace `final today = DateTime(now.year, now.month, now.day)` with `final today = DateTime.utc(now.toUtc().year, now.toUtc().month, now.toUtc().day)`. Compare against `warrantyEndDate.toUtc()`.
- **Verify:** unit test with `warrantyEndDate = 2026-01-01T00:00:00Z` and the device clock at `2025-12-31T20:00:00-08:00`. The status must be `active`, not `expired`.
- **Risk:** low.

### 2.2 — Compute reminder windows in UTC on server (S2-B)
- **Files:** `apps/api/src/services/notifications.service.ts:752-753`.
- **Change:** swap `CURRENT_DATE` for `(NOW() AT TIME ZONE 'UTC')::date`. Same transformation in any sibling query in this file that uses `CURRENT_DATE` (grep the file).
- **Verify:** integration test that sets a server timezone to `America/Los_Angeles` (`SET timezone='America/Los_Angeles'` in a test session), creates a warranty expiring at the day-boundary, and verifies the reminder fires on the correct UTC day.
- **Risk:** low.

### 2.3 — Service-level invariant check on warranty claim amounts (S2-F)
- **Files:** `apps/api/src/services/warranty-claims.service.ts:325-462`.
- **Change:** before the UPDATE, compute `effective.repairCost` and `effective.amountSaved` (using current row + patch), throw `AppError('amount_saved cannot exceed repair_cost', 400)` if violated. Don't remove the migration-033 CHECK; it's defense in depth.
- **Verify:** unit test: PATCH a claim with `amount_saved > repair_cost`, expect 400 not 500.
- **Risk:** none.

### 2.4 — Wipe SQLCipher key from Dart heap (S2-G)
- **Files:** `apps/mobile/lib/core/database/database.dart:305-309`.
- **Change:** Dart's GC won't zero memory, but we can minimize lifetime. Convert the `Uint8List` to the hex string immediately, fill the original bytes with zeros (`for (var i = 0; i < bytes.length; i++) bytes[i] = 0`), and don't keep a long-lived reference to the hex string either (pass it directly to the SQLCipher open call). Document that this is best-effort given Dart's memory model.
- **Verify:** code review only — there's no portable way to assert heap contents.
- **Risk:** low.

### 2.5 — Strict allowlist on push-notification routes (S2-H)
- **Files:** `apps/mobile/lib/core/services/push_notification_service.dart:191-192`.
- **Change:** replace the `startsWith` allowlist with first-segment match: `final segments = Uri.parse(route).pathSegments.where((s) => s.isNotEmpty).toList(); if (segments.isEmpty || !_kAllowedRouteSegments.contains(segments.first)) return;`.
- **Verify:** unit test for `route: '/items/../settings/delete-account'` — must reject.
- **Risk:** low.

### 2.6 — Reconciliation excludes archived items (S2-I)
- **Files:** `apps/api/src/services/reconciliation.service.ts:41-56`.
- **Change:** add `JOIN items i ON i.id = wc.item_id WHERE i.is_archived = FALSE` (or LEFT JOIN if claims can survive item deletion). If FK is `ON DELETE CASCADE`, claims for deleted items are already gone — only the archive case matters.
- **Verify:** seed an archived item with a claim, run reconciliation, assert the claim's amount is excluded.
- **Risk:** low. Pairs with 1.5.

### 2.7 — Audit-log hash chain verification endpoint + scheduled job (S2-K)
- **Files:** `apps/api/src/services/audit.service.ts:230` (the existing `verifyChain()` method). Add a route: `apps/api/src/routes/admin.ts` — new `GET /admin/audit/verify`. Also schedule it: hook into existing cron (look in `apps/api/src/index.ts` or similar bootstrapping for `setInterval`/`node-cron` patterns).
- **Change:** the route gates with `requireAdmin`, calls `AuditService.verifyChain()`, returns `{ ok: bool, lastVerifiedAt, brokenAt? }`. The scheduled job runs daily, logs (and pages, if alerting exists) on failure.
- **Verify:** call the route on a clean DB → ok. Manually corrupt one row's hash, call again → must return `{ ok: false, brokenAt: <id> }`.
- **Risk:** low.

### 2.8 — Seed remaining 19 category default repair costs (S2-L)
- **Files:** new migration `apps/api/src/db/migrations/076_seed_remaining_category_defaults.sql`. Reference: `074_category_defaults_repair_cost.sql` and the full category list in `packages/shared_models/lib/src/enums.dart`.
- **Change:** INSERT defaults for the 19 unseeded categories. Use sensible mid-market estimates; document the source in a comment.
- **Verify:** `SELECT COUNT(*) FROM category_defaults WHERE estimated_repair_cost IS NOT NULL` matches the total category count.
- **Risk:** low — additive only.

### 2.9 — Email scanner: enclose lock in transaction (S2-M)
- **Files:** `apps/api/src/services/email-scanner.service.ts:1388` (and the surrounding scan-claim function).
- **Change:** wrap the `SELECT … FOR UPDATE` and downstream INSERTs in an explicit `BEGIN`/`COMMIT` using a transaction client. Rollback on any failure.
- **Verify:** integration test that runs two scan workers against the same Gmail message; only one should successfully claim it.
- **Risk:** medium — concurrency tests are flaky; use a deterministic harness with explicit transaction barriers.

### 2.10 — CSRF check on partner-dashboard logout (S2-N)
- **Files:** `apps/partner-dashboard/src/app/api/auth/logout/route.ts:21-24`. Reference pattern in the same project: any other mutation route that uses `csrfTokenOk()`.
- **Change:** add `if (!csrfTokenOk(request)) return new Response('forbidden', { status: 403 })` at the top.
- **Verify:** logout request without the CSRF header gets 403.
- **Risk:** none.

### 2.11 — Server-side role gates on partner-dashboard layouts (S2-O)
- **Files:** `apps/partner-dashboard/src/app/dashboard/layout.tsx:1-14`. Search for `await requirePartner()` to see how other layouts call it.
- **Change:** convert layout to async, add `await requirePartner()` at the top. Repeat for any other dashboard subtree layouts that don't have it. Same for admin: `apps/partner-dashboard/src/app/admin/layout.tsx` should call `await requireAdmin()`.
- **Verify:** signed-in non-partner user requests `/dashboard/*` — must redirect to login or 403, not render briefly.
- **Risk:** low.

### 2.12 — Mask Stripe account ID in admin UI (S2-P)
- **Files:** `apps/partner-dashboard/src/app/admin/partners/[id]/page.tsx:149-151`.
- **Change:** render only the last 8 chars: `acct_••••${stripeAccountId.slice(-8)}`. If the full ID is needed for support workflows, add a "Copy full ID" button gated by a confirm modal — but keep the default view masked.
- **Verify:** open a partner detail page; no full `acct_…` string in DOM.
- **Risk:** none.

### 2.13 — Riverpod itemDetailProvider becomes autoDispose (S2-Q)
- **Files:** `apps/mobile/lib/core/providers/items_provider.dart:287-290`.
- **Change:** `final itemDetailProvider = FutureProvider.family.autoDispose<Item, String>((ref, id) async { … })`.
- **Verify:** open and close 20 item-detail screens, confirm the provider count drops to baseline. Use `flutter test` if the project has a Riverpod-cache assertion helper; otherwise code review.
- **Risk:** low. Confirm no widget *outside* the detail screen reads the same provider — that would re-create the entry.

### 2.14 — Money formatting respects device locale (S2-R)
- **Files:** `apps/mobile/lib/core/utils/money_formatter.dart:16-17, 19-20`.
- **Change:** accept a `Locale` parameter (or read `Localizations.localeOf(context)` at call sites that have one). Default to `en_US` only when the locale is null. Pass through to `NumberFormat.currency(locale: locale.toString())`.
- **Verify:** test with `Locale('fr', 'FR')` — output uses comma decimal and space thousands.
- **Risk:** low. Currency *symbol* may also need to follow locale — confirm product intent (always USD vs match device).

### 2.15 — Single-flight refresh in partner-dashboard API client (S2-S)
- **Files:** `apps/partner-dashboard/src/lib/api.ts:95-126`.
- **Change:** wrap the refresh call in a module-scoped `Promise<void> | null` variable. Concurrent 401s await the same promise. Clear the promise on resolve/reject.
- **Verify:** the existing `refresh-race.test.ts` should be extended to fire 5 concurrent 401s and assert only one POST to `/auth/refresh`.
- **Risk:** medium — async state in a singleton is bug-prone. Use the existing test file as a regression harness.

### 2.16 — Mobile pagination contract: read keyset cursors (S2-T)
- **Files:** `apps/mobile/lib/core/services/warranty_claims_repository.dart:24` and any repo that calls a paginated route. The API envelope: `apps/api/src/routes/items.ts:359-366`.
- **Change:** read `data['meta']?['pagination']?['next_cursor']` and surface it on the repo result. Update list screens to pass the cursor on the next fetch. If the repo always pulls the full set today, document it and skip until pagination becomes load-bearing.
- **Verify:** integration test against a seeded set of 50 items with page size 20 — confirm cursor walks through all three pages.
- **Risk:** medium — UI change cascades into list screens with infinite-scroll affordances.

---

## Phase 3 — Polish & defense-in-depth (~1-2 days)

Tests, logs, dead deps, defense in depth. After Phase 3: regressions on the Phase 1 fixes are caught by tests, telemetry surfaces drift early, the codebase is Rule-1/3 spotless again.

### 3.1 — Use cents on partner analytics commission display (S3-A)
- **Files:** `apps/api/src/services/partners.service.ts:1148-1150`.
- **Change:** swap `parseFloat()` for `decimalToCents()`, format for display only at the response edge.
- **Verify:** sum 100 commissions of $0.07 each — must render as $7.00, not $6.999999.

### 3.2 — Pin a constant-time floor on forgot-password timing (S3-B)
- **Files:** `apps/api/src/routes/auth.ts:621-689`.
- **Change:** the floor exists; add a unit test that asserts response time ≥ floor for both "user exists" and "user does not exist" branches. Add a comment referencing Ch01-F017 so a future refactor can't regress it.

### 3.3 — Test that JWT `alg: none` is rejected (S3-C)
- **Files:** new test in `apps/api/src/__tests__/auth.test.ts` or similar.
- **Change:** craft a JWT with header `{"alg":"none"}` and assert the Apple and Google sign-in endpoints both 401.

### 3.4 — Wire `registerUnknownEnumReporter` (S3-D)
- **Files:** `apps/mobile/lib/main.dart:32-170`. Reporter API: `packages/shared_models`.
- **Change:** after logging service init, call `registerUnknownEnumReporter((enumName, value, fallback) => LoggingService.warn('enum_drift', { enumName, value, fallback }))`. If Crashlytics is wired later, swap to a Crashlytics non-fatal recordError.
- **Verify:** trigger a known drift (manually return a fake enum from a mock API in dev) — must produce a log line.

### 3.5 — Sanitize console.error payloads in partner-dashboard (S3-E)
- **Files:** the 6 dashboard files identified by the audit (search `console.error`). Recommended fix: a small `logError(label, err)` helper that strips stack traces and known sensitive keys (`token`, `password`, `Authorization`, `cookie`).
- **Change:** replace each `console.error('msg', err)` with `logError('msg', err)`.

### 3.6 — Bootstrap partial-state guard in migration runner (S3-F)
- **Files:** `apps/api/src/db/migrations/run-migration.ts:55-80`.
- **Change:** instead of "users + items + partners exist => base done," check the `schema_version` row introduced in migration 045. If the row is missing OR doesn't match, treat the schema as incomplete and replay schema.sql before applying numbered migrations.
- **Verify:** drop the schema_version row, re-run migrations on an otherwise-bootstrapped DB; runner must replay schema.sql safely (idempotent CREATEs).

### 3.7 — Bound partner-analytics date range (S3-G)
- **Files:** `apps/api/src/routes/partners.ts:433-454`.
- **Change:** Joi/zod validator: `endDate - startDate <= 365 days`, default to last 90 days when omitted. Add `LIMIT 10000` to the underlying query as a hard ceiling.
- **Verify:** request with a 130-year window — 400.

### 3.8 — Replace `any` casts in partner-dashboard with response types (S3-H)
- **Files:** spread across `apps/partner-dashboard/src/app/admin/**/*.tsx` (the audit identified ~15 sites; grep for `as any`).
- **Change:** define shared response interfaces (one per API resource) in `apps/partner-dashboard/src/lib/api-types.ts`. Cast at the API-client boundary, not at the component.
- **Verify:** `npm run build` passes. Ideally `tsc --noEmit` with `--strict` flags any remaining `any`.

### 3.9 — Drop unused `date-fns` from partner-dashboard (S3-I)
- **Files:** `apps/partner-dashboard/package.json`.
- **Change:** `npm ls date-fns` first to confirm it's not transitive-required. If clean, `npm uninstall date-fns`. Re-build.

### 3.10 — Filter notifications for archived items (S3-J)
- **Files:** `apps/api/src/services/notifications.service.ts:146-155`.
- **Change:** LEFT JOIN items, add `(nh.item_id IS NULL OR i.is_archived = FALSE)` to the WHERE clause.
- **Verify:** archive an item, hit the notifications list, the related notification disappears.

### 3.11 — Validate deep-link code format (S3-K)
- **Files:** `apps/mobile/lib/core/services/deep_link_service.dart:96-127`.
- **Change:** `if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(code)) return null;` before returning the route.
- **Verify:** unit test for `/gift/../../admin` returns null.

### 3.12 — Regression tests for every Phase 1 fix
- Add tests for each S1 finding even if it required manual verification:
  - 1.1 long-password user can change password/email/delete
  - 1.2 server "filed" status renders verbatim in tests/widget
  - 1.3 push token POST happens on permission grant
  - 1.4 admin stats exclude soft-deleted users
  - 1.5 reconciliation: zero drift after a pass
  - 1.6 partner status field is read on dashboard
  - 1.7 push token uniqueness enforced
  - 1.8 webhook concurrent-claim test
  - 1.9 Apple nonce replay rejected
  - 1.10/1.11/1.12 idempotency end-to-end test

---

## Sequencing rules

- 1.10, 1.11, 1.12 are a unit — ship them together. Idempotency without the queue ack is meaningless; the queue ack without idempotency duplicates writes.
- 1.5 and 2.6 are paired — reconciliation needs both float-drift and archived-filter fixes to produce honest numbers.
- 2.1 and 2.2 are paired — fix client and server timezone in the same PR so behavior across the boundary is consistent.
- 1.6 (Dart partner status) blocks any partner-dashboard UI work that depends on the new field; ship 1.6 first.
- Phase 3 starts only after Phase 1 + 2 are merged and verified — its job is to harden completed work.

## Definition of done for the whole plan

- Every checkbox below ticked.
- All four verification gates green on the affected apps.
- This file deleted from the repo.

```
Phase 1
[x] 1.1   long-password lockout
[x] 1.2   claim status enum
[x] 1.3   FCM registration
[x] 1.4   admin soft-delete filters
[x] 1.5   reconciliation float drift
[x] 1.6   partner status field
[x] 1.7   push token poisoning
[x] 1.8   webhook dead-letter race
[x] 1.9   Apple nonce
[x] 1.10  idempotency key generation
[x] 1.11  idempotency key honored server-side
[x] 1.12  durable queue ack

Phase 2
[x] 2.1   warranty status UTC (mobile)
[x] 2.2   reminder window UTC (server)
[x] 2.3   claim amount service-level invariant
[x] 2.4   sqlcipher key wipe
[x] 2.5   push route allowlist
[x] 2.6   reconciliation archived filter
[x] 2.7   audit hash-chain verification + cron
[x] 2.8   seed remaining category defaults
[x] 2.9   email scanner txn boundary
[x] 2.10  dashboard logout CSRF
[x] 2.11  dashboard layout role gates
[x] 2.12  Stripe account masking
[x] 2.13  itemDetailProvider autoDispose
[x] 2.14  money locale-aware
[x] 2.15  single-flight refresh
[x] 2.16  mobile keyset pagination

Phase 3
[ ] 3.1   partner analytics cents
[ ] 3.2   forgot-password constant-time test
[ ] 3.3   JWT alg:none rejection test
[ ] 3.4   enum drift reporter wired
[ ] 3.5   dashboard error sanitizer
[ ] 3.6   migration runner partial-state guard
[ ] 3.7   partner analytics date bound
[ ] 3.8   dashboard `any` cleanup
[ ] 3.9   drop date-fns
[ ] 3.10  notifications filter archived
[ ] 3.11  deep-link code regex
[ ] 3.12  Phase-1 regression tests
```
