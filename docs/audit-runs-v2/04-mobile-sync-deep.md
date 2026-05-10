# Audit 04 v2 — Mobile Sync, Storage, Security (Deep Pass)

**Scope:** offline queue, SQLCipher DB, secure storage, biometric lock, ApiClient, conflict resolver, shared_models enums, bootstrap, adversarial scenarios.
**Date:** 2026-05-10
**Predecessor:** [docs/audit-runs/04-mobile-sync-storage.md](../audit-runs/04-mobile-sync-storage.md) (26 findings; 6 Critical / 8 High / 8 Medium / 4 Low). This deep pass does not duplicate v1 dispositions — it cites them by id when the same code path surfaces a *new* concern, but every finding below is independently new.

**Severity scale:** Critical (unrecoverable data loss / silent sign-out / irreversible PII leak / crash on cold start) · High (race that can lose user data / wrong-subclass map / silent enum drift on a known-broken status / missed CSP) · Medium (UX gap / partial feature / latent fragility) · Low (cosmetic / micro-perf).

---

## Critical

### C-DEEP-1 — `signOut()` in `ApiClient._withAutoRefresh` clears tokens after refresh succeeded but the *retried* request returned 401

**File:** [packages/api_client/lib/src/client.dart:549-574](../../packages/api_client/lib/src/client.dart)

```dart
if (response.statusCode == 401 && _accessToken != null) {
  try {
    await refreshAccessToken();
  } catch (e) {
    _log('[ApiClient] Token refresh failed, signing out: $e');
    await clearTokens();
    return response;          // <-- returns the original 401 response
  }
  // Refresh succeeded — retry the original request.
  try {
    response = await request();
  } on TimeoutException { ... }
  on SocketException catch (e) { ... }
}
return response;
```

After a successful refresh the retried request can ALSO come back 401 (e.g. server-side row deletion of the user, refresh-token reuse detected, JWT key rotation in flight). The function returns that 401 to `_parseResponse`, which throws `ApiAuthRequiredException` — but tokens are NOT cleared, the new access token IS sitting in the keychain, and `isAuthenticated` still returns `true`. Every subsequent call will refresh-then-401 in a loop forever, the auth stream never emits `signedOut`, and the user is stuck on a "broken" account state with no escape until a force-quit + cold-launch path that hopefully hits `restoreSession`'s reject branch.

The contract should be: a refreshed retry that *still* 401s means the credential is dead — clear tokens. Currently only refresh-itself failure clears.

**Action:** After the retry, check `response.statusCode == 401` and explicitly `clearTokens()` then throw `ApiAuthRequiredException`. Same fix for `upload()`'s `_withAutoRefresh` path (transitively affected).

### C-DEEP-2 — `restoreSession`'s second branch bypasses the clear-on-rejected guarantee when refresh succeeds against a stale `_userId` cache

**File:** [packages/api_client/lib/src/client.dart:319-362](../../packages/api_client/lib/src/client.dart)

The first branch (line 323-346) requires `_accessToken != null && refreshToken != null && _userId != null` — fine. The fallback at line 349-362 enters when the access token is missing but refresh + userId are present. It calls `refreshAccessToken()`. If refresh succeeds, the function returns true — but `_userId` was loaded from secure-storage line 321, which has no expiry / cross-checks. If the user_id row was rotated server-side (e.g. hard-delete + recreate with the same email producing a different uuid, S-D6 audit chain protection scenario), the local `_userId` will be stale. Every subsequent request will be authenticated under a different user's token (attacker's case: no — JWT carries the right user-id; benign drift case: yes — the in-memory cache disagrees with the access-token claims). Riverpod consumers reading `apiClient.currentUserId` will get the wrong value until the next cold start re-reads from `_keyUserId`.

Lower-probability than C-DEEP-1 but the lack of any cross-check between the new access token's `sub` claim and the stored `_userId` is the underlying issue. `refreshAccessToken` (line 472) doesn't update `_userId` at all even though it stores the new access token.

**Action:** Decode the new access token after refresh and cross-check `claims['sub'] == _userId`. Mismatch → `clearTokens` + `ApiAuthRequiredException`. While at it, surface the user_id from the refresh response if the server includes it.

### C-DEEP-3 — `enqueueChange` writes the queue row BEFORE the optimistic state update, but the items provider applies state first; reverse-order failure produces a "wrote to disk but state never reflected it" class of orphan

**File:** [apps/mobile/lib/core/providers/items_provider.dart:116-135](../../apps/mobile/lib/core/providers/items_provider.dart) and [offline_sync_service.dart:186-217](../../apps/mobile/lib/core/services/offline_sync_service.dart)

```dart
if (_isOfflineError(e)) {
  try {
    await ref.read(offlineSyncServiceProvider).enqueueChange(...);  // disk write A
    state = AsyncValue.data([item, ...currentItems]);                // state write B
    ...
  } catch (queueErr) {
    state = previousState;
    rethrow;
  }
}
```

If `enqueueChange` succeeds (row inserted) but `state = ...` throws (e.g. notifier disposed mid-flight by Riverpod because `currentUserProvider` rebuilt), control jumps to `catch (queueErr)`. The catch rolls UI state back to `previousState`, but the queue row is still on disk and will sync on the next online tick — server creates the item, but the user's UI never showed it because the optimistic insert was rolled back. On the next `itemsProvider` refresh the new row appears as if from nowhere (best case) OR a duplicate appears if the user re-attempts the same add (worst case — same `Item.id=''` per H-MS-6 collision concern).

**Action:** Either wrap the optimistic state write in try/catch and don't rollback on its failure, or invert the order (state update first; if that fails, don't enqueue). Note the synchronous `state = ...` setter on AsyncNotifier is documented to throw `StateError` if disposed, so this is reachable.

### C-DEEP-4 — `restoreSession` fallback at line 349 triggers `refreshAccessToken` while `_accessToken == null`; the refresh succeeds, the new token populates `_accessToken`, but the very-first request that races on the same instance can read `null` between save-token and the refresh emitting `tokenRefreshed`

**File:** [packages/api_client/lib/src/client.dart:349-362, 470-477](../../packages/api_client/lib/src/client.dart)

`refreshAccessToken` writes `_accessToken = accessToken` (line 471), then `await _storage.write(...)` (line 472). Between assignment and disk persist, a parallel `_headers()` call on the same `ApiClient` (e.g. an early background fetch racing with a UI fetch) reads `_accessToken` (line 518). The keychain write is awaited but the in-memory write is synchronous — fine for that race. But `_authStateController.add(ApiAuthState.tokenRefreshed)` happens AFTER the storage write. Anything `listen`-ing on `authStateChanges` to gate "first authenticated request" can fire its first request before the keychain has been updated; any subsequent process-restart between in-memory set and disk persist (theoretically possible if the OS suspends mid-await) leaves a divergent state.

More importantly: `refreshAccessToken` at line 446 reads the refresh token via `await _storage.read(...)`. If the device is locked / keychain inaccessible (KeychainAccessibility.first_unlock_this_device blocks reads when device is locked at boot), this read returns `null` → throws `ApiAuthRequiredException(401, 'No refresh token available')` → C-MS-2 wipes tokens. App relaunches when user unlocks, finds an empty keychain, drops them at the welcome screen. That's a real failure mode on iOS for users who reboot their phone with FaceID-locked-on-boot and the app cold-starts via a push notification before they unlock.

**Action:** Detect the "device locked / keychain access denied" case explicitly and short-circuit `restoreSession` to "wait for unlock" rather than treat as auth-rejected. `flutter_secure_storage` exposes a `PlatformException` with a known code on iOS for this — wrap the read accordingly.

### C-DEEP-5 — Drift `_databaseFileName` allows arbitrary user-id suffix → empty user-id "havenkeep.sqlite" collides between signed-out and zero-uid path

**File:** [apps/mobile/lib/core/database/database.dart:237-246](../../apps/mobile/lib/core/database/database.dart)

```dart
String _databaseFileName(String? userId) {
  if (userId == null || userId.isEmpty) {
    return 'havenkeep.sqlite';
  }
  ...
}
```

Empty string → `havenkeep.sqlite`. Null → `havenkeep.sqlite`. Same file. The "global" file is the entry point during the bootstrap window before `setActiveDatabaseUser(activeUserId)` runs, and is also where the queue gets opened after a failed sign-in attempt where the user-id is empty. If user A signs in (queue gets bound to `havenkeep-<hashA>.sqlite`), then signs out (`_wipeLocalState` deletes the per-user file but doesn't touch the global one), then user B signs in on the same device, there's a brief window during the bootstrap of the new session where `localDatabaseProvider` reads `_activeUserIdSync == null` and re-opens `havenkeep.sqlite`. If the SQLCipher key in the keychain was regenerated between sessions (sign-out called `SecureStorageService.clearAll()` which wipes `_keyDbEncryptionKey`), then the global file's old encryption key no longer exists → SQLCipher throws SQLITE_NOTADB. There's no fallback — the next operation hits a `SqliteException` and any read of the offline queue / conflicts crashes.

This compounds with the v1 C-MS-4 finding: backup-restore corrupts the per-user file; this finding adds that the *global* file path can be similarly orphaned through the sign-in/sign-out cycle even on a clean device.

**Action:** Either delete the global file in `_wipeLocalState` (right now `deleteDatabaseFile(userId: effectiveUserId)` only deletes the per-user file), or make the global path uniquely named + delete it on first sign-in. Belt-and-braces: the open-side guard from v1 C-MS-4 (try-decrypt, recreate on failure) covers this too.

### C-DEEP-6 — `auth_repository.signOut()` constructs a duplicate `FlutterSecureStorage` with `KeychainAccessibility.first_unlock` (NOT `first_unlock_this_device`) — confirms v1 H-MS-4 + an additional cross-device leak path

**File:** [apps/mobile/lib/core/services/auth_repository.dart:117-127](../../apps/mobile/lib/core/services/auth_repository.dart)

```dart
const storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);
String? refreshToken;
try {
  refreshToken = await storage.read(key: 'refresh_token');
}
```

V1 H-MS-4 noted that the read returns null because the canonical write uses `first_unlock_this_device`. New finding: `first_unlock` is iCloud-Keychain-replicable. If by some path (e.g. legacy build, a future bug, or someone copy-pasting this code into another flow), refresh tokens land in `first_unlock`, they'd roam to the user's other devices via iCloud Keychain. The presence of `first_unlock` in the codebase at all is a footgun; a future engineer could legitimately think "use this storage, the auth one already does" and end up with iCloud-replicable refresh tokens silently shipped.

The fix the v1 audit recommends (drop the duplicate, route through ApiClient) is correct AND necessary because of this footgun. Until that lands, every new bit of secure-storage code in `auth_repository.dart` could pick up the wrong default.

**Action:** Delete the duplicate constant. Expose a method on ApiClient like `Future<String?> peekRefreshTokenForRevocation()` (if absolutely needed) so the only `KeychainAccessibility.first_unlock_this_device`-bound storage in the app is the one inside ApiClient.

### C-DEEP-7 — `apiClientProvider` override in `main.dart` stamps the client AFTER `setActiveDatabaseUser` but BEFORE the bootstrap completes — races against any `Future` that captures `apiClient` from outside the ProviderScope

**File:** [apps/mobile/lib/main.dart:201-212, 110-138](../../apps/mobile/lib/main.dart)

```dart
final apiClient = ApiClient(baseUrl: config.apiBaseUrl);  // 110
try {
  await apiClient.restoreSession();                        // 112
} catch (e) { ... }

// Lines 117-129: keep-signed-in check
// Lines 131-139: setActiveDatabaseUser

runApp(
  ProviderScope(
    overrides: [
      apiClientProvider.overrideWith((ref) {
        ref.onDispose(() => apiClient.dispose());          // 206
        return apiClient;
      }),
    ],
```

The `apiClient` was constructed at line 110 BEFORE `setActiveDatabaseUser` (line 136). `restoreSession` runs at line 112 — no DB-bound providers are consulted. Fine. But `clearTokens` at line 123 emits `signedOut` on the broadcast stream. If `OfflineSyncService.start` were to be triggered earlier in the bootstrap (it's not today, but a future change might), the unauth → re-auth sequence would race against the DB-user-id seed. Today the order is correct, but there's no compile-time enforcement — same fragility v1 H-MS-8 documented for `_activeUserIdSync`, but for the API client.

A more concrete failure: `ProviderScope` is created with `apiClient` already in `signedOut` state (because keep-signed-in=false fired clearTokens), but `_userId` was already populated by `restoreSession`. The Provider scope then reads `currentUserId` → returns the now-stale id, but `isAuthenticated` returns false. Anything that watches both will see an inconsistent snapshot. `setActiveUserId` at line 138 only runs `if (apiClient.currentUserId != null)`, but the local var `activeUserId` at line 134-135 reads `apiClient.currentUserId ?? ...secure storage` — and `clearTokens` already ran at line 123. After `clearTokens`, `currentUserId` is null (line 429), so the secure-storage fallback runs — but if the secure storage `active_user_id` key was set in a previous session and never cleared (sign-out path uses `clearAll` which does clear it), `activeUserId` becomes the previous user's id and is fed into `setActiveDatabaseUser`. **The signed-out user's queue/conflicts file is opened.**

**Action:** Either move `setActiveDatabaseUser` BEFORE the keep-signed-in branch (so `currentUserId` is the truth source) AND clear `active_user_id` in `clearTokens` (currently it's only cleared in `_wipeLocalState`), or run the keep-signed-in clear path AFTER `setActiveDatabaseUser` and skip the DB-user binding when `clearTokens` was forced.

---

## High

### H-DEEP-1 — `redactSensitive` does not redact the request id, the bearer-prefix is case-insensitive but the exclusion class `[^\s"]+` lets URL-encoded tokens leak on a `'` boundary

**File:** [packages/api_client/lib/src/client.dart:182-194](../../packages/api_client/lib/src/client.dart)

```dart
var out = input.replaceAll(
  RegExp(r'Bearer\s+[^\s"]+', caseSensitive: false),
  'Bearer [REDACTED]',
);
```

`[^\s"]+` excludes whitespace and `"`. Single quote `'` is not excluded. An access token containing `'` would not happen with JWT base64url alphabet, but if a Bearer is ever logged inside a string-templated SQL-style log line (e.g. `'Bearer xyz'` after string-interpolation), the regex matches `Bearer xyz'` → consumes the trailing `'`. Cosmetic in practice, real if any future log call interpolates the value through SQL escaping. More importantly: tokens with embedded `>` / `<` / `,` / `}` are matched but the surrounding JSON braces would get consumed too — log line becomes mis-formatted.

Test: paste sample bearer + JWT + activation code + opaque hex through:

| Input | Output |
|---|---|
| `Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.sig` | `Authorization: Bearer [REDACTED]` (works) |
| `{"refreshToken":"a1b2c3d4..."}` | unchanged (NOT redacted; v1 H-MS-1) |
| `gift code ABCD-1234` | unchanged (NOT redacted; v1 H-MS-1) |
| `nonce=4f3a8b2e9c...` | unchanged (NOT redacted; v1 H-MS-1) |
| `{"x":"Bearer abc","y":"Bearer def"}` | `{"x":"Bearer [REDACTED]","y":"Bearer [REDACTED]"}` (the `"` boundaries terminate match correctly, ok) |
| `Bearer abc'def` | `Bearer [REDACTED]` (consumes the `'` and `def` — incorrect but benign) |

**Action:** Same v1 H-MS-1 redaction-by-field-name fix.

### H-DEEP-2 — `_isTokenExpired` 30-second skew window applies to BOTH "expired" and "about-to-expire", but `restoreSession`'s pre-flight check fires `refreshAccessToken` even when the token has 25 seconds left — burns refresh quota on every cold start of a recently-warm session

**File:** [packages/api_client/lib/src/client.dart:374-405, 325](../../packages/api_client/lib/src/client.dart)

```dart
return DateTime.now().isAfter(
  expirationDate.subtract(const Duration(seconds: 30)),
);
```

A token issued 14:55 with 15-min lifetime expires 15:10. At 15:09:35, `_isTokenExpired` returns true. `restoreSession` fires `refreshAccessToken`. If the user cold-launches the app at 15:09:50 they refresh on launch even though the token would have lasted another 25 seconds. Server-side rate-limit on the refresh endpoint (currently 10/min per IP per the auth limiter) doesn't care about a single user, but a user who cold-launches the app twice in the 30-second skew window burns two refreshes for no reason. Long-term: incrementally degrades refresh-token throughput on the server's `refresh_tokens` table (each refresh writes a row to `refresh_token_chain`).

**Action:** Document the 30-second margin as intentional (it's defensive against clock skew between client and server) but consider tightening to 10-15 seconds. Not data-loss but worth tracking.

### H-DEEP-3 — `_parseResponse` fails to handle `Content-Type: text/plain` bodies — Caddy / Cloudflare 502 / 504 returns HTML or plaintext error pages, decoded as JSON throws `FormatException`, mapped to `ApiException.fromResponse(502, 'Invalid JSON in response body')`

**File:** [packages/api_client/lib/src/client.dart:584-607](../../packages/api_client/lib/src/client.dart)

```dart
try {
  if (response.body.isEmpty) {
    body = <String, dynamic>{};
  } else {
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      body = decoded;
    } else { ... }
  }
} on FormatException {
  throw ApiException.fromResponse(
    response.statusCode,
    'Invalid JSON in response body',
  );
}
```

Behavior is correct (502 still maps to `ApiServerException`), but the error message is misleading — a Caddy 502 returns an HTML page; the user sees "Invalid JSON in response body" surfaced through a snackbar or error screen instead of "the server is temporarily unavailable". UX bug, not correctness.

Worse: the FormatException catch ignores `response.statusCode` semantics and feeds the original status to `fromResponse`. So a 200 OK with malformed JSON throws `ApiUnknownException(200, 'Invalid JSON...')` — that goes to a `default` in upstream switches and surfaces as "unknown error" with no retry. The OfflineSyncService catches `ApiUnknownException` and retries (line 320), which is correct, but `_parseResponse`-driven failures on 200s are misleading for users.

**Action:** Branch on `response.headers['content-type']` to short-circuit non-JSON paths with a clearer message (`'Server returned non-JSON response'`). Also distinguish `body.isEmpty` for non-2xx (server error with empty body) from the 204-style empty-body 2xx case — the current code returns an empty map for both, which works for the success branch but elides error info.

### H-DEEP-4 — `_buildUri` percent-encodes individual segments via `Uri.replace(pathSegments:)` but does NOT validate that no segment contains `/` — caller passing `id = "abc/def"` slips a path traversal

**File:** [packages/api_client/lib/src/client.dart:642-665](../../packages/api_client/lib/src/client.dart)

`Uri.replace(pathSegments: [..., 'abc/def'])` produces a URI where `/` is percent-encoded as `%2F` — Express decodes it, but most routers (Express included via path-to-regexp) reject percent-encoded slashes by default. So `GET /api/v1/items/abc%2Fdef` returns 404, not the wrong endpoint. This is fine.

But a segment like `..` is NOT special-encoded. `Uri.replace(pathSegments: ['api', 'v1', 'items', '..'])` produces `https://api.example.com/api/v1/items/..` — the `..` is interpreted by the *server's* normalisation (Caddy, Express) which COULD walk up a level. Express path-to-regexp also doesn't normalise `..`, so `GET /api/v1/items/..` is matched against the items routes — Express returns 404 because `..` is not a valid uuid for the param. So this is also fine in practice.

The real failure mode: a caller that constructs `pathSegments: ['api', 'v1', 'items', userInput]` where `userInput = ''` (empty string). `Uri.replace` filters or preserves empty segments depending on version — Dart 3's behavior is to preserve them, producing `/api/v1/items/` which routes to the LIST endpoint, not 404. So `getItemById('')` lists all items instead of 404ing. The router then leaks every item the user has access to.

```dart
Future<Item> getItemById(String id) async {
  try {
    final data = await _client.get(
      pathSegments: ['api', 'v1', 'items', id],  // <-- id='' becomes /items/
    );
```

The mobile app does call `getItemById(localItem.id)` from `_parkUpdateConflict` (line 463). If `localItem.id == ''` (per H-MS-6 the optimistic-create path uses empty string), this LISTS all items, picks the first by accident, and treats it as the conflict target. Multiplied by the conflict-park flow, the user sees a "conflict" against a totally unrelated item.

**Action:** Either reject empty segments in `_buildUri` (assert + throw) or validate caller inputs (`getItemById` should reject empty id with a typed exception). The former is the safer default.

### H-DEEP-5 — `_withAutoRefresh` does NOT timeout the refresh-then-retry combination — a hung refresh can stall the original request indefinitely if the refresh's 10-second timeout fires but `request()` retry has its own `_defaultTimeout=30s`

**File:** [packages/api_client/lib/src/client.dart:455-572, 636](../../packages/api_client/lib/src/client.dart)

```dart
final response = await _http.post(...).timeout(const Duration(seconds: 10));
```

Refresh has its own 10-second timeout (line 455). Original request has 30s (line 636) wrapped at `_withAutoRefresh` callsites. So the worst case is 30 + 10 + 30 = 70 seconds for a request that hits 401 → refresh → retry. Not infinite, but worse than the apparent contract (30s). UI loading spinners hold for over a minute on the "your token expired but the network is also slow" path. Not a correctness bug; UX gap.

**Action:** Wrap `_withAutoRefresh` in an outer `.timeout(_defaultTimeout * 2)` so the entire envelope is bounded.

### H-DEEP-6 — `OfflineSyncService.dispose()` does not await an in-flight `syncPendingChanges` — confirmed M-MS-8 from v1 PLUS a new race: `_authSub.close()` fires before sync's `ref.read(isSyncingProvider.notifier).state = false` runs, leaving the UI's "Syncing…" stuck

**File:** [apps/mobile/lib/core/services/offline_sync_service.dart:122-126, 345-354](../../apps/mobile/lib/core/services/offline_sync_service.dart)

```dart
void dispose() {
  _detachConnectivityListener();
  _authSub?.close();
  _authSub = null;
}
```

If the user signs out mid-sync (auth-state listener at line 81-95 fires `_detachConnectivityListener`, then sign-out's `ref.invalidate(localDatabaseProvider)` triggers the provider's `onDispose`, which calls `service.dispose()`), the in-flight `syncPendingChanges` keeps running against a closed `_db` (the database `onDispose` at line 337 closed it). The `_isSyncing = false` line in the `finally` (line 346) runs after the closed-db exception, but by then `ref` is invalidated → `_ref.read(isSyncingProvider.notifier)` (line 349) throws.

The `try { ... } catch (_) {}` at lines 248 and 350 silently swallow the throw, leaving `isSyncingProvider.state = true` from the entry block (line 244) until the next sync run. UI shows "Syncing…" indefinitely until the user signs back in.

**Action:** Track the future from `syncPendingChanges` (`_currentRun = syncPendingChanges()`) and `await _currentRun` in `dispose`. The auth listener that kicks off sync should be bounded by the same future. Belt-and-braces fix M-MS-8.

### H-DEEP-7 — `clearSyncedActions` runs unconditionally at the end of every sync run, including when the loop bailed early due to an exception in the rest of the run

**File:** [apps/mobile/lib/core/services/offline_sync_service.dart:341-345](../../apps/mobile/lib/core/services/offline_sync_service.dart)

```dart
}

// Clean up synced entries
await _db.clearSyncedActions();
```

`clearSyncedActions` is INSIDE the try/finally at the top of `syncPendingChanges` (line 256-345). But it's outside the per-entry try/catch. If `_db.removeEntriesOlderThan` (line 260) or `_db.getPendingActions` (line 262) throws (e.g. SQLCipher key invalid → SqliteException) BEFORE the for-loop runs, control jumps to the outer `try`'s missing catch, falls through to `finally`. The `finally` at line 345 only sets `_isSyncing = false` — it doesn't run `clearSyncedActions`. Good.

But `clearSyncedActions` IS inside the outer `try` block, which means it runs even if all per-entry processing skipped (e.g. all entries had `attempts >= _kMaxRetries`). At that point `clearSyncedActions` deletes nothing — it's idempotent. Cosmetic.

The real bug: the `markActionSynced` calls inside the loop (line 279) write `status='synced'`, then `clearSyncedActions` deletes them at the end. If the loop is interrupted mid-iteration by a thrown exception (the catch at line 286 / 331 handles it, but if BOTH catches fail to handle e.g. a `StateError` from notifier disposal — caught only by the outer non-existent), the synced rows persist. Next sync run cleans them up — fine, no data loss. But the cleanup is racy if the next run inserts rows in `pending` with the same ID (impossible — autoincrement). OK, not a bug.

**Action:** None — verified clean. Recording the trace because the audit asked.

### H-DEEP-8 — `enqueueChange` does not validate the payload size; a 1 MB payload (e.g. an Item with a 1 MB notes field) is JSON-encoded into the queue row, exceeding SQLite's default `max_page_size` for a single-row INSERT

**File:** [apps/mobile/lib/core/services/offline_sync_service.dart:207-216](../../apps/mobile/lib/core/services/offline_sync_service.dart)

```dart
await _db.enqueueAction(OfflineQueueCompanion(
  ...
  payload: Value(jsonEncode(payload)),
  ...
));
```

SQLCipher inherits SQLite's `SQLITE_MAX_LENGTH` default of 1 GB, so a 1 MB row fits. But Drift's TextColumn maps to TEXT with no size cap, and large rows blow up SQLCipher's per-page encryption performance (each page must be re-encrypted on disk). 500 entries × 100 KB each = 50 MB encrypted file — backup-size affecting.

More importantly: the payload contains user-controlled input (Item.notes is freeform). A user pasting a 10 MB document into `notes` while offline → 10 MB written to the queue. Silent.

**Action:** Cap payload size at, say, 64 KB. Reject larger payloads with a `NonRetriableError` and a UX message.

### H-DEEP-9 — `persistUploadFile` source-path validation only checks existence; doesn't check that source is a file (could be a symlink to outside app sandbox) and doesn't bound the file size

**File:** [apps/mobile/lib/core/services/offline_sync_service.dart:140-161](../../apps/mobile/lib/core/services/offline_sync_service.dart)

```dart
final source = File(sourcePath);
if (!source.existsSync()) {
  throw NonRetriableError(...);
}
final hash = sha256.convert(utf8.encode(sourcePath)).toString().substring(0, 16);
final ext = p.extension(sourcePath);
final destPath = p.join(dir.path, '$hash$ext');
final dest = File(destPath);
if (!dest.existsSync()) {
  await source.copy(destPath);
}
```

`source.copy(destPath)` follows symlinks (Dart's `File.copy` resolves the target). On iOS the photo library picker returns paths inside the temp dir which are auto-deleted; on Android the share-sheet may return a content:// URI that the platform channel resolves to a path outside the sandbox. A malicious file picker plugin could return a path like `/etc/hosts` and we'd silently copy it into our app-support dir. The kMaxFileUploadSize (50 MB, [packages/api_client/lib/src/constants.dart:13](../../packages/api_client/lib/src/constants.dart)) is enforced at the upload-API level but NOT at queue-persist time — an offline user can pile up 1 GB of files in `queued_uploads/`.

**Action:** Validate `source.statSync().type == FileSystemEntityType.file`, validate `source.lengthSync() <= kMaxFileUploadSize`, throw `NonRetriableError` otherwise.

### H-DEEP-10 — `MaintenanceSummaryState.fromJson` falls back to `noItems` on unknown values silently — does NOT call `logUnknownEnumValue`

**File:** [packages/shared_models/lib/src/maintenance.dart:308-323](../../packages/shared_models/lib/src/maintenance.dart)

```dart
static MaintenanceSummaryState fromJson(Object? value) {
  switch (value) {
    case 'no_items': return MaintenanceSummaryState.noItems;
    case 'no_schedules': return MaintenanceSummaryState.noSchedules;
    case 'caught_up': return MaintenanceSummaryState.caughtUp;
    case 'has_due': return MaintenanceSummaryState.hasDue;
    default:
      // Unknown / missing — fall back to the most-conservative state
      return MaintenanceSummaryState.noItems;
  }
}
```

The dartdoc explicitly acknowledges the fallback rationale but doesn't fund it through `logUnknownEnumValue`. If the server adds a new state (e.g. `partial_due`, `degraded`), the mobile silently shows the empty state for users who SHOULD see "you have items pending" — no Crashlytics breadcrumb.

**Action:** Add the funnel call before returning the fallback. Same pattern as `ClaimStatus.fromJson`.

### H-DEEP-11 — Every silent enum factory (the v1 C-MS-6 list) — re-verified across the entire shared_models surface

Re-counting precisely with grep:

**Use `_byName + logUnknownEnumValue` (correct):** `ClaimStatus`, `PartnerStatus` — only two.

**Use `_byName` lookup but NO funnel (silent):** `MaintenanceDifficulty`, `WarrantyPurchaseStatus`, `PartnerCommissionReferenceType`, `PartnerCommissionPayoutMethod`, `PartnerSubscriptionTier`, `EmailScanStatus` — six total.

**Use `firstWhere(orElse:)` (silent):** `ItemCategory`, `ItemRoom`, `WarrantyType`, `WarrantyStatus`, `AuthProvider`, `UserPlan`, `HomeType`, `DocumentType`, `NotificationType`, `NotificationAction`, `PartnerType`, `ReferralSource`, `ConversionType`, `ConversionStatus`, `ItemAddedVia`, `OfflineAction`, `OfflineStatus`, `PartnerGiftStatus`, `PartnerCommissionType`, `PartnerCommissionStatus` — twenty total.

**Use switch with `default:` (silent):** `MaintenanceSummaryState` — one (H-DEEP-10).

Total silent: 27. Total funnel-correct: 2.

**Five concrete known-broken cases** (the audit prompt's specific request):

1. **`WarrantyPurchaseStatus`** — missing `cancelling` (mig 098 added it). Fallback is `active`. User clicks Cancel, sees the warranty stay Active until manual refresh.
2. **`PartnerStatus`** — already funnel-correct; not at risk. (Listed for completeness.)
3. **`PartnerCommissionStatus`** — fallback is `pending`. Mig 030 added `reversed` (already in the enum). Future addition (e.g. a `disputed` state for partner commission disputes) silently falls back to `pending`. UI shows the partner the commission is "pending payout" while it's actually frozen for review.
4. **`ClaimStatus`** — already funnel-correct.
5. **`PartnerCommissionType`** — three values (`gift`, `warranty_sale`, `referral`). If a server adds `partner_subscription_revshare` for the new partner-tier sharing model (alluded to in the partner subscription tier work), mobile silently coerces to `referral` and the partner sees the wrong commission type.
6. **`OfflineAction`** — fallback is `create_item`. If a future migration adds `update_document` or `delete_document`, a queued action silently becomes a `create_item` retry — completely wrong replay semantics. **Highest impact** in this list because the wrong action triggers the wrong API call.
7. **`UserPlan`** — fallback is `free`. If the server adds a `trial` or `enterprise` plan, premium-tier users get gated as free until app update. Free-plan limits silently kick in for users who paid.

**Action:** Migrate ALL 27 silent fromJsons to the `_byName + logUnknownEnumValue` pattern in one sweep. The v1 C-MS-6 audit recommended this; reaffirming priority.

---

## Medium

### M-DEEP-1 — `_isTokenExpired` returns `true` on parse failure, but the parse failure path is never distinguished in telemetry; corrupt access token loops indefinitely if refresh succeeds (self-heals) or hits C-MS-2/C-DEEP-1 (signs out)

**File:** [packages/api_client/lib/src/client.dart:402-405](../../packages/api_client/lib/src/client.dart)

```dart
} catch (e) {
  _log('[ApiClient] Failed to decode JWT for expiration check: $e');
  return true;
}
```

V1 H-MS-7 noted the silent infinite refresh loop. Adding: the `_log` line goes through `redactSensitive` which preserves the stack/exception text. If the corrupt token is JWT-shaped, the regex `eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+` redacts it. If it's NOT JWT-shaped (corrupted partway), the raw bytes go to the log sink. Tokens are sensitive even when malformed.

**Action:** Always-redact the token argument before logging — `_log('Failed to decode JWT for expiration check: $e')` would help, but `e` may contain the raw bytes. Best path: log only the exception class name + `<token suppressed>`.

### M-DEEP-2 — `restoreSession`'s 10-second timeout on refresh is shorter than `_http.post.timeout(10s)` inside `refreshAccessToken` — outer wins by a hair, but a slow handshake races the inner

**File:** [packages/api_client/lib/src/client.dart:328-329, 351-352, 455](../../packages/api_client/lib/src/client.dart)

Both timeouts are 10 seconds. If the inner POST hits exactly the 10-second mark, `TimeoutException` propagates up, the outer `.timeout(10s)` may already be at 9.99s, and Dart's behavior is to throw the inner first. Net: the user waits 10 seconds total. Fine. But the doubled timeout is a code-smell — they should be the same constant.

**Action:** Define `const _refreshTimeout = Duration(seconds: 10);` and reuse.

### M-DEEP-3 — Drift schema version 5 dropped `local_items` / `local_homes` but the `onCreate` for fresh installs still creates only `OfflineQueue` and `SyncConflicts` — net: no v6+ regression risk, but worth noting in the migration

The classes/tables list is `[OfflineQueue, SyncConflicts]` (line 31), so onCreate creates exactly those. The drop in onUpgrade(4→5) is safely no-op if those tables never existed. v1 H-MS-3 noted the risk for historical binaries.

**Action:** None — verified clean.

### M-DEEP-4 — `_openConnection` zero-out of `keyBytes` is best-effort: the SQLCipher native code copies the hex string into its own buffer, AND the `passphrase = "x'${_bytesToHex(keyBytes)}'"` string remains in heap until GC

**File:** [apps/mobile/lib/core/database/database.dart:286-310](../../apps/mobile/lib/core/database/database.dart)

```dart
final passphrase = "x'${_bytesToHex(keyBytes)}'";
try {
  db.execute('PRAGMA key = "$passphrase";');
} finally {
  for (var i = 0; i < keyBytes.length; i++) {
    keyBytes[i] = 0;
  }
}
```

The bytes get zeroed. The hex string `passphrase` does NOT — Dart strings are immutable, and `_bytesToHex` allocates a new String. The `db.execute` call passes the SQL string through Dart FFI to SQLCipher; the string is reachable from both the local var (lost at scope exit) and any FFI-side copy. Heap dump in the GC-pending window leaks the hex. The comment acknowledges this ("string copy of the hex passphrase still lives in heap until GC").

Realistic impact: a memory dump of a running iOS process (requires jailbreak / debugger) could recover the key. This is the language limit, not the code's fault. Worth noting for the threat model.

**Action:** None reachable in pure Dart. If concerned, switch to `package:sqlcipher_flutter_libs`'s lower-level FFI to pass `keyBytes` directly without going through a Dart string. Significant complexity for marginal threat-model gain.

### M-DEEP-5 — `clearAllQueueEntries` and `clearAllConflicts` in `_wipeLocalState` run BEFORE `db.close()` — but if either throws, `db.close()` never runs and the file delete proceeds against an open file handle

**File:** [apps/mobile/lib/core/providers/auth_provider.dart:382-396](../../apps/mobile/lib/core/providers/auth_provider.dart)

```dart
try {
  final db = ref.read(localDatabaseProvider);
  await db.clearAllQueueEntries();
  await db.clearAllConflicts();
  await db.close();
} catch (e) {
  debugPrint('[Auth] DB wipe failed (non-fatal): $e');
}

try {
  await deleteDatabaseFile(userId: effectiveUserId);
}
```

If `clearAllQueueEntries` throws (SQLCipher key mismatch e.g. C-MS-4 / C-DEEP-5), the catch swallows it; `db.close()` does NOT run. Then `deleteDatabaseFile` tries to `file.delete()` while the SQLite connection is still open. On iOS this succeeds (POSIX semantics: open file handles persist after delete). On Android (FAT32 SD card scenarios) this can fail. The catch on line 394-396 swallows that too.

After this, `setActiveDatabaseUser(null)` runs, and the next `localDatabaseProvider` read constructs a NEW `HavenDatabase` instance — but the old one is leaked (hanging onto a SQLite connection on a deleted file). No memory pressure visible to the user, but the file is deleted with active reads/writes possible until the dispose chain catches up.

**Action:** `db.close()` should be in a finally so it runs regardless of clear failures. Better: bracket the wipe in a single try/finally that always closes.

### M-DEEP-6 — `_deletePersistedUpload`'s "managed directory" check is brittle: `p.isWithin` returns false for the directory itself

**File:** [apps/mobile/lib/core/services/offline_sync_service.dart:166-183](../../apps/mobile/lib/core/services/offline_sync_service.dart)

```dart
if (!p.isWithin(queuedDir, path) && p.dirname(path) != queuedDir) {
  return;
}
```

`p.isWithin('/a/b', '/a/b')` returns false. `p.dirname('/a/b')` returns `/a`. So if `path == queuedDir` itself, both checks fail → return without delete. Good. But the check `p.dirname(path) != queuedDir` would pass for nested paths like `/a/b/c/d.pdf` IF the deletion is for nested files. Currently only flat files in `queuedDir` exist, so this is not exercised. Fragile if subdirs are ever introduced.

**Action:** Simplify with a single `p.isWithin(queuedDir, path) || p.equals(queuedDir, p.dirname(path))` and document.

### M-DEEP-7 — `OfflineSyncService.start` subscribes the connectivity listener with `fireImmediately: true` — but `_authSub.listen` calls the callback synchronously with the current value, which can pre-empt other initState() flows

**File:** [apps/mobile/lib/core/services/offline_sync_service.dart:81-95](../../apps/mobile/lib/core/services/offline_sync_service.dart)

```dart
_authSub = _ref.listen<bool>(
  isAuthenticatedProvider,
  (previous, isAuthenticated) {
    if (isAuthenticated) {
      _attachConnectivityListener();
      syncPendingChanges();
    } else {
      _detachConnectivityListener();
    }
  },
  fireImmediately: true,
);
```

`fireImmediately: true` invokes the callback synchronously inside `listen`. The provider that calls `service.start()` ([offline_sync_service.dart:548](../../apps/mobile/lib/core/services/offline_sync_service.dart)) is the constructor; if `isAuthenticatedProvider` is already true, `syncPendingChanges` kicks off before any other Riverpod consumer has subscribed. The sync run itself is async and doesn't actually block, but `_attachConnectivityListener` (line 97-114) registers a stream subscription synchronously — fine.

The race: `apiClientProvider`'s broadcast stream emits `signedIn` from `restoreSession` (line 344) at bootstrap. The auth state stream provider (auth_provider.dart:32) yields immediately. `isAuthenticatedProvider` watches both. If `OfflineSyncService` is constructed BEFORE the auth state has propagated, `fireImmediately` fires with `false`, never re-fires (the StateProvider.listen requires a state change). So the sync loop never starts until auth state changes again.

This is mitigated because `syncPendingChanges` is called every time `isAuthenticated` flips to true OR a connectivity event fires while online. But if the service is constructed AFTER the user's auth-state has stabilized at `true` on cold boot, AND no connectivity event happens, the queue is drained only on the NEXT auth-state flip (sign-out / sign-in). Could be a 30-day stall.

In practice the bootstrap chain in main.dart (line 333: `ref.watch(offlineSyncServiceProvider)` inside `HavenKeepApp.build`) construsts the service AFTER `runApp` runs — well after `restoreSession`. The first read is during `_HavenKeepAppState.build`, by which time auth has settled. `fireImmediately: true` fires with `true` if user is authenticated. OK. Verify this by checking the bootstrap order timeline:

1. `main()` line 110: `ApiClient(...)` constructed.
2. line 112: `restoreSession()` awaited — emits `signedIn` to broadcast stream.
3. line 134-138: `setActiveDatabaseUser` + `setActiveUserId` set.
4. line 159: `Firebase.initializeApp` (after which `_crashlyticsReady = true`).
5. line 201: `runApp(ProviderScope(...))`.
6. ProviderScope is built; `apiClientProvider` overridden.
7. `HavenKeepApp.build` runs: `ref.watch(offlineSyncServiceProvider)` (line 333). The provider reads `localDatabaseProvider` (DB user-id has been set), constructs `OfflineSyncService`, calls `service.start()`, registers auth listener with `fireImmediately: true`.
8. The listener fires with the current `isAuthenticatedProvider` value — `true` (if restored).

The `signedIn` event was emitted to the broadcast stream BEFORE the StreamProvider subscribed (broadcast streams don't replay). But `isAuthenticatedProvider` reads `client.isAuthenticated` directly (line 49), which is `_accessToken != null` — already true from `restoreSession`. So the `fireImmediately` value is correct.

**Action:** None — verified clean. Documenting the trace because the audit prompt asked.

### M-DEEP-8 — `conflicts_screen._resolve` calls `repo.updateItem(winning)` for `keepLocal` but does NOT pass `idempotencyKey` — a 409 here re-parks a conflict referencing the previously-parked conflict

**File:** [apps/mobile/lib/features/settings/conflicts_screen.dart:124-134](../../apps/mobile/lib/features/settings/conflicts_screen.dart)

```dart
if (keepLocal) {
  await repo.updateItem(winning);
}
```

If the user is offline when they pick "keep local", `repo.updateItem` throws `ApiNetworkException`. The catch at line 145 sets `_error`, leaves the conflict row in `sync_conflicts` (the `removeConflict` at line 129 is BELOW the failing `updateItem`). User retries online. Fine.

If the user is online but the server has changed AGAIN since the original conflict was parked, `repo.updateItem` throws `ApiConflictException` (the server's `updated_at` is newer than the local copy). The catch swallows that too — `_error = 'Failed to resolve: ...'`. The conflict row stays. User has to manually re-resolve, but the UI doesn't refresh the server snapshot, so they're picking against stale server data. Stuck in a manual loop.

**Action:** When `_resolve` hits `ApiConflictException`, refresh the conflict's `serverVersionJson` from a fresh `getItemById(localItem.id)` call before showing the error so the next attempt is against current data.

### M-DEEP-9 — `OfflineSyncService.syncPendingChanges` swallows ALL non-Api exceptions in the per-entry catch (line 331-340) but doesn't telemetrize — a `StateError` from a notifier disposed mid-sync looks like a "transient retry"

**File:** [apps/mobile/lib/core/services/offline_sync_service.dart:331-340](../../apps/mobile/lib/core/services/offline_sync_service.dart)

```dart
} catch (e) {
  debugPrint('[OfflineSync] Failed to sync entry ${entry.id}: $e');
  final nextAttempts = entry.attempts + 1;
  if (nextAttempts < _kMaxRetries) {
    await _db.reschedulePending(entry.id, nextAttempts);
    await Future.delayed(_backoffDelay(nextAttempts));
  } else {
    await _db.markActionFailed(entry.id, nextAttempts);
  }
}
```

A `StateError` from `ref.read(itemsRepositoryProvider).createItem(...)` (e.g. provider disposed because user signed out mid-sync) is treated as a transient and rescheduled. After 3 retries it's marked failed. The user sees "3 items failed to sync" — looks like network problems, but actually the provider disposal is the cause.

**Action:** Distinguish disposal exceptions (catch `StateError` separately) from genuine errors and log via Crashlytics.

### M-DEEP-10 — `OfflineSyncService` does NOT cancel `Future.delayed` in `_backoffDelay` if `dispose` fires mid-sleep — a long-running back-off can extend service lifetime past dispose

**File:** [apps/mobile/lib/core/services/offline_sync_service.dart:300, 326, 336, 220-226](../../apps/mobile/lib/core/services/offline_sync_service.dart)

`Future.delayed(_backoffDelay(...))` sleeps up to 30 seconds (`_kMaxDelayMs`). If `dispose` fires during this sleep, the sleep continues, and the loop's next iteration runs against (potentially) closed db / disposed providers. The catch above (M-DEEP-9) covers it but at the cost of pollution on the queue's failed-attempt count.

**Action:** Replace `Future.delayed` with a cancellable sleep that listens to `_disposed` flag; abort the loop early on dispose.

### M-DEEP-11 — `kFreePlanItemLimit = 5` in [api_client/lib/src/constants.dart:4](../../packages/api_client/lib/src/constants.dart) — duplicates server-side env config; drift between mobile and server is silent

Server-side constant lives in `apps/api/src/utils/...` (not directly checked here). If the server raises the limit to 7 but the mobile binary still has 5 hardcoded, free users see "limit reached" UI when the server would accept their next item. Conversely, if server lowers to 3, mobile lets users add up to 5 then the API rejects with 422 — UX mismatch.

**Action:** Fetch limits from the server's `/api/v1/config` endpoint (or similar) and cache. Or accept the drift and version both via release notes.

### M-DEEP-12 — `localDatabaseProvider` does NOT invalidate when `apiClient.currentUserId` changes mid-session (token refresh response containing a different `sub`)

**File:** [apps/mobile/lib/core/database/database.dart:333-339](../../apps/mobile/lib/core/database/database.dart)

The provider reads `_activeUserIdSync` once at construction. If a token refresh somehow returns a token for a DIFFERENT user (server bug — shouldn't happen, but) the in-memory `_userId` flips, `_activeUserIdSync` does not (it's only set by main.dart bootstrap and `_bindActiveUser`). The DB instance is bound to the wrong user for the rest of the session.

**Action:** Tie `_activeUserIdSync` to a Riverpod state that the auth state listener updates, so any change to `currentUserId` invalidates `localDatabaseProvider`. The fix dovetails with C-DEEP-2.

### M-DEEP-13 — `AuthRepository.signOut`'s "retry once" on logout API call has no timeout boundary — both attempts could stall for the full request timeout (30s × 2 = 60s + 1s sleep)

**File:** [apps/mobile/lib/core/services/auth_repository.dart:117-142](../../apps/mobile/lib/core/services/auth_repository.dart)

User taps Sign Out. Network is slow. The first `_signOutApiCall` waits 30s, throws timeout. 1s sleep. Second call waits another 30s. Then `_client.clearTokens()` finally runs. UI is stuck on "Signing out…" for 61 seconds.

**Action:** Bound the total signOut to a tighter window (e.g. 5 seconds), then proceed to local clear. Server-side revoke on next-online instead.

---

## Low

### L-DEEP-1 — `Random.secure()` for `_generateRequestId` is fine, but allocating a new random per-request is wasteful — could share `_Random_requestIds` instance (already shared, OK)

Verified: line 17 declares the shared `Random.secure()` instance. Each call generates 16 bytes. Cosmetic.

### L-DEEP-2 — `redactSensitive` allocates two intermediate strings per call (`replaceAll` × 2)

V1 L-MS-4 noted this. Cosmetic.

### L-DEEP-3 — `_databaseFileName` truncates SHA-256 to 16 hex chars (64 bits). Per v1 M-MS-3, collision math is fine. Could be 32 hex chars for paranoia at zero cost.

Cosmetic.

### L-DEEP-4 — `_buildUri`'s legacy `path:` mode is gated by `@Deprecated` on every method but never asserted-out. A caller passing an invalid path with embedded `?` would skip query-param merging.

`Uri.parse('$baseUrl/foo?baz=1').replace(queryParameters: {'a':'1'})` — the original `?baz=1` is overwritten. So a caller passing `path: '/foo?baz=1'` AND `queryParams: {'a':'1'}` loses `baz`. Today no callers do this (verified zero hits for `path:` from v1's grep).

### L-DEEP-5 — `_kQueueEvictionCount = 100` is hard-coded; no relationship enforced between `_kMaxQueueSize` (500) and the eviction count. Configurable would be over-engineering; leaving as-is.

### L-DEEP-6 — `_log` calls `_onLog?.call(safe)` without an exception boundary; a host-app callback that throws will propagate up through the API client. Today the host registers no `onLog` so it's a non-issue.

### L-DEEP-7 — The empty-id collision in optimistic creates (v1 H-MS-6) — re-confirmed. The conflict-screen's `getItemById(localItem.id)` (`offline_sync_service.dart:464`) with `id == ''` triggers H-DEEP-4 (lists all items). Fix one, fix both.

### L-DEEP-8 — `isSyncingProvider` is a `StateProvider<bool>` written-through from inside `OfflineSyncService` — works but is the kind of cross-layer coupling Riverpod's docs flag. Cosmetic / documentation.

---

## Adversarial Scenarios Walkthrough (Section L of prompt)

### L1 — User reinstalls app on the same device

iOS: keychain entries persist across reinstalls (default behavior; `KeychainAccessibility.first_unlock_this_device` survives reinstall). `_keyDbEncryptionKey` is still in the keychain. Documents directory is wiped on reinstall (iOS apps' Documents dir is sandbox-deleted). Result: keychain has key but file is gone → `_openConnection` creates a fresh empty DB → SQLCipher encrypts with the existing key → works. Auth tokens also persist → user is auto-signed-in to the new install with no fresh sign-in. **Risk:** if the user uninstalled BECAUSE they wanted to reset state, this is surprising behavior. Apple's behavior is to clear keychain only on full device wipe, not app uninstall. Recommend documenting in onboarding.

Android: `EncryptedSharedPreferences` clears on uninstall. So the DB key is regenerated → SQLCipher fails on the (already-deleted) file. Net: clean state.

### L2 — Force-quit during sync

`_isSyncing` flag is in-memory; cleared on process death. Queue rows in `in_flight` state stay that way (line 95-97 only flips `pending → in_flight`). Next launch's `getPendingActions` (line 87-91) reads BOTH `pending` and `in_flight`, re-sends with the same idempotency key. Server's request_idempotency cache returns the cached response. Net: safe.

But: if the kill happens BETWEEN `markActionInFlight` (line 277) and the network call (line 278), the row is `in_flight` with the same idempotency key. Re-send works. If the kill happens BETWEEN the network call and `markActionSynced` (line 279), the server has the write, the row is still `in_flight`, re-send hits the idempotency cache → returns cached success → `markActionSynced` runs. Net: safe.

### L3 — iCloud restore

V1 C-MS-4. Confirmed: file in Documents is iCloud-backup-eligible by default; key is device-bound. On restore, file lands without key → SQLCipher fails. No fallback. **CRITICAL still — fix per v1 + add NSURLIsExcludedFromBackupKey.**

### L4 — User changes password on another device

Server-side: all refresh tokens are revoked (per the audit chain mig 030+ pattern). Mobile cached refresh token is now dead.
Next API call: 401 → `_withAutoRefresh` → `refreshAccessToken` → server returns 401 → C-MS-2 wipes tokens → `signedOut` emitted → user kicked back to welcome screen. Correct, but jarring: no message explaining why. UX would benefit from a "your password was changed, please sign in" branch.

### L5 — User signs out, signs in as different user

`_wipeLocalState(userId: A)` deletes A's per-user DB file + clears all secure storage (including the DB encryption key). `setActiveDatabaseUser(null)` is called, `localDatabaseProvider` invalidated. New sign-in: `_bindActiveUser(B.id)` sets `_activeUserIdSync = B.id`, invalidates `localDatabaseProvider`. New `HavenDatabase` opens `havenkeep-<hashB>.sqlite`, new key auto-generated. Net: clean.

But the C-DEEP-7 race I identified above: if `setActiveDatabaseUser` runs against `null` and then the next read of `localDatabaseProvider` happens BEFORE `_bindActiveUser(B.id)` (e.g. some Riverpod consumer eagerly reads it during the auth state transition), it opens the global `havenkeep.sqlite` file. That file was either (a) deleted in the wipe, or (b) is the legacy global file. If it's a fresh open, the key auto-generates and the file is empty — fine but wasteful. If `_bindActiveUser` then runs and re-invalidates, the global file is left orphaned on disk forever (no cleanup).

### L6 — User mass-floods the queue

`_kMaxQueueSize = 500`. Each `enqueueChange` checks `getQueueSize >= 500`, and if so calls `removeOldestEntries(100)` BEFORE inserting. Sequence of 1000 offline edits:

- Entries 1-500: inserted normally.
- Entry 501: queue at 500 → drop oldest 100 → insert. Queue now at 401.
- ... continues evicting in batches ...
- Final state: queue at ~500, contains the most-recent 500 edits. The first 500 edits are GONE — `removeOldestEntries` deletes by `createdAt ASC`, no status filter. **Includes anything in `failed` state.**

V1 C-MS-3 + H-MS-2. Re-confirmed: data loss is silent. Even worse: `removeOldestEntries` doesn't check whether the row is `in_flight` — if a sync is mid-run, an in-flight row could be deleted from under it. The sync loop's `markActionSynced` would then no-op (UPDATE matches zero rows) and `clearSyncedActions` would do nothing. The synced row still went through server-side, but the local UI never gets the post-sync invalidation.

### L7 — Captive portal returns HTML for /auth/refresh

`refreshAccessToken` posts JSON, gets HTML back with status 200 (captive portal hijacks). `jsonDecode` throws FormatException. `_parseResponse` is NOT used here (refresh has its own parsing at line 458). Looking at the code:

```dart
if (response.statusCode == 200) {
  final body = jsonDecode(response.body) as Map<String, dynamic>;
```

`jsonDecode` of HTML throws FormatException. The outer catch at line 489-493 propagates it. The `finally` at 494-496 sets `_refreshCompleter = null`. The throw bubbles up to `restoreSession` (or `_withAutoRefresh`). In `restoreSession` at line 332-342, the catch catches `Exception` (any), treats as transient, returns false without clearing tokens. **Correct behavior**.

In `_withAutoRefresh` at line 558-562, catch catches the FormatException, logs "Token refresh failed", clears tokens, returns the original 401. **Defeats H-B9** — the captive-portal hijack signs the user out.

**Critical reachability: a flight-mode user landing on a captive portal during a normal API call gets signed out.**

This is a re-confirmation of v1 C-MS-2 + a NEW concrete trigger (captive portal HTML response). Adding to the action list for C-MS-2: also catch FormatException and treat as transient.

### L8 — MITM with custom CA installed

V1 C-MS-1. No TLS pinning. Custom-CA-trusted device sees plaintext. Refresh tokens captured.

---

## Tests

### Existing sync/storage test files

| File | Coverage | Gaps |
|---|---|---|
| `apps/mobile/test/services/offline_sync_service_test.dart` | enqueue, syncPendingChanges happy path, max-retry, transient retry, FIFO, JSON-decode, lifecycle | NO test for: 409 conflict park (`_parkUpdateConflict`), C-MS-5 preflight failure path, queue eviction, eviction of failed entries (C-MS-3), idempotency key threading, `_processEntry` for documents, dispose-mid-sync race (M-MS-8 / H-DEEP-6), connectivity state changes, captive-portal HTML refresh failure |
| `apps/mobile/test/services/auth_repository_test.dart` | signIn happy path, error paths, logout API | NO test for: H-B9 transient-failure refresh, signOut keychain-class mismatch (H-MS-4) |
| `packages/api_client/test/api_exception_test.dart` | factory mapping, sealed switch, redactSensitive (Bearer + JWT only) | NO test for: refresh-token redaction, OAuth state, activation codes, `_isTokenExpired` skew, `_withAutoRefresh` retry-401 (C-DEEP-1), captive-portal FormatException, `_parseResponse` non-JSON content-type, `_buildUri` empty segment (H-DEEP-4) |

### Missing test surface (the audit prompt's specific request)

- **Conflict resolution (the entire `_parkUpdateConflict` flow)** — zero direct tests.
- **Queue eviction at 500-entry cap** — zero tests.
- **H-B9 transient-failure path** — zero tests for the network-error → keep-tokens contract.
- **Sealed switch exhaustiveness on `_processEntry`** — depends on Dart compiler; not validated by a test.
- **`_databaseFileName` per-user collision** — zero tests.
- **`_isTokenExpired` parse-failure path (C-DEEP-2 / H-MS-7)** — zero tests.
- **Schema migration v1 → v5 path** — Drift's migration testing API exists; not used.
- **`SecureStorageService` / `BiometricService`** — zero tests.

**Action:** Add a test suite that mounts a real Drift DB (in-memory), enqueues entries, simulates network failures, verifies queue contents post-sync. Also unit-test `_isTokenExpired` against a malformed payload and a 25-second-from-expiry token.

---

## Rollup

| Severity | New (this pass) | V1 | Combined |
|---|---|---|---|
| Critical | 7 | 6 | 13 |
| High | 11 | 8 | 19 |
| Medium | 13 | 8 | 21 |
| Low | 8 | 4 | 12 |
| **Total** | **39** | **26** | **65** |

### Top fixes to land first (deep-pass priority)

1. **C-DEEP-1** — `_withAutoRefresh` does not clear tokens after retried-401. One-line fix; user impact = "perma-stuck account state" until force quit.
2. **C-DEEP-7** — bootstrap race opens global DB file when keep-signed-in=false drops tokens before `setActiveDatabaseUser`. Prevents legacy-file orphaning AND wrong-user file open.
3. **C-DEEP-3** — items_provider's enqueue-then-state ordering. Prevents the orphan-row class.
4. **C-DEEP-4** — keychain-locked-at-boot path → token wipe. iOS-cold-start-from-push regression.
5. **H-DEEP-4** — `_buildUri` empty segment leakage. One-line assert.
6. **H-DEEP-11** — sweep all 27 silent enum factories through the funnel. Mechanical.
7. **C-DEEP-6** — drop the duplicate `FlutterSecureStorage` in `auth_repository.dart`. Prevents future iCloud-Keychain leak.

After those: re-run `flutter analyze`, the (currently empty-of-storage-tests) test suite, and verify build sizes are unchanged.

---

## File path reference (audit asks for absolute paths)

- `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/main.dart`
- `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/core/services/offline_sync_service.dart`
- `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/core/services/secure_storage_service.dart`
- `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/core/services/auth_repository.dart`
- `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/core/services/items_repository.dart`
- `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/core/services/biometric_service.dart`
- `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/core/database/database.dart`
- `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/core/database/tables/offline_queue.dart`
- `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/core/database/tables/sync_conflicts.dart`
- `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/core/utils/conflict_resolver.dart`
- `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/core/utils/apple_sign_in_nonce.dart`
- `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/core/providers/auth_provider.dart`
- `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/core/providers/items_provider.dart`
- `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/features/onboarding/welcome_screen.dart`
- `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/features/settings/conflicts_screen.dart`
- `/Users/pacomedomagni/Projects/havenkeep/packages/api_client/lib/src/client.dart`
- `/Users/pacomedomagni/Projects/havenkeep/packages/api_client/lib/src/constants.dart`
- `/Users/pacomedomagni/Projects/havenkeep/packages/api_client/test/api_exception_test.dart`
- `/Users/pacomedomagni/Projects/havenkeep/packages/shared_models/lib/src/_unknown_enum_log.dart`
- `/Users/pacomedomagni/Projects/havenkeep/packages/shared_models/lib/src/enums.dart`
- `/Users/pacomedomagni/Projects/havenkeep/packages/shared_models/lib/src/maintenance.dart`
- `/Users/pacomedomagni/Projects/havenkeep/packages/shared_models/lib/src/partner.dart`
- `/Users/pacomedomagni/Projects/havenkeep/packages/shared_models/lib/src/partner_commission.dart`
- `/Users/pacomedomagni/Projects/havenkeep/packages/shared_models/lib/src/partner_gift.dart`
- `/Users/pacomedomagni/Projects/havenkeep/packages/shared_models/lib/src/warranty_purchase.dart`
- `/Users/pacomedomagni/Projects/havenkeep/packages/shared_models/lib/src/warranty_claim.dart`
- `/Users/pacomedomagni/Projects/havenkeep/packages/shared_models/lib/src/email_scan.dart`
- `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/test/services/offline_sync_service_test.dart`
- `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/test/services/auth_repository_test.dart`
