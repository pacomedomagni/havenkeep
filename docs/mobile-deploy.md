# HavenKeep mobile — deploy guide

Everything you need to ship to TestFlight + Play Internal Testing tomorrow. Follows the same pattern as Restorae (already shipped). Skim section 1 first; the rest is reference.

## TL;DR — bundle IDs and signing

| Field | Value |
| --- | --- |
| iOS bundle ID | `com.flokou.havenkeep` |
| Android `applicationId` | `com.flokou.havenkeep` |
| Android upload-key SHA-1 | `80:54:BE:DD:DE:2F:5D:D7:73:F7:33:AE:D1:0A:D1:56:2A:33:DA:89` |
| Android debug SHA-1 | `EB:8A:74:33:4B:5A:1B:8F:2A:FA:FA:54:5A:F1:11:95:75:07:E9:C5` |
| Keystore + password | `apps/mobile/android/app/upload-keystore.jks` + `key.properties` (both gitignored) |
| Fastlane lane | `cd apps/mobile/android && fastlane internal` |

---

## 1. Tomorrow's manual steps (in order)

### Step 0 — Fix the Android dep that blocks the build

The Android scaffolding is in place but `flutter_web_auth_2:3.1.2` (used by the Outlook email scanner) doesn't compile against the current AGP version. You must bump it before any Android build will succeed.

```diff
- flutter_web_auth_2: ^3.1.0
+ flutter_web_auth_2: ^5.0.0
```

Then update `apps/mobile/android/app/src/main/AndroidManifest.xml` — add inside `<application>`:

```xml
<activity android:name="com.linusu.flutter_web_auth_2.CallbackActivity" android:exported="true">
    <intent-filter android:label="flutter_web_auth_2">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="${appAuthRedirectScheme}" />
    </intent-filter>
</activity>
```

And in `android/app/build.gradle.kts` `defaultConfig` block, add:

```kotlin
manifestPlaceholders["appAuthRedirectScheme"] = "<the-scheme-from-OUTLOOK_REDIRECT_URI>"
```

`<the-scheme-from-OUTLOOK_REDIRECT_URI>` is the URI scheme prefix from the `OUTLOOK_REDIRECT_URI` env var (e.g. for `havenkeep://outlook/callback` it's `havenkeep`). v5's API for `FlutterWebAuth2.authenticate(url:, callbackUrlScheme:)` is identical to v3, so `email_oauth_service.dart` doesn't need changes.

Then `flutter pub get && flutter build apk --debug` should succeed.

### Step 1 — Firebase project

[console.firebase.google.com](https://console.firebase.google.com) → **Add project** → name "HavenKeep" → enable Analytics → Create.

After creation:

- Add Android app: package name `com.flokou.havenkeep`, register, **Download `google-services.json`**, save it as `apps/mobile/android/app/google-services.json` (overwriting any existing).
- Add iOS app: bundle ID `com.flokou.havenkeep`, register, **Download `GoogleService-Info.plist`**, save as `apps/mobile/ios/Runner/GoogleService-Info.plist`.
- Authentication → Sign-in method → enable Google + Apple.
- Project settings → Android app → **Add fingerprint** (twice):
  - `EB:8A:74:33:4B:5A:1B:8F:2A:FA:FA:54:5A:F1:11:95:75:07:E9:C5` (debug)
  - `80:54:BE:DD:DE:2F:5D:D7:73:F7:33:AE:D1:0A:D1:56:2A:33:DA:89` (upload key)
- **Re-download `google-services.json`** after both fingerprints are added (otherwise `oauth_client[]` is empty and Google Sign-In fails on Android).
- Note the **Web OAuth client ID** Firebase auto-creates (visible in the re-downloaded `google-services.json` under the `client_type: 3` entry) — that's the value for `GOOGLE_SERVER_CLIENT_ID` dart-define.
- Update `apps/mobile/lib/firebase_options.dart` and `apps/mobile/firebase.json` with the new project values (the simplest path is to install FlutterFire CLI and run `flutterfire configure --project=<new-project-id>`).
- Update `apps/mobile/ios/Runner/Info.plist` `CFBundleURLSchemes`: replace the placeholder `com.googleusercontent.apps.REPLACE-WITH-CLIENT-ID` with the `REVERSED_CLIENT_ID` from the new `GoogleService-Info.plist`.

### Step 2 — Apple Developer Portal

[developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers/list)

- Confirm App ID for `com.flokou.havenkeep` exists. If not, register it: **+** → App IDs → App → Bundle ID `com.flokou.havenkeep` → enable **Sign In with Apple** + **Push Notifications** capabilities.

For Apple Sign-In on Android (web flow), also create:

- **Identifiers → +** → Services IDs → identifier `com.flokou.havenkeep.signin.staging` (and another `.signin` for prod when prod DNS is up). Configure each with:
  - Primary App ID: `com.flokou.havenkeep`
  - Domains: your havenkeep domain
  - Return URL: `https://api.<env>.havenkeep.app/api/v1/auth/apple/callback`
- **Keys → +** → Sign in with Apple → Configure → tie to the Services ID → download the `.p8` (one-shot — store carefully). Note the Key ID + Team ID.

### Step 3 — App Store Connect

[appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **My Apps** → confirm Restorae's HavenKeep app exists for `com.flokou.havenkeep` (you mentioned 8 TestFlight builds already exist, so this should be there). If not, **+** → New App → bundle ID `com.flokou.havenkeep`.

Fill in the bare minimum for TestFlight: **App Information** (name, primary category: Productivity, secondary: Utilities), **Privacy Policy URL** (`https://havenkeep.app/legal/privacy` once your marketing site is published).

### Step 4 — Play Console (NEW for havenkeep)

[play.google.com/console](https://play.google.com/console) → **Create app** → name HavenKeep → free → accept declarations → Create.

The full one-time setup mirrors Restorae (we did this today):
1. **Policy and programs → App content** — go through every section (App access, Ads, Content rating, Target audience, News apps, COVID-19, Data safety, Government apps, Health apps).
2. For the Health apps form: **My app does not have any health features** (warranty tracker, not health).
3. Privacy policy URL: `https://havenkeep.app/legal/privacy` (you have it at `apps/marketing/src/pages/legal/privacy.astro`, just confirm it's published).
4. Target audience: **18 and over** OR **13 and older** depending on whether teens would reasonably use a warranty tracker (probably 13+ matches market reality).
5. Data safety form: declare collected data (email, user ID, photos for receipts, app activity, crash logs) — none shared, all encrypted in transit, deletion supported.
6. **Grow → Store presence → Store settings**: category Productivity (or Tools), tags **Notebook**, **Productivity** (Play tags don't have warranty/receipt-specific options).
7. **Grow → Store presence → Main store listing**: paste copy from §3 below; upload assets from `apps/mobile/android/store-assets/` (regenerate with `./scripts/regen-android-store-assets.sh` if you want a fresh feature graphic).
8. **Test and release → Setup → App signing**: Play auto-creates this on first upload.
9. **Users and permissions → Invite users**: add `play-publisher@restorae-id.iam.gserviceaccount.com` (the same service account JSON you have at `~/.secrets/google-play-service-account.json`) with at least **Release to testing tracks** permission.

### Step 5 — Build + upload AAB

```sh
cd apps/mobile
flutter build appbundle --release \
  --dart-define=API_BASE_URL=<staging URL> \
  --dart-define=WEB_FRONTEND_URL=<staging marketing URL> \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<new Web client ID> \
  --dart-define=APPLE_SERVICES_ID=com.flokou.havenkeep.signin.staging \
  --dart-define=APPLE_REDIRECT_URI=https://api.staging.havenkeep.app/api/v1/auth/apple/callback

cd android && fastlane internal
```

Then Play Console → Internal testing → **Start rollout to Internal testing**.

After rollout, copy the **Play App Signing SHA-1** from Play Console → Setup → App signing → add it as a third fingerprint to Firebase → re-download `google-services.json` → bake into the next AAB → re-upload.

### Step 6 — Build + upload IPA

```sh
cd apps/mobile
flutter build ipa --release \
  --dart-define=<same dart-defines as above>
open -a Transporter build/ios/ipa/havenkeep_mobile.ipa
```

Click **Deliver** in Transporter. Wait ~10-30 min. App Store Connect → TestFlight → add testers → install.

---

## 2. Screenshots — capture flow

Play needs at least 2; Apple needs 5 at 6.9". Run the app on a 1290×2796 simulator (iPhone 16 Pro Max), capture each of these screens:

1. Onboarding / launch
2. Home screen (item list)
3. Add item wizard / camera scanner
4. Item detail with warranty info
5. Notification or maintenance reminder

Save them to `apps/marketing/public/screenshots/` (parallel to Restorae's pattern). Then re-run `./scripts/regen-android-store-assets.sh` after we add screenshot-cropping support to it. For now, upload directly to each store via console UI.

---

## 3. Store listings copy (drafts — edit before submitting)

### Apple App Store

**App name** (30 max): `HavenKeep`
**Subtitle** (30 max): `Your warranties. Protected.`
**Promotional text** (170 max):
> Track every receipt and warranty in one place. Photo-scan receipts, get reminded before warranties expire, never lose proof of purchase again.

**Description** (4000 max):
```
HavenKeep keeps track of your warranties, receipts, and proof-of-purchase so you don't have to dig through emails or shoeboxes when something breaks.

WHAT'S INSIDE

• Photo-scan receipts and product manuals — HavenKeep extracts the warranty period automatically.
• Email scanner connects to your Gmail or Outlook (with your permission) and finds purchase confirmations you forgot about.
• Warranty expiry reminders — get a notification before coverage runs out.
• Maintenance reminders for things like filter changes, tune-ups, or annual service.
• Gift tracking — save warranties on items you've given to family.

PRIVACY

Your receipts, photos, and warranty data are encrypted on our servers and visible only to you. Email scans happen with read-only access; we never send mail or change your inbox. Delete your account from inside the app any time.

PREMIUM (optional)

Unlimited items, unlimited email scans, advanced search. Free tier covers most households comfortably.

Questions: support@havenkeep.app
Privacy: https://havenkeep.app/legal/privacy
```

**Keywords** (100 max, comma-sep, no spaces):
```
warranty,receipt,scanner,proof of purchase,reminder,gmail,outlook,home,gift,notebook
```

**Category**: Productivity (primary), Utilities (secondary)
**Age rating**: 4+ (no objectionable content)

### Google Play Store

**App name** (30 max): `HavenKeep`
**Short description** (80 max):
```
Track every receipt and warranty. Photo-scan, email-scan, expiry reminders.
```

**Full description** (4000 max): same as Apple description above, with a footer:
```
Privacy: https://havenkeep.app/legal/privacy
Terms: https://havenkeep.app/legal/terms
```

**Category**: Productivity
**Tags** (max 5, available options): Notebook, Productivity, Tools

---

## 4. Reference

- **What I set up tonight**: Android scaffold (`flutter create --platforms=android`), bundle ID `com.flokou.havenkeep`, AndroidManifest with proper permissions (camera, photo library, notifications, biometric, exact alarms, vibrate), upload keystore + key.properties (gitignored), Fastlane lanes (`internal` / `alpha` / `production` / `validate`), store-asset regen script, iOS export-compliance key in Info.plist.
- **What's gitignored**: `apps/mobile/android/app/upload-keystore.jks`, `apps/mobile/android/key.properties`, `**/google-services.json`, `**/GoogleService-Info.plist`, `**/lib/firebase_options.dart`, `apps/mobile/android/store-assets/`.
- **Critical dependency to bump**: `flutter_web_auth_2: ^3.1.0` → `^5.0.0` (see Step 0).
- **Service-account JSON for Play**: reuses `~/.secrets/google-play-service-account.json` from Restorae. Same Google developer account → works for both.
- **Apple App Store Connect API key**: not yet set up. We're using Transporter for now (drag-drop). Generate one when you want full CLI iOS deploy: ASC → Users and Access → Keys → Team Keys.
