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
- **`apps/marketing`** — Astro static site. Tailwind dark theme. Hosts `/legal/*` and `/delete-account` for store compliance. Sitemap + RSS shipped. CSP/X-Frame headers are set by Caddy in front of the static host (live on staging via the shared `infra/Caddyfile`).
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
Numbered migrations live in `apps/api/src/db/migrations/`: 028–039 (security/data-loss criticals), 040–045 (DB foundation), 050–051 (payments + uploads), 060–067 (services), 070 (drift constraints), 071 (partner status enum), 072–074 (digest outbox / welcome email open / category repair-cost defaults), 075–081 (audit-chain casts, request idempotency, MinIO object keys, audit-chain advisory lock, audit-logs description cap), 082 (re-applies audit-trigger casts + advisory lock together — fixes audit C1 where 080 regressed 075's enum/UUID casts), 083 (warranty_*.user_id RESTRICT→SET NULL + denormalized email columns for purge anonymization — audit C4), 084 (user_mfa_factors + user_mfa_backup_codes for TOTP enrollment — audit S-C2), 085 (drop dead documents.deleted_at column — H-D3), 086 (drop redundant plaintext partner_gifts.activation_code UNIQUE — H-D4), 087 (webhook_events.id → bigint — H-D5), 088 (email_scans.completion_message — H-D7), 089 (chargeback_status regex CHECK — H-D8), 090 (category_defaults.lifespan_years seeded from items.ts hardcoded map — H-C2), 091 (audit_logs.user_email → VARCHAR(320) — M-D2), 092 (partners is_active/status invariant CHECK — M-D4), 093 (documents.file_size non-negative CHECK — M-NEW-5), 094 (drop redundant idx_newsletter_subscribers_email — M-NEW-6), 095 (partial index on partner_commissions for the 30-day auto-approve sweep + columns for self-service payouts), 096 (audit_action enum: add `partner.payout_request` so the new payout endpoint can audit-log without 22P02), 097 (warranty_claim_state_history immutable trigger now allows FK CASCADE delete from the parent claim), 098 (warranty_purchase_status enum: add `cancelling` for the three-phase cancel flow's transient state), 099 (cleanup_old_audit_logs() rewritten as SECURITY DEFINER under audit_cleaner role — newer Postgres rejects mid-function `SET LOCAL ROLE` inside a SECURITY DEFINER body), 100 (grant SELECT on audit_logs to audit_cleaner — DELETE alone wasn't enough; PG needs SELECT to evaluate the WHERE clause). Runner auto-detects `ALTER TYPE ADD VALUE` and `CREATE INDEX CONCURRENTLY` and runs those files outside transactions; the runner also wraps `main()` in `pg_advisory_lock` (H-D1) so two replicas booting simultaneously can't race on the same DDL. `schema_version` table tracks bootstrap completion.

### Stripe SDK pin
`stripe@^21.0.1` with `apiVersion: '2026-03-25.dahlia'` (see [apps/api/src/utils/stripe-client.ts](apps/api/src/utils/stripe-client.ts)). NOT v22 — v22 ships a CJS-typing regression that breaks `Stripe.Charge` / `Stripe.PaymentIntent` / `Stripe.Event` resolution under our `tsconfig.module=commonjs`. v21 carries the same API version pin and runtime surface. Bump to v22+ once Stripe ships the CJS fix or we migrate the API to ESM.

### Staging deployment
Staging lives on a shared Digital Ocean droplet at **`206.189.26.12`** (Ubuntu 24.04, 8 GB / 2 vCPU). Eight apps share the box (havenkeep, loni, restorae, platform, bquick, legalci, fortify, hge-men) plus shared infra (Postgres, MinIO, Redis, Caddy, Dozzle). HavenKeep does NOT run its own Postgres/Redis/MinIO — it consumes the shared infra-postgres / infra-redis / infra-minio containers on the `staging-net` Docker network.

Deploy system lives at **`~/Projects/staging/`** (separate repo, not in this monorepo). The flow:
```sh
cd ~/Projects/staging
./ship.sh havenkeep            # builds 3 images on laptop, scps tarballs, deploys
./rollback.sh havenkeep        # roll back to previous image tag
```
What `ship.sh` does: builds `havenkeep-api`, `havenkeep-dashboard`, `havenkeep-marketing` for `linux/amd64`, saves as gzipped tarballs, scps to `/opt/staging/havenkeep/images/`, then SSHes and triggers `/opt/staging/havenkeep/deploy.sh <tag>`. The droplet-side `deploy.sh` runs migrations as a one-shot container (`profile: migrate`) before flipping `IMAGE_TAG=` in `.env` and `docker compose up -d --force-recreate`. Failed healthchecks roll back automatically.

| Surface | URL | Container | Bound to |
|---|---|---|---|
| Marketing | `https://staging.havenkeep.app` | `havenkeep-marketing` | `staging-net:4321` (Astro preview) |
| API | `https://api.staging.havenkeep.app` | `havenkeep-api` | `staging-net:3000` |
| Partner dashboard | `https://partner.staging.havenkeep.app` | `havenkeep-dashboard` | `staging-net:3001` |

(Subdomain note: staging uses `partner.` singular — that's what the live Caddyfile binds. Production may use `partners.` plural; decide before going live.)

**Where staging secrets live** (NOT in this repo — they live on the droplet):
- `/opt/staging/havenkeep/.env` — just `IMAGE_TAG=<tag>`, read by compose
- `/opt/staging/havenkeep/.env.api` — API runtime env: `APP_BASE_URL`, `FRONTEND_URL`, `DASHBOARD_URL`, `CORS_ORIGINS`, `STRIPE_*`, `JWT_SECRET`, etc.
- `/opt/staging/havenkeep/.env.dashboard` — Next.js runtime env
- `/opt/staging/infra/.env` — shared infra (postgres root password, per-app DB passwords, MinIO root + 6 per-app keypairs, Redis password)

Per-app Caddy routing lives in `/opt/staging/infra/Caddyfile`. The havenkeep block already has a raw-body matcher for `/api/v1/webhooks/stripe` and `/api/v1/webhooks/revenuecat` (Stripe signature verification needs the raw body unmolested by Caddy compression).

Logs: `https://logs.staging.kouakoudomagni.com` (Dozzle, basic auth — ask Domagni for credentials). Or `ssh root@206.189.26.12 'docker logs havenkeep-api -f'`.

---

## Part 3 — Outstanding work

Every gate is currently green: api tsc + 305/305 jest tests, dashboard tsc + build, marketing build, both Dart packages analyze, mobile analyze, 444 flutter tests, debug APK build all pass. The 2026-04-29 audit-remediation arc is closed (145 findings → 145 dispositions; see `git log --oneline` if you need the per-finding history).

**No outstanding code-level work.** All in-repo follow-ups (S-M7 public CSRF mint, Phase-5 activation-code wipe) shipped on `main`. The list below is staging-track only — production is months away and intentionally not documented here yet (when prod gets close, that runbook gets written based on what staging actually proved).

### A. Staging — Stripe test mode setup

The partner-payout pipeline runs end to end against staging at `https://api.staging.havenkeep.app/api/v1/webhooks/stripe`.

**Setup** (one-time):

1. **On the staging droplet** (`/opt/staging/havenkeep/.env.api`), populate:
   - `STRIPE_SECRET_KEY=sk_test_…` (Stripe Dashboard, **Test mode** toggle on)
   - `STRIPE_WEBHOOK_SECRET=whsec_…` (the signing secret printed when you save the webhook endpoint)
   - `STRIPE_PRICE_ID_PREMIUM=price_…` (create the Premium product under Test mode first)
   - `STRIPE_ALLOW_SANDBOX=true` (the config validator refuses `sk_test_…` without it)
2. **In the Stripe Dashboard (Test mode)**, register the webhook endpoint at `https://api.staging.havenkeep.app/api/v1/webhooks/stripe` subscribing to: `payment_intent.succeeded`, `payment_intent.payment_failed`, `charge.refunded`, `charge.dispute.created`, `charge.dispute.updated`, `charge.dispute.closed`, `customer.deleted`, `customer.updated`, `radar.early_fraud_warning.created`, `payout.failed`, `account.updated`. The handlers are in [apps/api/src/routes/webhooks.ts](apps/api/src/routes/webhooks.ts). (Dispute outcome — won/lost — is on `charge.dispute.closed.status`; there is no separate `.lost` event.)
3. **Enable Connect (Test mode)** under Connect → Settings: Express accounts on, OAuth + Direct on, Stripe-issued 1099-NEC on.

**Verification scripts** ship in [scripts/stripe/](scripts/stripe/):

- `./scripts/stripe/check-staging.sh` — under-10s connectivity smoke test. Verifies stripe CLI auth, public surface (Caddy + `/health`), API config (the four env values land in `.env.api`), and webhook signature path end to end.
- `./scripts/stripe/e2e-staging.sh` — full acceptance suite. Seven independent phases:
  - **Phase 1: plumbing** — fires every subscribed event via `stripe trigger`, verifies API logs each handler ran
  - **Phase 2: gift purchase** — creates a real PaymentIntent through `POST /partners/gifts`, verifies `partner_gifts.status='created'` + commission row
  - **Phase 3: refund** — `stripe refunds create` → `charge.refunded` handler → reversal commission row
  - **Phase 4: dispute** — `charge.dispute.created/.updated/.closed` triggers; `.lost` requires manual dashboard step
  - **Phase 5: connect onboarding** — opens hosted Express form, waits for `account.updated` → `stripe_account_status='enabled'`
  - **Phase 6: payout** — ages a commission past the 30-day clawback, runs `POST /partners/me/payouts`, verifies `transfer.id` written and row marked `paid`
  - **Phase 7: failures** — `payment_intent.payment_failed`, `payout.failed`, `customer.deleted`, `radar.early_fraud_warning.created`
  - Run subset via `--phases=2,3,4`. Wipe fixtures via `--cleanup`. Test state cached at `~/.havenkeep/stripe-e2e-staging/` so re-runs are idempotent.

The bar for "staging Stripe is green" is `./scripts/stripe/e2e-staging.sh` exiting 0 on every phase.

### B. Mobile build prep (when you're ready to ship a TestFlight / Play Internal build)

Code-side the mobile is build-ready: bundle ID `app.havenkeep.mobile`, Apple Team ID `N3RF2GHS99` wired into AASA + Xcode signing, upload-key SHA-256 wired into `assetlinks.json`, iOS PrivacyInfo.xcprivacy + APNs + Apple Sign-In + Associated Domains entitlements, complete Info.plist permission strings, `ITSAppUsesNonExemptEncryption=false`, adaptive Android launcher icon, all marketing legal pages live on staging.

**AASA scope** (4.8): `/gift/*` and `/referral/*` are the only paths that universal-link into the app. `/verify-email`, `/reset-password`, `/verify-email-change` are intentionally web-only — the user may click those links on a laptop / work phone / family member's phone, so opening the app on a different device is the wrong UX. Those endpoints land on the marketing site's auth UI.

Off-platform setup needed before the first build can be uploaded:
1. **Firebase Crashlytics keys** — `firebase_options.dart` reads `FIREBASE_ANDROID_API_KEY` / `FIREBASE_IOS_API_KEY` from `.env.<flavor>`. Drop real values into `apps/mobile/.env.staging` (and run `scripts/prepare-env.sh staging` before `flutter build`). Place fresh `GoogleService-Info.plist` and `google-services.json` from Firebase Console at `apps/mobile/ios/Runner/` and `apps/mobile/android/app/` (both gitignored).
2. **Apple Sign-In Services IDs** — create `app.havenkeep.mobile.signin.staging` in Apple Developer portal → Identifiers → Services IDs. Configure with `staging.havenkeep.app` as the Web Authentication redirect URL.
3. **TestFlight / Play Internal record** — create staging app records under both consoles using bundle ID `app.havenkeep.mobile`. Privacy URL: `https://staging.havenkeep.app/legal/privacy`. The full Privacy Nutrition Label / Data Safety answers are pre-filled in [apps/mobile/store/PLAY_CONSOLE_ANSWERS.md](apps/mobile/store/PLAY_CONSOLE_ANSWERS.md) and [apps/mobile/store/STORE_LISTING.md](apps/mobile/store/STORE_LISTING.md).
4. **Play App Signing fingerprint** (only after first AAB upload) — copy SHA-256 from Play Console → App integrity and replace `REPLACE_WITH_PLAY_APP_SIGNING_SHA256` in [apps/marketing/public/.well-known/assetlinks.json](apps/marketing/public/.well-known/assetlinks.json). The upload-key fingerprint (`70:21:27:A4:…`) is already wired.

Production mobile submission (App Store / Play live) is deferred — those steps will be written when the staging app is stable enough to think about ramp.
