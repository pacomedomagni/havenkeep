# HavenKeep — Project Rules + Outstanding Work

This is the primary markdown file in the repo. It carries:
1. Non-negotiable rules every Claude Code session must follow.
2. Stack quick-reference for orientation.
3. The outstanding-work ledger — every task left after the audit-remediation pass.

When something here is done, delete the entry. Don't park new TODOs in code or in scattered notes — keep them here.

Other markdown files allowed in the repo:
- `apps/mobile/IOS_DEPLOYMENT.md` — iOS → TestFlight runbook lives next to the app it deploys.
- `apps/mobile/store/STORE_LISTING.md` — App Store + Play Store listing copy (titles, descriptions, keywords, privacy questionnaires).
- `apps/mobile/store/PLAY_CONSOLE_ANSWERS.md` — Pre-filled answers for Play Console's App Content + Data Safety forms.
- `apps/mobile/store/APP_REVIEW_NOTES.md` — Demo account credentials + reviewer walkthrough script for App Review.

Any other `*.md` file is a violation of Rule 3 and must be folded into one of the files above or deleted.

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

### Email scanner OAuth
- **Gmail** — mobile opens `accounts.google.com/o/oauth2/v2/auth`, captures `code`, forwards `code + redirect_uri` to `/api/v1/email-scanner/scan`. The API exchanges them server-side using `client_secret`.
- **Outlook** — same shape. The Azure AD app **must** be registered as a confidential / web client (not "public client"), because the API redeems the code with `client_secret`. The mobile flow intentionally does NOT send PKCE (`code_challenge`); the API never sees a verifier and Microsoft would reject a half-completed PKCE handshake.

Per-environment Services IDs follow the convention:
- `app.havenkeep.mobile.signin.staging`
- `app.havenkeep.mobile.signin`

### Mobile signing
- **iOS**: Xcode auto-signing under your Apple Developer team.
- **Android**: upload key at `apps/mobile/android/app/upload-keystore.jks` (gitignored) with credentials in `apps/mobile/android/key.properties` (also gitignored). Play App Signing re-signs on Google's end.
- Both `google-services.json` and `GoogleService-Info.plist` are gitignored — each developer downloads the latest from Firebase Console for their environment.

### Telemetry
- Server: pino → Loki. Redact paths cover bearer tokens, refresh tokens, OAuth access tokens, base64 image bodies, password hashes, Stripe webhook secrets.
- Mobile: `dart:developer.log` is the always-on transport. **Firebase Crashlytics is wired** in [main.dart](apps/mobile/lib/main.dart) — release builds enable collection, debug builds skip it. `FlutterError.onError` forwards fatal framework errors via `recordFlutterFatalError`; `PlatformDispatcher.instance.onError` records platform errors as fatal; the outer `runZonedGuarded` catch records anything else as non-fatal. `registerUnknownEnumReporter` in `shared_models` writes a Crashlytics breadcrumb (`enum_drift: …`) for every unknown server enum — useful for "we shipped a server change, then it crashed five seconds later" forensics. All Crashlytics calls are gated on a `_crashlyticsReady` flag so a developer build with no Firebase API key still works.
- Webhook events table tracks delivery + retries with dead-letter at attempt 8.

### DB migrations
Numbered migrations live in `apps/api/src/db/migrations/`: 028–039 (security/data-loss criticals), 040–045 (DB foundation), 050–051 (payments + uploads), 060–067 (services), 070 (drift constraints), 071 (partner status enum), 072–074 (digest outbox / welcome email open / category repair-cost defaults), 075–081 (audit-chain casts, request idempotency, MinIO object keys, audit-chain advisory lock, audit-logs description cap), 082 (re-applies audit-trigger casts + advisory lock together — fixes audit C1 where 080 regressed 075's enum/UUID casts), 083 (warranty_*.user_id RESTRICT→SET NULL + denormalized email columns for purge anonymization — audit C4), 084 (user_mfa_factors + user_mfa_backup_codes for TOTP enrollment — audit S-C2), 085 (drop dead documents.deleted_at column — H-D3), 086 (drop redundant plaintext partner_gifts.activation_code UNIQUE — H-D4), 087 (webhook_events.id → bigint — H-D5), 088 (email_scans.completion_message — H-D7), 089 (chargeback_status regex CHECK — H-D8), 090 (category_defaults.lifespan_years seeded from items.ts hardcoded map — H-C2), 091 (audit_logs.user_email → VARCHAR(320) — M-D2), 092 (partners is_active/status invariant CHECK — M-D4), 093 (documents.file_size non-negative CHECK — M-NEW-5), 094 (drop redundant idx_newsletter_subscribers_email — M-NEW-6). Runner auto-detects `ALTER TYPE ADD VALUE` and `CREATE INDEX CONCURRENTLY` and runs those files outside transactions; the runner now also wraps `main()` in `pg_advisory_lock` (H-D1) so two replicas booting simultaneously can't race on the same DDL. `schema_version` table tracks bootstrap completion.

---

## Part 3 — Outstanding work

Every gate is currently green: api tsc + 305/305 jest tests, dashboard tsc + build, marketing build, both Dart packages analyze, mobile analyze, 444 flutter tests, debug APK build all pass. The 2026-04-29 audit-remediation arc is closed (145 findings → 145 dispositions; see `git log --oneline` if you need the per-finding history).

**No outstanding code-level work.** All in-repo follow-ups (S-M7 public CSRF mint, Phase-5 activation-code wipe) shipped on `main`. The remaining items below are off-platform configuration that has to happen on Stripe / Apple / Google / your prod host — there's no code change that unblocks them.

### A. App Store / Play Store submission (off-platform configuration)

Code-side everything is ready: bundle ID `app.havenkeep.mobile`, Apple Team ID `N3RF2GHS99` wired into AASA + Xcode signing, upload-key SHA-256 wired into `assetlinks.json`, iOS PrivacyInfo.xcprivacy with required-reasons APIs + data collection categories, APNs entitlement, Apple Sign-In + Associated Domains entitlements, complete Info.plist permission strings + `ITSAppUsesNonExemptEncryption=false`, all marketing legal pages (`/legal/privacy`, `/legal/terms`, `/legal/delete-account`, `/cookies`, `/security`), a `/support` page (App Store Support URL), Caddy AASA MIME-type + CSP headers, and an adaptive Android launcher icon. Universal Links + App Links manifest files at `apps/marketing/public/.well-known/`.

**AASA scope** (4.8): `/gift/*` and `/referral/*` are the only paths that universal-link into the app. `/verify-email`, `/reset-password`, `/verify-email-change` are intentionally web-only — the user may click those links on a laptop / work phone / family member's phone, so opening the HavenKeep app on a different device is the wrong UX. Those endpoints land on the marketing site's auth UI. Adding in-app screens for them later means: (a) extend the `components:` array in `apps/marketing/public/.well-known/apple-app-site-association`, (b) extend `apps/marketing/public/.well-known/assetlinks.json` similarly for Android, and (c) wire the route in `apps/mobile/lib/core/services/deep_link_service.dart`.

The remaining work is **off-platform configuration only**:

1. **Play App Signing fingerprint** — after the first AAB upload, copy the SHA-256 from Play Console → App integrity → App signing key fingerprint and replace `REPLACE_WITH_PLAY_APP_SIGNING_SHA256` in `apps/marketing/public/.well-known/assetlinks.json`. The upload-key fingerprint (`70:21:27:A4:…`) is already wired.
2. **Firebase Crashlytics live keys** — `firebase_options.dart` reads `FIREBASE_ANDROID_API_KEY` / `FIREBASE_IOS_API_KEY` from `.env.<flavor>`. With placeholder keys, Crashlytics initialises but reports stop at the device. Drop real values into `apps/mobile/.env.production` (and rerun `scripts/prepare-env.sh production` before `flutter build`). Optionally also place fresh `GoogleService-Info.plist` and `google-services.json` from Firebase Console at `apps/mobile/ios/Runner/` and `apps/mobile/android/app/`; both are gitignored.
3. **Reversed Google Client ID** — already wired in [apps/mobile/ios/Runner/Info.plist:75](apps/mobile/ios/Runner/Info.plist#L75) for the live Firebase project. If you regenerate the Firebase project, replace this with the new `GoogleService-Info.plist` `REVERSED_CLIENT_ID`.
4. **Apple Sign-In Services IDs** — create `app.havenkeep.mobile.signin` and `app.havenkeep.mobile.signin.staging` in Apple Developer portal under Identifiers → Services IDs. Configure each with the marketing domain as the Web Authentication redirect URL.
5. **App Store Connect** — create app record with bundle ID `app.havenkeep.mobile`. Privacy URL: `https://havenkeep.com/legal/privacy`. Support URL: `https://havenkeep.com/support`. Marketing URL (optional): `https://havenkeep.com`. Account Deletion: in-app via Settings → Delete Account. Privacy Nutrition Label: mirror the categories declared in `PrivacyInfo.xcprivacy`.
6. **Play Console** — create app with package name `app.havenkeep.mobile`. Privacy Policy: `https://havenkeep.com/legal/privacy`. Data Safety form: mirror `PrivacyInfo.xcprivacy` categories. Account deletion: in-app + `https://havenkeep.com/legal/delete-account`. Target API level 35 is auto-met by Flutter 3.41+.

### B. Production go-live: Stripe Connect + public URLs (off-platform configuration)

Partner self-service payouts are fully built and tested locally. To take it live, two things have to happen — both off-platform configuration with no code changes.

#### B.1 Stripe Connect — provide the keys

The Express API expects three env-equivalent values, all read from Docker Secrets in production (`docker-compose.production.yml` already references them). Drop real values into the secrets files on the prod host:

| File | Value | Where to find it |
|---|---|---|
| `./secrets/stripe_secret_key.txt` | `sk_live_…` | Stripe Dashboard → Developers → API keys → Live mode → "Secret key" |
| `./secrets/stripe_webhook_secret.txt` | `whsec_…` | Stripe Dashboard → Developers → Webhooks → click your endpoint → "Signing secret" |
| `STRIPE_PRICE_ID_PREMIUM` (env, in `.env` not secrets) | `price_…` | Stripe Dashboard → Products → Premium product → "Price ID" |

The webhook endpoint URL to configure in Stripe is `https://api.havenkeep.com/api/v1/webhooks/stripe` and must subscribe to: `payment_intent.succeeded`, `payment_intent.payment_failed`, `charge.refunded`, `charge.dispute.created`, `charge.dispute.lost`, `customer.deleted`, `customer.updated`, `radar.early_fraud_warning.created`, `payout.failed`, `account.updated`. (The handlers are already implemented in `apps/api/src/routes/webhooks.ts`.)

**Stripe Connect configuration** (one-time, on the platform Stripe account):
1. Stripe Dashboard → Connect → Settings → enable **Express** accounts.
2. Branding → upload logo + color, set support email to `support@havenkeep.com`.
3. Tax reporting → enable **Stripe-issued 1099-NEC** for Express accounts (this is what makes the partner-dashboard's "Open tax documents" button surface forms automatically). Stripe charges a small per-form fee; you only pay for partners who hit the $600 threshold.
4. Settings → enable both **OAuth** and **Direct** account creation modes (the API uses Direct via `accounts.create`).

Validation: the API's config validator refuses to boot in production unless `STRIPE_SECRET_KEY` looks like `sk_live_…` and `STRIPE_WEBHOOK_SECRET` starts with `whsec_`. Sandbox keys (`sk_test_…`) are blocked unless `STRIPE_ALLOW_SANDBOX=true` is also set — flip that to `false` (or remove it) for the production env.

#### B.2 Public URLs — wire DNS + Caddy

The three apps each need their own hostname. DNS A records all point at the same prod-host IP; Caddy in front routes by Host header.

| App | Production | Staging | Container port |
|---|---|---|---|
| Marketing site | `havenkeep.com` (+ `www.havenkeep.com` redirect) | `staging.havenkeep.app` | `80` (nginx) |
| API | `api.havenkeep.com` | `api.staging.havenkeep.app` | `3000` |
| Partner dashboard | `partners.havenkeep.com` | `partners.staging.havenkeep.app` | `3001` |

The staging triple lives on the shared dev droplet (`104.248.51.126`) behind Loni's Caddy on the 20** port range; `docker-compose.staging.yml` + `scripts/deploy-staging.sh` use these hostnames as defaults. Production lives on its own host with its own Caddy. Staging Stripe webhooks point at `https://api.staging.havenkeep.app/api/v1/webhooks/stripe`; production at the `.com` equivalent.

**DNS records to create** (at your registrar):
```
havenkeep.com.                       A     <prod-ip>
www.havenkeep.com.                   A     <prod-ip>
api.havenkeep.com.                   A     <prod-ip>
partners.havenkeep.com.              A     <prod-ip>
staging.havenkeep.app.               A     <staging-ip>
api.staging.havenkeep.app.           A     <staging-ip>
partners.staging.havenkeep.app.      A     <staging-ip>
```

**Caddyfile** (place at `/etc/caddy/Caddyfile` on the prod host; Caddy auto-issues Let's Encrypt certs). This also covers W078 / W111 — the production CSP enforcement headers must be set by Caddy in front of the static Astro site:
```
havenkeep.com, www.havenkeep.com {
    @www host www.havenkeep.com
    redir @www https://havenkeep.com{uri}
    reverse_proxy localhost:80
    header {
        Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
        X-Frame-Options "DENY"
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
        Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self'; connect-src 'self' https://api.havenkeep.com; frame-ancestors 'none'"
    }
    # Universal Links / App Links manifests must serve as application/json.
    @aasa path /.well-known/apple-app-site-association /.well-known/assetlinks.json
    header @aasa Content-Type application/json
}

api.havenkeep.com {
    reverse_proxy localhost:3000
    header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
}

partners.havenkeep.com {
    reverse_proxy localhost:3001
    header {
        Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
        X-Frame-Options "DENY"
        X-Content-Type-Options "nosniff"
    }
}
```

**Production env vars to set** in `.env` on the prod host (alongside the secrets files above):
```
FRONTEND_URL=https://havenkeep.com
DASHBOARD_URL=https://partners.havenkeep.com
API_URL=https://api.havenkeep.com
PUBLIC_PARTNER_DASHBOARD_URL=https://partners.havenkeep.com
CORS_ORIGINS=https://havenkeep.com,https://partners.havenkeep.com
```

The `PUBLIC_PARTNER_DASHBOARD_URL` value is what the marketing `/partners` page's "Apply to become a partner" CTA points at; it's compiled into the Astro build, so re-build marketing after setting it.

After Caddy reloads, the partner-flow chain is live: marketing `/partners` → "Apply" → `partners.havenkeep.com/signup` → onboarding → admin approve → Stripe Connect onboarding → "Request payout" works end to end.
