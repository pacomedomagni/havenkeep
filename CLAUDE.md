# HavenKeep — Project Rules + Outstanding Work

This is the primary markdown file in the repo. It carries:
1. Non-negotiable rules every Claude Code session must follow.
2. Stack quick-reference for orientation.
3. The outstanding-work ledger — every task left after the audit-remediation pass.

When something here is done, delete the entry. Don't park new TODOs in code or in scattered notes — keep them here.

The only other markdown file allowed in the repo is `apps/mobile/IOS_DEPLOYMENT.md` — the iOS → TestFlight runbook lives next to the app it deploys. Any other `*.md` file is a violation of Rule 3 and must be folded into CLAUDE.md or deleted.

---

## Part 1 — The five rules (non-negotiable)

### 1. Never leave tech debt
When you change code, the area you touched leaves cleaner than you found it. Unused imports get removed, stale `// TODO` / `// FIXME` / `// HACK` markers get resolved or deleted, half-finished abstractions get finished or removed, redundant code gets collapsed. You do not ship "good enough" — you ship done.

### 2. Never implement backfill logic — even if the change is breaking
No migration shims, no compat branches, no "if-old-shape-then" fallbacks, no dual-read/dual-write paths, no feature flags that exist just to keep old behavior alive. When a contract changes, update every caller in the same change. Breaking changes are acceptable; backfill to hide them is not.

### 3. Never leave legacy or dead code — purge it
When code is replaced, the old version is deleted in the same change. Not commented out. Not parked with a `// deprecated`. Not renamed to `_oldFoo`. Gone. Same rule for unreferenced functions, unreachable branches, commented-out blocks, and any code path no caller exercises. If you're not sure something is used, grep first. If nothing references it, delete it.

### 4. ALL means ALL — you do not decide what to defer
You do not unilaterally call work "out of scope," "for a later pass," "follow-up," "nice-to-have," or "optional." If the work is implied by the task, it's part of the task. "Out of scope" is a decision only the user can make. When you believe something should be deferred, ask the user. Don't assume, don't silently shrink the change, and don't narrate the skip as if it's done.

### 5. Ship with zero errors and zero warnings
The final state of any change is lint-clean, typecheck-clean, and warning-free across every tool that runs on the affected code:
- **Backend (`apps/api`)**: `npx tsc --noEmit` + `npm test`
- **Marketing (`apps/marketing`)**: `npm run build` (Astro)
- **Partner dashboard (`apps/partner-dashboard`)**: `npm run build`
- **Mobile (`apps/mobile`)**: `flutter analyze` + `flutter test` + `flutter build apk --debug`
- **Shared packages (`packages/*`)**: lint + typecheck via the consuming app's pipeline

If you encounter pre-existing errors or warnings in files you're touching (or adjacent to your work), you fix them. "Warnings that were already there" is not an acceptable excuse.

### How to apply these rules
- Before starting a task, enumerate everything it touches — if that enumeration surfaces work that feels "out of scope," ask, don't trim.
- Before finishing, sweep the files you touched: delete unused imports, kill dead branches, resolve TODOs, ensure typecheck/lint/tests/analyzer pass clean.
- If a rule and a shortcut conflict, the rule wins.
- If a rule and a user instruction conflict, the user instruction wins — but ask them to acknowledge the rule is being overridden.

---

## Part 2 — Stack quick-reference

Monorepo, pnpm + npm hybrid (mobile is its own pubspec workspace).

- **`apps/mobile`** — Flutter (Dart SDK `^3.0.0`). Riverpod, Dio (via `api_client`), `sqflite_sqlcipher`, `flutter_dotenv` for env config (NOT dart-defines). Bundle ID `app.havenkeep.mobile` on both iOS and Android.
- **`apps/api`** — Express + Postgres (raw `pg` client, NOT Prisma). JWT auth with refresh tokens. Routes per feature (`src/routes/*`). Logging via pino → Loki. No Sentry.
- **`apps/marketing`** — Astro static site. Tailwind dark theme. Hosts `/legal/*` and `/delete-account` for store compliance. Sitemap + RSS shipped. CSP/X-Frame headers expected via Caddy in front of the static host.
- **`apps/partner-dashboard`** — Next.js admin/partner portal. Same-origin proxy at `/api/v1/[...path]` with header allowlist + double-submit CSRF on mutations.
- **`packages/shared_models`** — Dart models shared between mobile and any other Dart consumer. Hydrate-render tested.
- **`packages/api_client`** — Dart wrapper around Dio for talking to the Express API. `pathSegments` API; sealed `ApiException` hierarchy with 9 typed subclasses; `idempotencyKey` parameter on every mutating method.
- **`packages/shared_ui`** — Dart UI primitives (cards, buttons, color tokens) consumed by `apps/mobile`.

### Auth specifics
Three sign-in paths, all terminating at the Express API:
- **Email/password** — `/api/v1/auth/register`, `/login`, `/refresh`. bcrypt with SHA-256 pre-hash so >72-byte passwords still use full entropy.
- **Google Sign-In** — mobile uses the native SDK with `serverClientId`. Backend `/auth/google` accepts an array of audiences via `config.google.clientId` + `GOOGLE_AUDIENCES` env.
- **Apple Sign-In** — iOS uses the native SDK; Android (and any web/desktop client) uses `WebAuthenticationOptions` with an Apple Developer Services ID. The backend `/auth/apple` endpoint accepts both audiences via `config.apple.bundleId` (single) + `config.apple.servicesIds` (comma-sep array).

Per-environment Services IDs follow the convention:
- `app.havenkeep.mobile.signin.staging`
- `app.havenkeep.mobile.signin`

### Mobile signing
- **iOS**: Xcode auto-signing under your Apple Developer team.
- **Android**: upload key at `apps/mobile/android/app/upload-keystore.jks` (gitignored) with credentials in `apps/mobile/android/key.properties` (also gitignored). Play App Signing re-signs on Google's end.
- Both `google-services.json` and `GoogleService-Info.plist` are gitignored — each developer downloads the latest from Firebase Console for their environment.

### Telemetry
- Server: pino → Loki. Redact paths cover bearer tokens, refresh tokens, OAuth access tokens, base64 image bodies, password hashes, Stripe webhook secrets.
- Mobile: `dart:developer.log` is the always-on transport. `registerUnknownEnumReporter` in `shared_models` lets the bootstrap plug in a custom transport (e.g. Firebase Crashlytics breadcrumb) without coupling the model layer to any specific SDK.
- Webhook events table tracks delivery + retries with dead-letter at attempt 8.

### DB migrations
27 numbered migrations live in `apps/api/src/db/migrations/`: 028–039 (security/data-loss criticals), 040–045 (DB foundation), 050–051 (payments + uploads), 060–067 (services), 070 (drift constraints), 071 (partner status enum), 072–074 (digest outbox / welcome email open / category repair-cost defaults). Runner auto-detects `ALTER TYPE ADD VALUE` and `CREATE INDEX CONCURRENTLY` and runs those files outside transactions. `schema_version` table tracks bootstrap completion.

---

## Part 3 — Outstanding work

Every gate is currently green: api tsc, dashboard tsc + build, marketing build, both Dart packages analyze, mobile analyze, 444 flutter tests, debug APK build all pass. The list below is what the audit work left genuinely unaddressed.

### A. Gated on infra you control (not code defects)

- **`apps/api npm test` execution.** Tests typecheck and the helpers + setup + 30+ new test files all wire up correctly, but the suite needs a `havenkeep_test` Postgres on `:5432`. The `fortify-postgres-1` container holds that port locally. Either free the port + `createdb havenkeep_test && cd apps/api && npm run db:migrate && npm test`, or update `__tests__/setup.ts` to read `TEST_DB_PORT` and run a sidecar Postgres on a free port. The TRUNCATE guard refuses to run unless `DB_NAME` contains "test".
- **Production CSP report-uri / CSP enforcement headers** (W078 / W111). Marketing site is static Astro — the headers must be set by Caddy in front of it. `astro.config.mjs` documents which headers Caddy needs.
- **Firebase Crashlytics DSN** (optional). The Dart enum-drift funnel (`registerUnknownEnumReporter`) is wired and ready for a custom transport.

### B. Mobile feature gaps

All audit-flagged mobile gaps have been closed in this branch. The list previously here covered: inline maintenance log on item detail, calendar-month history view, due-window filter chips + bulk mark-done, home recent-activity feed, email-scanner UX (cancel mid-scan / granted-scopes display / in-app disconnect / low-confidence review queue), and Ch05-F098 splash tap-to-retry. All shipped — re-add entries here if a regression surfaces.

### C. App Store / Play Store submission

Code-side everything is ready: bundle ID `app.havenkeep.mobile`, iOS PrivacyInfo.xcprivacy with required-reasons APIs + data collection categories, APNs entitlement, Apple Sign-In + Associated Domains entitlements, complete Info.plist permission strings + `ITSAppUsesNonExemptEncryption=false`, all marketing legal pages (`/legal/privacy`, `/legal/terms`, `/legal/delete-account`, `/cookies`, `/security`), and a `/support` page (App Store Support URL). Universal Links + App Links manifest files exist at `apps/marketing/public/.well-known/`.

The remaining work is **off-platform configuration only** — no code blocks shipping:

1. **Apple Team ID** — fill into `apps/marketing/public/.well-known/apple-app-site-association` (replace `TEAMID` placeholder, in two spots). Get from Apple Developer Account → Membership.
2. **Android signing fingerprints** — fill into `apps/marketing/public/.well-known/assetlinks.json` (replace `REPLACE_WITH_UPLOAD_KEY_SHA256` and `REPLACE_WITH_PLAY_APP_SIGNING_SHA256`). Get upload key from `keytool -list -v -keystore upload-keystore.jks`; get Play App Signing fingerprint from Play Console → App Integrity.
3. **Caddy MIME type for `/.well-known/apple-app-site-association`** — Apple requires `Content-Type: application/json` and the file MUST NOT have an extension. Add `header /.well-known/apple-app-site-association Content-Type application/json` to the Caddy config in front of marketing.
4. **Firebase config files** — download fresh `GoogleService-Info.plist` and `google-services.json` from Firebase Console and place them at `apps/mobile/ios/Runner/GoogleService-Info.plist` and `apps/mobile/android/app/google-services.json`. Both are gitignored.
5. **Reversed Google Client ID** — replace `com.googleusercontent.apps.REPLACE-WITH-CLIENT-ID` in `apps/mobile/ios/Runner/Info.plist` (CFBundleURLSchemes) with the value from `GoogleService-Info.plist` `REVERSED_CLIENT_ID`.
6. **Apple Sign-In Services IDs** — create `app.havenkeep.mobile.signin` and `app.havenkeep.mobile.signin.staging` in Apple Developer portal under Identifiers → Services IDs. Configure each with the marketing domain as the Web Authentication redirect URL.
7. **App Store Connect** — create app record with bundle ID `app.havenkeep.mobile`. Privacy URL: `https://havenkeep.com/legal/privacy`. Support URL: `https://havenkeep.com/support`. Marketing URL (optional): `https://havenkeep.com`. Account Deletion: in-app via Settings → Delete Account. Privacy Nutrition Label: mirror the categories declared in `PrivacyInfo.xcprivacy`.
8. **Play Console** — create app with package name `app.havenkeep.mobile`. Privacy Policy: `https://havenkeep.com/legal/privacy`. Data Safety form: mirror `PrivacyInfo.xcprivacy` categories. Account deletion: in-app + `https://havenkeep.com/legal/delete-account`. Target API level 35 is auto-met by Flutter 3.41+.
9. **Adaptive Android launcher icon** (polish, not blocking) — current Android icon is the legacy `mipmap-*/ic_launcher.png` only. For Android 8+ (min SDK 26+) consider adding `mipmap-anydpi-v26/ic_launcher.xml` + foreground/background layers. Cleanest path: add `flutter_launcher_icons` dev dep, configure with the existing `assets/icons/app-icon.png`, run `dart run flutter_launcher_icons`.
