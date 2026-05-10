# Audit 04 — Mobile Sync, Offline-First, Security/Storage

**Scope:** offline queue, SQLCipher DB, secure storage, biometric lock, ApiClient, conflict resolver, shared_models enums.
**Date:** 2026-05-10
**Severity scale:** Critical (data loss / silent sign-out / pinning bypass) · High (race / wrong-subclass mapping / leaked sensitive) · Medium (UX bug / partial feature / drift) · Low (cosmetic).

---

## Critical

### C-MS-1 — TLS pinning is documented in dartdoc but never wired up

**File:** `packages/api_client/lib/src/client.dart:202-217`, `apps/mobile/lib/main.dart:110`, `apps/mobile/.env.staging`

The class-level dartdoc on `ApiClient` (`client.dart:202-217`) walks through how a release build is supposed to construct an `IOClient` backed by an SPKI-pinned `SecurityContext`, but the constructor at `client.dart:252-277` is the only construction point and the bootstrap at `main.dart:110` calls it as `ApiClient(baseUrl: config.apiBaseUrl)` — no `httpClient:` argument. The default `http.Client()` (line 257) uses the platform trust store, so any device with a custom CA installed (corporate MDM, attacker-installed root, debug proxies in production) can MITM every request, including `/auth/refresh` (refresh-token theft) and the OAuth endpoints. There is no `TLS_PIN_*` / `SPKI_*` value in any of the `.env.*` files either, so the pin isn't even configured to wire in. The audit prompt asks four sub-questions ("debug-skip / loaded from .env / badCertificateCallback returns false / backup pin"); none of them apply because there is no pinning at all.

**Action:** Either (a) implement the pinned client described in the dartdoc, gate it on `kReleaseMode` so debug builds keep working against local API, load primary + backup SPKI hashes from `.env.bundled`, and enforce in `badCertificateCallback` (return `false` on mismatch — never `true` with a log); or (b) delete the misleading dartdoc so the next reader doesn't believe pinning is in place.

### C-MS-2 — `refreshAccessToken` clears tokens on ANY non-200 response, defeating the H-B9 transient-error guard

**File:** `packages/api_client/lib/src/client.dart:457-488`

The H-B9 fix in `restoreSession` (lines 331-342) is the right idea — distinguish `ApiAuthRequiredException` (refresh genuinely rejected) from transport / 5xx (transient) and only clear tokens on the former. But `refreshAccessToken` itself collapses every non-200 response into the same `ApiAuthRequiredException` AND calls `clearTokens()` BEFORE it throws (`client.dart:480-488`):

```dart
} else {
  // Refresh failed — force sign out
  await clearTokens();                          // <-- unconditional wipe
  const error = ApiAuthRequiredException(401, 'Session expired. Please sign in again.');
  _refreshCompleter!.completeError(error);
  throw error;
}
```

So a 502 from Caddy / a 503 from a deploying API / a 500 from a flaky middleware will (1) wipe the access + refresh tokens from the keychain, (2) emit `signedOut` on the auth stream, (3) throw what looks like a credential failure. The `restoreSession` catch block can't tell that this was transient — by the time it sees `ApiAuthRequiredException`, the tokens are already gone. Same issue inside `_withAutoRefresh` at line 549-562: a 5xx on the refresh during a normal in-session API call signs the user out mid-use.

The `client.dart:481` comment ("Refresh failed — force sign out") is the bug talking — the H-B9 contract says refresh is only "failed" when the refresh credential itself is rejected (typically 401 on `/auth/refresh`).

**Action:** Branch on `response.statusCode` — 401/403 = `clearTokens` + `ApiAuthRequiredException`; 5xx = `ApiServerException` (do not clear tokens); other 4xx = throw without clearing. Update both call sites in `restoreSession` (`client.dart:336-342`, `355-361`) and `_withAutoRefresh` (`client.dart:556-562`) to keep the existing transient-vs-rejected branching but trust that refresh now reflects reality.

### C-MS-3 — 7-day stale-eviction wipes FAILED queue entries, erasing the user's "lost write" record

**File:** `apps/mobile/lib/core/services/offline_sync_service.dart:255-260`, `apps/mobile/lib/core/database/database.dart:188-189`

`syncPendingChanges` calls `_db.removeEntriesOlderThan(staleCutoff)` at the top of every run. The implementation (`database.dart:188-189`) is `(delete(offlineQueue)..where((t) => t.createdAt.isSmallerThanValue(cutoff))).go()` — it does NOT filter on `status`. A row in `failed` state older than 7 days is silently deleted, meaning the user's failed-write banner / "review failed syncs" UI loses its evidence and the user has no way to know a write was dropped (the in-memory state was already updated optimistically when the queue entry was created).

The audit prompt explicitly calls this out as a data-loss concern. The contract should be: pending/in_flight aged out → maybe retry / drop. Failed → keep until the user dismisses, OR keep for a much longer window with a bigger budget.

**Action:** `removeEntriesOlderThan` should add `..where((t) => t.status.equals('pending') | t.status.equals('in_flight'))`. Failed rows should require an explicit user dismiss (or a separate, longer cap such as 90 days).

### C-MS-4 — Per-user DB lives in iCloud-backed Documents directory while its key is device-bound; restore corrupts the user

**File:** `apps/mobile/lib/core/database/database.dart:249-252`, `apps/mobile/lib/core/services/secure_storage_service.dart:37-44`

`resolveDatabaseFile` puts the SQLCipher file under `getApplicationDocumentsDirectory()`. On iOS this directory is included in iCloud / iTunes backups by default (no `NSURLIsExcludedFromBackupKey`). The DB encryption key is stored in `_deviceBoundStorage` with `KeychainAccessibility.first_unlock_this_device`, which is intentionally NOT iCloud-replicable (S-HI-06 — correct security choice).

When a user restores their phone from iCloud onto a new device:
1. The encrypted SQLite file lands in Documents on the new device.
2. The keychain key does NOT come along (device-bound).
3. `getOrCreateDbEncryptionKey` (`secure_storage_service.dart:141-162`) sees no existing key → generates a fresh one.
4. `_openConnection` runs `PRAGMA key = "x'<new-random-bytes>'"` against the OLD-encrypted file → SQLCipher returns SQLITE_NOTADB / "file is not a database".
5. There is no fallback — the next operation hits a `SqliteException` and the whole local-data path crashes. The offline queue / sync conflicts are inaccessible.

There is no detection of the "wrong key" failure mode anywhere (`_openConnection` at `database.dart:286-310` only checks that SQLCipher is linked, not that the key actually decrypts). The user sees a perma-broken app state.

**Action:** Two changes — (a) move the DB file to `getApplicationSupportDirectory()` AND set `NSURLIsExcludedFromBackupKey` so iCloud doesn't carry forward a file we know we can't decrypt on a new device; (b) wrap the first SELECT after `PRAGMA key` (e.g. `PRAGMA cipher_version` is already there — also do `PRAGMA schema_version`) in a try/catch so a wrong-key open is detected → delete the file → recreate with the new key. The local cache loss is acceptable because the server has the canonical data; the perma-corrupt state is not.

### C-MS-5 — `_parkUpdateConflict` losing the local edit when its preflight `getItemById` fails

**File:** `apps/mobile/lib/core/services/offline_sync_service.dart:460-493`

Flow on a 409 from a queued `update_item`:

1. `_processEntry` calls `updateItem` → `ApiConflictException` thrown (`offline_sync_service.dart:430`).
2. `_parkUpdateConflict(item)` runs.
3. It calls `getItemById(localItem.id)` (line 463). If the item was deleted on another device, this returns 404 → `ApiNotFoundException`. If the user's connectivity flaps mid-park, this throws `ApiNetworkException`.
4. Either failure hits the `rethrow` at line 491 — control returns up to `_processEntry`, which propagates the exception out to the outer switch in `syncPendingChanges` (`offline_sync_service.dart:286-330`).
5. `ApiNotFoundException` falls into the "non-retriable client error" case at line 307-313 → `markActionFailed(_kMaxRetries)`. The conflict is NEVER written to `sync_conflicts`. The user's edit is silently lost — neither replayed nor surfaced for resolution.

The same outcome happens if `recordConflict` itself throws (`db.recordConflict` is wrapped in the same try/catch at line 461-492). The atomicity question the audit asks ("can a 409 lose the local edit if the queue row is removed before the conflict row is written") has the answer "yes, via the preflight 404 path".

**Action:** `_parkUpdateConflict` should park the conflict FIRST (using a synthetic server snapshot e.g. `{ "tombstone": true }` if the preflight failed), THEN attempt the preflight as an enrichment. Alternatively wrap park + queue-mark in a transaction so partial failure rolls both back and the entry retries. Either way, a 404/network during park must not transition the queue row to `failed` while leaving no conflict record.

### C-MS-6 — Vast majority of `enum.fromJson` factories silently coerce unknown values without going through the unknown-enum funnel

**File:** `packages/shared_models/lib/src/enums.dart` (entire file), `email_scan.dart:94-96`, `warranty_purchase.dart:173-175`, `partner.dart:265-267`, `partner_gift.dart`, `partner_commission.dart` (×4), `maintenance.dart:16-18`

The audit prompt asks: "Walk every fromJson … note which ones DO log unknown values (via _byName + logUnknownEnumValue) and which ones use `firstWhere(orElse:)` without logging." Result:

**Logs unknown values via `logUnknownEnumValue` (correct):**
- `ClaimStatus.fromJson` — `warranty_claim.dart:132-145`
- `PartnerStatus.fromJson` — `partner.dart:233-242`

**Silently coerces, no telemetry (incorrect):**
- All 22 enums in `enums.dart`: `ItemCategory`, `ItemRoom`, `WarrantyType`, `WarrantyStatus`, `AuthProvider`, `UserPlan`, `HomeType`, `DocumentType`, `NotificationType`, `NotificationAction`, `PartnerType`, `ReferralSource`, `ConversionType`, `ConversionStatus`, `ItemAddedVia`, `OfflineAction`, `OfflineStatus` — each uses `Values.firstWhere(orElse:)` with no `logUnknownEnumValue` call.
- `EmailScanStatus` (`email_scan.dart:94-96`)
- `WarrantyPurchaseStatus` (`warranty_purchase.dart:173-175`) — fallback is `active` which is **dangerous** because mig 098 added a `cancelling` enum value the mobile model doesn't know about; the user mid-cancel sees the warranty status flip to `active`.
- `PartnerSubscriptionTier` (`partner.dart:265-267`)
- `PartnerGiftStatus` (`partner_gift.dart`)
- `PartnerCommissionType`, `PartnerCommissionStatus`, `PartnerCommissionReferenceType`, `PartnerCommissionPayoutMethod` (`partner_commission.dart`)
- `MaintenanceDifficulty` (`maintenance.dart:16-18`)
- `MaintenanceSummaryState.fromJson` (`maintenance.dart:308-323`) — switch with `default:` returns `noItems` silently

`registerUnknownEnumReporter` is wired in `main.dart:97-107` to forward to Crashlytics. So when an enum DOES log, the team gets the breadcrumb. But for ~30 of the 32 enums, server-side enum drift is invisible to the mobile observability pipeline. The `cancelling` case for `WarrantyPurchaseStatus` is the immediate landmine: a user clicking Cancel sees their UI tell them the warranty is still Active until they manually pull-to-refresh post-server-finalization.

**Action:** Add `cancelling` to `WarrantyPurchaseStatus` and re-run the gates as a code fix; then route every fromJson through the `_byName + logUnknownEnumValue` shape used by `ClaimStatus` / `PartnerStatus`. The fallback in each case should pick the most-conservative value (e.g. `WarrantyPurchaseStatus.cancelling` should fall back to `active` only AFTER the team is aware via Crashlytics). This is mechanical work but necessary — the funnel is the team's only signal that a server change drifted before the mobile binary ships.

---

## High

### H-MS-1 — `redactSensitive` does not cover refresh tokens, OAuth state, activation codes, or Apple nonces

**File:** `packages/api_client/lib/src/client.dart:182-194`

Current regex set:
1. `Bearer\s+[^\s"]+` → strips Bearer-prefixed access tokens.
2. `eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+` → strips JWT-shaped tokens.

Not covered:
- **Refresh tokens** — opaque hex (server-side they're 64-byte random). They ride in JSON request bodies. If a `_log` line ever quotes a body (e.g. `"Refresh failed: $body"`), the refresh token leaks to the log sink. Today none of the explicit `_log` calls include the body, but the `_parseResponse` thrown messages (`client.dart:614-620`) come from `body['error']` / `body['message']` — and a server that ever echoed a token field in an error message would leak.
- **Apple Sign-In nonce / Google idToken** — these ARE JWT-shaped so the `eyJ…` regex handles idTokens. But the nonce is a hex value with no JWT shape.
- **Activation codes / gift codes** (8-12 char alphanum). If they appear in error messages (e.g. "Gift `ABCD-1234` already redeemed"), they pass through.
- **OAuth state values** — same shape concern.

The audit prompt's specific question — "Any other sensitive patterns it should catch (refresh tokens — opaque hex; activation codes; OAuth state)?" — the answer is yes, the refresh-token surface in particular is exposed if any future log line includes a request body.

**Action:** Either harden `redactSensitive` to scrub well-known field names from JSON bodies (`refreshToken`, `accessToken`, `idToken`, `nonce`, `code`, `state` — replace value with `[REDACTED]`), or invert the model: the http layer never logs request/response bodies, period. The current redact-by-pattern approach is only as good as the patterns enumerated.

### H-MS-2 — `enqueueChange` queue-cap check is not transactional; concurrent enqueues can exceed the 500-entry limit

**File:** `apps/mobile/lib/core/services/offline_sync_service.dart:191-216`, `apps/mobile/lib/core/database/database.dart:169-185`

`enqueueChange` reads `getQueueSize()` (line 193), conditionally calls `removeOldestEntries(100)` (line 199), then inserts. Two near-simultaneous calls (e.g. from two providers updating items in parallel) can both observe size==499, both INSERT, and the queue ends up at 501 (or 502 if both pass the full check). The server-side idempotency story is still fine; the cap itself is just slightly leaky. The audit prompt asks "what happens at entry 501? Oldest dropped? User notified?" — answer: silently dropped via `removeOldestEntries`, no user notification.

Bigger concern: the eviction is **silent** — the user's optimistic UI shows the change as applied, but the underlying queue row is gone the next time the cap is hit. There's no banner / no failed-status row. Pure data loss with no UX signal.

**Action:** Wrap the size-check + insert in a Drift transaction so the cap is enforced atomically. When eviction fires, write to a separate "dropped writes" log (or reuse the failed status with a `'evicted'` reason) so the user can see what they lost. Notify the UI via `isSyncingProvider` adjacent — e.g. a `queueOverflowProvider`.

### H-MS-3 — Drift schema migration drops `local_items` / `local_homes` but the comment says they were "never written to" — verify on real upgrade paths

**File:** `apps/mobile/lib/core/database/database.dart:39-71`

The migration plan handles upgrades 2→3 (create `sync_conflicts`), 3→4 (add `idempotency_key` column), and 4→5 (drop dead `local_items` / `local_homes` tables). The audit prompt asks: "If a user upgrades the app from a build with schema 4 to schema 5, does data survive?"

Trace: a v4 device opens v5 binary → `onUpgrade(m, 4, 5)` runs → loop sets `target=5` → executes `DROP TABLE IF EXISTS local_items` and `local_homes`. The active tables `offline_queue` and `sync_conflicts` are untouched. So pending offline mutations survive the upgrade — good.

Risk: the comment claims those two tables were "never written to". `git grep` confirms no `into(localItems)` / `into(localHomes)` exists in current code, so the drop is safe. But: a user who had a much older binary that DID write to those tables (if any historical version existed) loses data on upgrade. The original install date matters. Given the project hasn't shipped, this is academic, but it's worth documenting in the migration that historical data in those tables is intentionally dropped.

**Action:** Either add a comment confirming "no shipped binary ever wrote to these" (preferred, since the project hasn't shipped publicly), or — once the app DOES ship — add a defensive `INSERT INTO offline_queue ... SELECT FROM local_items` migration before the DROP if any historical binary actually populated them.

### H-MS-4 — `auth_repository.signOut` reads refresh token via a duplicate `FlutterSecureStorage` instance, divergent from `ApiClient`

**File:** `apps/mobile/lib/core/services/auth_repository.dart:118-122`

`AuthRepository.signOut` constructs its own `FlutterSecureStorage` with `KeychainAccessibility.first_unlock` (NOT `first_unlock_this_device`), then reads `'refresh_token'` from it. But `ApiClient` writes the refresh token via its `_storage` field (`client.dart:259-277`), which uses `KeychainAccessibility.first_unlock_this_device`. **Different accessibility classes are different keychain items on iOS.** The two stores point at the same key name but the iOS keychain treats them as separate records — the read at line 124 will return `null` because the actual token was written under `first_unlock_this_device`.

If true, this means `signOut` always sends `{}` to `/auth/logout` (no `refreshToken`), so the server cannot revoke that specific refresh token. Existing sessions on other devices are unaffected (correct), but the local refresh-token row in the server's `refresh_tokens` table stays alive until natural expiry. Not a data-loss issue but a session-revocation gap.

**Action:** Drop the duplicate `FlutterSecureStorage` instance. Pass the refresh token through `ApiClient` (`apiClient.readRefreshTokenForLogout()` or similar) so there's exactly one accessor with one accessibility class.

### H-MS-5 — `_processEntry` `markActionSynced` runs even when 409 was parked (inconsistent state)

**File:** `apps/mobile/lib/core/services/offline_sync_service.dart:270-282`

Around `_processEntry`:

```dart
await _db.markActionInFlight(entry.id);
await _processEntry(entry);          // 409 -> _parkUpdateConflict -> RETURNS NORMALLY
await _db.markActionSynced(entry.id); // <-- runs!
```

When `_parkUpdateConflict` swallows the 409 (which is intentional — that's how parking works), `_processEntry` returns normally and the queue row gets marked `synced`. But the underlying server state was NOT updated — the conflict is parked and the user's edit hasn't actually shipped yet. Marking the queue row `synced` then `clearSyncedActions` (line 344) deletes the row, so:

1. The conflict row in `sync_conflicts` is the only remaining trace.
2. If the user picks "keep mine" in the conflict UI, `repo.updateItem(winning)` runs (`conflicts_screen.dart:126`) — that's fine, server now reflects local.
3. If the user picks "keep server" without ever opening the conflict screen, and then dismisses it (or the conflict row is cleared somehow), the local edit is gone with no record.

The "synced" status is misleading — semantically the entry was deferred to manual resolution, not synced. A subtle but real correctness gap because anything analyzing the offline queue history (failed-sync banner, debug exports, telemetry) thinks the write succeeded.

**Action:** When `_parkUpdateConflict` parks, return a sentinel (e.g. `bool _processEntry(...) -> bool didSync`). Skip `markActionSynced` when the entry was parked, and instead delete the queue row directly with a status of `'parked'`. Or unify the conflict-park into a transaction that flips the queue row's status to `'parked'` instead of leaving it to be marked `synced`.

### H-MS-6 — Optimistic-create offline uses empty string `''` as `entityId`; collisions if two are created offline

**File:** `apps/mobile/lib/core/providers/items_provider.dart:118-123`, `apps/mobile/lib/features/add_item/quick_add_screen.dart` (Item construction)

Quick-add constructs `Item(id: '', …)` then calls `addItem`. On `_isOfflineError`, `enqueueChange(entityId: item.id, …)` puts `entityId=''` in the queue. The optimistic state list has `[item]` with `id=''`. Two offline creates → both have `id=''` → `state` list contains two rows that share an empty key. UI selectors keyed on id will collapse / mis-render. The replay at `_processEntry` line 416-422 calls `createItem(item)` for each — server generates IDs and returns the full row, but the optimistic state still holds the empty-id duplicates until a refresh.

**Action:** Stamp a client-side UUID at `Item(id: …)` construction (or in the quick-add flow), then let the server preserve it as the canonical id (the API already accepts caller-supplied IDs in the create payload — verify). Optimistic state rendering keys on real ids; replay flows through cleanly.

### H-MS-7 — `_isTokenExpired` returns `true` on parse failure → silent infinite refresh loop on a malformed stored token

**File:** `packages/api_client/lib/src/client.dart:374-405`

`_isTokenExpired` returns `true` for any decode failure (line 404). `restoreSession` then calls `refreshAccessToken`. If `refreshAccessToken` succeeds, the new token is stored — fine. If it fails (5xx), C-MS-2 wipes tokens. If it fails with a malformed response, same.

But consider: corrupt access token stored in keychain (e.g. partial write). On every cold start, `_isTokenExpired` returns true → `refreshAccessToken` runs → either succeeds (token replaced — self-heals) or hits C-MS-2 (signs out). Self-heal path is fine. Sign-out path falls under C-MS-2.

Lower risk than C-MS-2 but worth fixing as part of the same change: log the parse failure as a distinct telemetry event (`token_parse_failure`) so we can measure whether stored tokens ever get corrupted in the wild.

### H-MS-8 — `setActiveDatabaseUser` race on cold start — `localDatabaseProvider` reads the in-memory `_activeUserIdSync` which may not be set yet

**File:** `apps/mobile/lib/core/database/database.dart:333-354`, `apps/mobile/lib/main.dart:131-139`

`localDatabaseProvider` (line 333-339) reads the top-level `_activeUserIdSync` Dart variable when first instantiated and uses it to compute the per-user file. The variable is set by `setActiveDatabaseUser` in `main.dart:136`. As long as no one reads `localDatabaseProvider` before line 136 executes, this is fine. But `main.dart:202-211` builds `ProviderScope` AFTER line 136. Good — but there's no compile-time guarantee. A future refactor that moves `runApp(ProviderScope(...))` ahead of the user-id seed will silently open the wrong (global) DB file for the rest of the session.

**Action:** Make `_activeUserIdSync` non-null required by funneling the bootstrap through a single function that sets it, then constructs the ProviderScope. Or: pass userId as an override on `localDatabaseProvider` instead of through a top-level var. The override pattern is more idiomatic Riverpod and avoids the implicit ordering contract.

---

## Medium

### M-MS-1 — Conflict resolver uses `firstWhere` semantics that hide one-second-granularity conflicts

**File:** `apps/mobile/lib/core/utils/conflict_resolver.dart:63-76`, `42-55`

The dartdoc explicitly acknowledges the issue ("If two edits happen within the same timestamp granularity (e.g., within the same second), one may be silently overwritten") and accepts it. Mentioned only because the audit prompt asks about correctness. The proper fix is server-issued ETags / version counters; the comment plans for that. Accept as-documented for now.

### M-MS-2 — `redactSensitive` regex `Bearer\s+[^\s"]+` would not catch `Bearer\t<token>` if the token contains an embedded newline (defensive only)

**File:** `packages/api_client/lib/src/client.dart:184-187`

`[^\s"]+` excludes whitespace and double-quote, so any horizontal/vertical-whitespace inside the token chunk would terminate the match early and leak the rest. Tokens are always bearer tokens in headers (no whitespace), so this is theoretical. Worth noting because of how easy it is to widen accidentally — e.g. if someone ever does `Authorization: Bearer ${t1}\n${t2}` (which is invalid but parses oddly), the redact won't help.

### M-MS-3 — `_databaseFileName` uses 64 bits of SHA-256 — collision math is fine but per-user file enumeration leaks user-id hashes if the device is compromised

**File:** `apps/mobile/lib/core/database/database.dart:237-246`

64 bits of SHA-256 = ~1 collision per 2^32 users (4B). That's astronomically low for any realistic install base. The audit prompt asks to verify; verified. The only consideration is that someone with file-system access to the device can list `havenkeep-<hash>.sqlite` files and confirm a specific user-id was signed in (offline rainbow attack on user-id space — but user-ids are UUIDs, so the search space is too large). No action.

### M-MS-4 — `_kBiometricLockGracePeriod = Duration(seconds: 30)` — hard-coded constant, audit calls for "tight" but not "user-configurable"

**File:** `apps/mobile/lib/main.dart:241`

CLAUDE.md doesn't list this as configurable. 30s is the documented audit value. Force-kill behavior: `_backgroundedAt` is in-memory; a force-kill clears it. On next launch, `_maybeShowLock` falls back to `lastUnlock` from secure storage (`main.dart:303`). If the last unlock is older than 30s (any cold start with biometric enabled is), the lock prompts. So force-kill → re-prompt. Correct.

### M-MS-5 — `Crashlytics _crashlyticsReady` only flips after `Firebase.initializeApp` succeeds; calls between zone setup and Firebase init are silently dropped

**File:** `apps/mobile/lib/main.dart:97-107`, `158-170`

The unknown-enum reporter (line 97-107) reads `_crashlyticsReady` at call time. Lines 158-170 init Firebase and set the flag. Any `logUnknownEnumValue` or `recordError` between the registration of the reporter (line 97) and Firebase init (line 159) is dropped. In practice nothing between those lines triggers an enum drift — but the model loading (e.g. `EnvironmentConfig.fromEnvironment`) runs in between. Currently no enum drift can fire there; if a future change adds Item parsing in bootstrap before line 170, drift signals will be lost.

**Action:** Defer reporter registration until AFTER Firebase init, or make the funnel queue messages into a buffer and flush when the flag flips.

### M-MS-6 — `sync_conflicts.entityType` only ever sees `'item'` today; `conflicts_screen.dart` handles others by throwing — silent feature gap

**File:** `apps/mobile/lib/features/settings/conflicts_screen.dart:110-114`, `apps/mobile/lib/core/services/offline_sync_service.dart:474-479`

Only `update_item` parks conflicts (`offline_sync_service.dart:430-435`). `update_preferences` doesn't (it'd be the natural next target — server can detect concurrent prefs edits across devices). If a future hand-off enables prefs conflicts and forgets to update the conflict screen, the user sees `StateError: Unsupported conflict entity type: preferences` instead of resolution UI.

**Action:** Either delete `update_preferences` from the prospective-conflict surface (declare last-write-wins for prefs is intentional), or add the prefs branch to `conflicts_screen.dart` ahead of the server-side change.

### M-MS-7 — `OfflineQueueData.idempotencyKey` is `nullable` — the schema-v4 migration comment says "entries enqueued before the schema-v4 migration have a null key"

**File:** `apps/mobile/lib/core/database/tables/offline_queue.dart:17`, `apps/mobile/lib/core/services/offline_sync_service.dart:401-414`

The dartdoc says null-key entries "degrade gracefully (server treats them as non-idempotent)". Acceptable trade-off. But the column is permanently nullable — every new enqueue ALSO has the option of writing null (a future bug in `enqueueChange` could regress to null and we wouldn't notice at the schema level). Per CLAUDE.md Rule 2 ("Never implement backfill"), the right move is to:

1. One-time SQL: `UPDATE offline_queue SET idempotency_key = lower(hex(randomblob(16))) WHERE idempotency_key IS NULL` in a migration step.
2. Add a `NOT NULL` constraint.

Or: change `idempotencyKey` to non-nullable in the table definition (Drift will require all existing rows to have a value — combine with the one-time UPDATE above as a v6 migration).

### M-MS-8 — `OfflineSyncService.dispose()` does not close the db; depends on Riverpod `onDispose` — order matters

**File:** `apps/mobile/lib/core/services/offline_sync_service.dart:122-126`, `545-562`

`offlineSyncServiceProvider` registers `onDispose(() => service.dispose())` (line 560). `localDatabaseProvider` registers its own `onDispose(() => db.close())` (`database.dart:337`). If the service is in the middle of `syncPendingChanges` when dispose fires, the in-flight markActionSynced/markActionFailed call could race with the close. Riverpod guarantees a deterministic dispose order based on dep graph, but the service holds the db reference — if Riverpod tears providers down in registration order, the db could close while the sync run is still in-flight.

In practice the only call site that disposes both is sign-out (`auth_provider.dart:_wipeLocalState`). It awaits `db.close()` BEFORE the provider is invalidated; the sync service doesn't get torn down until later. Safe today, fragile.

**Action:** `OfflineSyncService.dispose()` should `await` an in-flight sync if any (e.g. expose `Future<void> get currentRun` and await it inside dispose). Belt-and-braces protection.

---

## Low

### L-MS-1 — `_log` redacts via `redactSensitive` but the `developer.log` call in `_headers` (line 526-530) emits the request id without redaction — fine, but inconsistent path

**File:** `packages/api_client/lib/src/client.dart:526-530`

The `request_id=$requestId` line goes through `developer.log`, not `_log`. The request id is non-sensitive (32 hex chars from `Random.secure`) so this is fine. Worth noting only because the log path bypasses the redactor — if a future change adds a `developer.log` line that interpolates `$_accessToken`, it wouldn't be scrubbed.

### L-MS-2 — Drift `getQueueSize` / `pendingCount` / `failedCount` could be one COUNT(*) with `GROUP BY status`, currently three round trips

**File:** `apps/mobile/lib/core/database/database.dart:99-107`, `144-151`, `169-174`

UI showing the offline-queue summary (settings screen) calls all three. Single query returning `(pending, failed, total)` would shave two SQLCipher round trips. Cosmetic.

### L-MS-3 — `_kQueuedUploadsDir` filename strategy uses 16 hex chars from sha256(sourcePath); same source-path collisions reuse the same persisted file (intentional, OK)

**File:** `apps/mobile/lib/core/services/offline_sync_service.dart:140-161`

Documented as idempotent ("re-queueing the same file reuses the same persisted copy"). Verified. The 64-bit collision space for source paths on a single device is comfortable.

### L-MS-4 — `redactSensitive` allocates twice per message (one `replaceAll` per regex)

**File:** `packages/api_client/lib/src/client.dart:182-194`

A single combined regex (with alternation) would halve allocations. Cosmetic — log volume is low.

---

## Nothing-to-fix verifications

These were specifically called out in the audit prompt and verified clean:

- **Sealed switch in offline-sync replay** (`offline_sync_service.dart:291-330`): all 9 ApiException subtypes are explicitly cased. The compiler will flag a missing case if the sealed hierarchy grows.
- **Idempotency key minted at enqueue, not at retry** (`offline_sync_service.dart:205-216`): UUID is stamped once and stored on the row; replay reads from `entry.idempotencyKey` (line 414).
- **Single-flight refresh deadlock** (`client.dart:438-497`): the `try/catch/finally` ensures `_refreshCompleter = null` always runs; a synchronous throw before the body completes still completes the completer with error (line 489-493) so other waiters get the error.
- **Concurrent `syncPendingChanges` re-entry**: guarded by `_isSyncing` flag at line 230.
- **Conflict UI rapid-tap**: `_resolving` flag at `conflicts_screen.dart:97, 233, 238` disables both buttons during in-flight work.
- **`_bytesToHex` zero-out** (`database.dart:299-308`): the byte buffer is overwritten in-place after PRAGMA. The string copy of the hex passphrase still lives in heap until GC; the comment acknowledges this is the language limit.
- **Apple OAuth nonce / Google idToken passthrough** (`auth_repository.dart:90-108`): values are forwarded to the backend, never logged locally.
- **`x-request-id` is correlation-only**, never used as auth: confirmed (`client.dart:524-530`).
- **No legacy `path:` API usage** in the mobile codebase (`grep` returns 0 hits in `apps/mobile/lib`).
- **No TODO / FIXME / HACK markers** in any of the audited files (per CLAUDE.md Rule 1).
- **`upload()` idempotency-key capture** (`client.dart:818-857`): the closure reads `idempotencyKey` from outer scope at call time of `doUpload`, which is invoked inside `_withAutoRefresh`; on retry the same closure is reinvoked and re-reads the same outer variable. Correct.
- **`_headers` reads `_accessToken` at request time** (line 518): rebuild on every request, not closure-captured.
- **Force-kill biometric re-prompt path**: in-memory `_backgroundedAt` is gone post-kill; `lastUnlock` from secure storage is the authority on next launch (`main.dart:303`).
- **`KeychainAccessibility.first_unlock_this_device` on both auth tokens AND DB key**: confirmed — `client.dart:274` and `secure_storage_service.dart:42`. Push token / device id / biometric pref live on the iCloud-replicating store, which is the right trade-off.
- **Auth-gated connectivity listener**: `OfflineSyncService.start` does NOT subscribe until `isAuthenticatedProvider` flips true; tears down on false (`offline_sync_service.dart:80-95`).

---

## Rollup

| Severity | Count |
|---|---|
| Critical | 6 |
| High | 8 |
| Medium | 8 |
| Low | 4 |
| **Total** | **26** |

Top three to land first:
1. **C-MS-2** — `refreshAccessToken` non-200 handling defeats H-B9. One file, one branch.
2. **C-MS-3** — 7-day eviction on FAILED entries. One-line filter fix in `database.dart:188-189`.
3. **C-MS-6** — `WarrantyPurchaseStatus` `cancelling` value missing AND every `firstWhere(orElse:)` enum needs the funnel. Mechanical but high-value telemetry.

After those, **C-MS-1** (TLS pinning) and **C-MS-4** (DB backup-restore corruption) are required before TestFlight.
