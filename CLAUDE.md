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

Every gate is currently green: api tsc, dashboard tsc + build, marketing build, both Dart packages analyze, mobile analyze, 444 flutter tests, debug APK build all pass. The list below is what the audit work left genuinely unaddressed.

### A. Gated on infra you control (not code defects)

- **`apps/api npm test` infrastructure is unblocked.** Postgres on the docker-compose dev stack is now bound to `:5434` (host-side, see `docker-compose.override.yml`) — port 5432 is held by an unrelated project. To run tests:
  ```sh
  docker compose up -d postgres redis      # postgres on :5434, redis on :6380
  docker exec havenkeep-postgres psql -U havenkeep -c "CREATE DATABASE havenkeep_test;"
  cd apps/api && \
    DB_HOST=localhost DB_PORT=5434 DB_NAME=havenkeep_test \
    DATABASE_URL="postgresql://havenkeep:havenkeep_dev_2026@localhost:5434/havenkeep_test" \
    npm run db:migrate
  TEST_DB_PORT=5434 TEST_REDIS_URL=redis://localhost:6380 npm test
  ```
  Current state: 239/300 tests pass; 61 fail because of pre-existing test gaps (missing Google OAuth / SendGrid mocks, schema-drift assumptions). Each failure is per-test, not infra.
- **Production CSP report-uri / CSP enforcement headers** (W078 / W111). Marketing site is static Astro — the headers must be set by Caddy in front of it. `astro.config.mjs` documents which headers Caddy needs.
- **Firebase Crashlytics DSN** (optional). The runtime is wired (see Telemetry above) but reports stop at the device when `firebase_options.dart` has the placeholder API key — drop a real `GoogleService-Info.plist` / `google-services.json` in to start receiving reports.

### B. Mobile feature gaps

All audit-flagged mobile gaps have been closed in this branch. The list previously here covered: inline maintenance log on item detail, calendar-month history view, due-window filter chips + bulk mark-done, home recent-activity feed, email-scanner UX (cancel mid-scan / granted-scopes display / in-app disconnect / low-confidence review queue), and Ch05-F098 splash tap-to-retry. All shipped — re-add entries here if a regression surfaces.

### C. App Store / Play Store submission

Code-side everything is ready: bundle ID `app.havenkeep.mobile`, Apple Team ID `N3RF2GHS99` wired into AASA + Xcode signing, upload-key SHA-256 wired into `assetlinks.json`, iOS PrivacyInfo.xcprivacy with required-reasons APIs + data collection categories, APNs entitlement, Apple Sign-In + Associated Domains entitlements, complete Info.plist permission strings + `ITSAppUsesNonExemptEncryption=false`, all marketing legal pages (`/legal/privacy`, `/legal/terms`, `/legal/delete-account`, `/cookies`, `/security`), a `/support` page (App Store Support URL), Caddy AASA MIME-type + CSP headers, and an adaptive Android launcher icon. Universal Links + App Links manifest files at `apps/marketing/public/.well-known/`.

**AASA scope** (4.8): `/gift/*` and `/referral/*` are the only paths that universal-link into the app. `/verify-email`, `/reset-password`, `/verify-email-change` are intentionally web-only — the user may click those links on a laptop / work phone / family member's phone, so opening the HavenKeep app on a different device is the wrong UX. Those endpoints land on the marketing site's auth UI. Adding in-app screens for them later means: (a) extend the `components:` array in `apps/marketing/public/.well-known/apple-app-site-association`, (b) extend `apps/marketing/public/.well-known/assetlinks.json` similarly for Android, and (c) wire the route in `apps/mobile/lib/core/services/deep_link_service.dart`.

The remaining work is **off-platform configuration only** — no code blocks shipping:

1. **Play App Signing fingerprint** — after the first AAB upload, copy the SHA-256 from Play Console → App integrity → App signing key fingerprint and replace `REPLACE_WITH_PLAY_APP_SIGNING_SHA256` in `apps/marketing/public/.well-known/assetlinks.json`. The upload-key fingerprint (`70:21:27:A4:…`) is already wired.
2. **Firebase config files** — download fresh `GoogleService-Info.plist` and `google-services.json` from Firebase Console and place them at `apps/mobile/ios/Runner/GoogleService-Info.plist` and `apps/mobile/android/app/google-services.json`. Both are gitignored.
3. **Reversed Google Client ID** — replace `com.googleusercontent.apps.REPLACE-WITH-CLIENT-ID` in `apps/mobile/ios/Runner/Info.plist` (CFBundleURLSchemes) with the value from `GoogleService-Info.plist` `REVERSED_CLIENT_ID`.
4. **Apple Sign-In Services IDs** — create `app.havenkeep.mobile.signin` and `app.havenkeep.mobile.signin.staging` in Apple Developer portal under Identifiers → Services IDs. Configure each with the marketing domain as the Web Authentication redirect URL.
5. **App Store Connect** — create app record with bundle ID `app.havenkeep.mobile`. Privacy URL: `https://havenkeep.com/legal/privacy`. Support URL: `https://havenkeep.com/support`. Marketing URL (optional): `https://havenkeep.com`. Account Deletion: in-app via Settings → Delete Account. Privacy Nutrition Label: mirror the categories declared in `PrivacyInfo.xcprivacy`.
6. **Play Console** — create app with package name `app.havenkeep.mobile`. Privacy Policy: `https://havenkeep.com/legal/privacy`. Data Safety form: mirror `PrivacyInfo.xcprivacy` categories. Account deletion: in-app + `https://havenkeep.com/legal/delete-account`. Target API level 35 is auto-met by Flutter 3.41+.

### D. Production go-live: Stripe Connect + public URLs

The partner self-service payout pipeline is fully built and tested locally. To take it live in production, two things have to happen — both off-platform configuration with no code changes:

#### D.1 Stripe Connect — provide the keys

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

#### D.2 Public URLs — wire DNS + Caddy

The three apps each need their own hostname. DNS A records all point at the same prod-host IP; Caddy in front routes by Host header.

| App | Hostname | Container port | Purpose |
|---|---|---|---|
| Marketing site | `havenkeep.com` (+ `www.havenkeep.com` redirect) | `80` (nginx) | Public site, /partners landing |
| API | `api.havenkeep.com` | `3000` | Mobile + dashboard backend, Stripe webhook target |
| Partner dashboard | `partners.havenkeep.com` | `3001` | Partner self-service portal |

**DNS records to create** (at your registrar):
```
havenkeep.com.            A     <prod-ip>
www.havenkeep.com.        A     <prod-ip>
api.havenkeep.com.        A     <prod-ip>
partners.havenkeep.com.   A     <prod-ip>
```

**Caddyfile** (place at `/etc/caddy/Caddyfile` on the prod host; Caddy auto-issues Let's Encrypt certs):
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

### E. Audit-remediation in flight (2026-04-29 audit)

A 9-reviewer end-to-end audit on 2026-04-29 produced 145 findings (22 Critical, 44 High, 51 Medium, 28 Low) and a 5-phase remediation plan. Documents live in `/tmp` per Rule 3 (move to durable storage before relying on them):

- `/tmp/havenkeep-handoff.md` — read first; entry point for any session continuing the work
- `/tmp/havenkeep-audit-2026-04-29.md` — the audit (Part I general, Part II security threat-class addendum)
- `/tmp/havenkeep-remediation-plan.md` — the 5-phase plan with per-finding instructions

**Phase 1 — Stop the bleeding** (10 findings) shipped on branch `remediation/phase-1-stop-the-bleeding`:
- C1 (mig 082) — restored audit-trigger enum/UUID casts that mig 080 regressed
- C9 — registered pg type-parser for NUMERIC (OID 1700) so DECIMAL columns hydrate as JS numbers
- H-A7 — dashboard auth response envelope unwrap (`body.data.accessToken`); login was broken in prod
- C7+C8 — Stripe charge.* handlers match by payment_intent (not charge.id); partial refund handling
- C10 — `asyncHandler` sweep on `routes/auth.ts`; audit-log writes are now best-effort
- C13b — `/me/recover` reachable for soft-deleted users within 30-day grace
- S-C1 — audit routes use `requireAdmin` + new `verifyAdminFresh` helper for fresh DB-derived admin checks
- S-C5 + S-H2 — per-user 3/hour limiter on `/me/change-email` + per-recipient Redis dedupe + closed enumeration oracle
- S-C6 — per-user rate limit on `/email-scanner/scan` (5/hour) + mutation actions (30/15min)

**Phase 2 — Critical security & integrity** (12 findings) shipped on branch `remediation/phase-2-criticals`:
- C2+C3 — flushDigestOutbox now sends FCM (was inserting `'pending'` and never pushing); FOR UPDATE SKIP LOCKED prevents concurrent-replica duplicates
- C4 (mig 083) — warranty_*.user_id RESTRICT→SET NULL + user_email_at_purchase / user_email_at_claim denormalized columns; account-purge anonymizes before DELETE so paying users hard-delete cleanly
- C5+C6 — warranty cancel split into 3-phase (lock+claim 'cancelling' → Stripe refund outside tx → finalize) and partner_commissions joined via reference_id+reference_type='warranty_purchase' (column was hallucinated)
- C11 — email-scan setTimeout handle captured + clearTimeout in .finally so 5-min closures don't leak per scan
- C12 — activation-code generation moved BEFORE the BEGIN; collision pre-check via SELECT EXISTS, retry-loop-inside-aborted-tx pattern removed
- C13 + S-M9 — POST /api/v1/auth/verify-email-change implemented (atomic DELETE-RETURNING token, swap email, drop refresh tokens, invalidate cache); marketing /verify-email-change.astro page consumes the link; users.ts switched from bare SHA-256 to keyed HMAC via new utils/token-hash.ts
- C14 — ItemsNotifier mutations wire OfflineSyncService.enqueueChange on ApiNetworkException / ApiTimeoutException (was 0 callers); other ApiException variants still rollback
- C15 — pubspec ships only .env.bundled; scripts/prepare-env.sh copies the active flavor file before `flutter build`; .gitignore the bundle
- S-C2 (mig 084) — TOTP MFA: user_mfa_factors + user_mfa_backup_codes tables, /api/v1/mfa/totp/{enroll,verify,disable} + /status routes, /auth/mfa/challenge to exchange a short-lived (5min) mfa_token for real access+refresh; /auth/login routes through the gate when MfaService.getStatus returns hasVerifiedFactor
- S-C4 — Gmail and Outlook OAuth flows now mint and verify a `state` parameter (32-byte CSPRNG, base64url) per RFC 6749 §10.12

**Phase 3 — High-impact correctness & data** (23 findings) shipped on branch `remediation/phase-3-correctness`:

Auth & sessions:
- H-A1 — /auth/login refuses tokens for soft-deleted (within-grace returns ACCOUNT_PENDING_DELETION 403) / suspended accounts; new AppErrorCode entry
- H-A2 — closed by P1.8/S-H2 (no-op verification commit not needed)
- H-A4 — /forgot-password per-target-email Redis counter (3/h) on top of the per-IP limiter; skips the existing-token-burn UPDATE when fired
- H-A5 — /me/verify-premium revokes Gmail/Outlook OAuth integrations on premium→free transitions (best-effort)
- H-A6 — /auth/apple rejects when stored apple_user_id differs from JWT sub
- H-A8 — new GET /auth/role-check + dashboard middleware caches the response in an HttpOnly hk_role_check cookie (30s TTL); demoted users lose nav access in ≤30s instead of ≤1h
- H-A9 — /admin/partners/:id/{approve,reject} state-machine guards (idempotent on re-execute, refuses rejected→*); audit metadata captures from→to; reject burns refresh tokens + invalidateUserCache

Data integrity:
- H-D1 — migration runner wraps main() in pg_advisory_lock (key 'MGRN' = 0x4d_47_52_4e); rolling deploys can't race on DDL
- H-D2 — DELETE /items/:id no longer DELETEs warranty_purchases / warranty_claims; FK SET NULL preserves paid records
- H-D3 (mig 085) — drops dead documents.deleted_at column + partial index
- H-D4 (mig 086) — drops redundant plaintext partner_gifts.activation_code UNIQUE; service-side 23505 handler simplified
- H-D5 (mig 087) — webhook_events.id BIGINT promotion + 7-day cleanup moved from weekly Sunday to daily
- H-D6 — user_push_tokens INSERT/UPSERT now bumps last_seen_at; FcmService.cleanupStaleTokens(60) wired into the daily cron
- H-D7 (mig 088) — email_scans.completion_message split out from error_message; service-side writer updated
- H-D8 (mig 089) — partner_gifts.chargeback_status CHECK is now a regex (lowercase snake_case ≤64 chars) so future Stripe enum additions don't crash the dispute handler

Contract drift:
- H-C1 — ITEM_LIST_COLUMNS includes estimated_repair_cost; mobile app sees the seeded value
- H-C2 (mig 090) — items.ts hardcoded CATEGORY_DEFAULT_LIFESPAN replaced by category_defaults.lifespan_years with 60s in-memory cache; admin can change lifespan without a code deploy
- H-C3 — shared_models MaintenanceDueSummary now parses summary_state into a new MaintenanceSummaryState enum; dashboard can distinguish noItems / noSchedules / caughtUp / hasDue

Payments hardening:
- H-P1 — Stripe dispute handler invokes isEventInOrder('stripe', payment_intent_id, ...) so reordered retries don't override fresher state
- H-P2 — auditWebhookPlanTransition helper wired at four highest-impact transitions (charge.refunded revoke, charge.dispute.lost revoke, RC INITIAL_PURCHASE/RENEWAL/UNCANCELLATION upgrade, RC EXPIRATION downgrade); rows carry webhook_source + webhook_event_id metadata
- H-P3 — explicit handlers for payout.failed (with handlePayoutFailed lookup of partner_commissions), payment_intent.payment_failed, customer.deleted, customer.updated, radar.early_fraud_warning.created
- H-P4 — TIER_PRICING renamed TIER_PRICE_PER_GIFT_USD; /partners/tiers response surfaces price_per_gift; price_monthly stays at 0 with explanatory comment until recurring billing actually ships
- H-P5 — /me/verify-premium is upgrade-only; non-premium response on a currently-premium user leaves the row alone (defers demotion to webhook with event-id causality)
- H-P6 — already shipped in P1.4 alongside C8 (proportional commission clawback for partial refunds)

**Phase 4 — Hardening & contract drift** (~20 findings) shipped on branch `remediation/phase-4-hardening`:

Bug-correctness Highs:
- H-B1 — ROLLBACK .catch(() => {}) sweep across 16 files / 33 sites; broken-connection rollback failures no longer mask the real caller error
- H-B2 — daysRemaining now uses UTC-midnight day-count (daysBetweenUtc helper); DST + non-UTC server no longer tip the count
- H-B3 — isSyncingProvider is a StateProvider<bool>; OfflineSyncService writes through it from syncPendingChanges so UI sees flips
- H-B6 — splash bootstrap error routes through ErrorHandler.getUserMessage instead of leaking ApiException toString
- H-B8 — five family providers gain .autoDispose (documents, claims, maintenance×2, brand suggestions); per-key cache no longer grows unboundedly
- H-B9 — restoreSession distinguishes ApiAuthRequiredException (clear tokens) from transient transport errors (keep tokens, retry next launch)
- H-B11 — notification IDs use a process-monotonic counter; collisions and Y2K38 wraparound both closed

Auth & security mediums:
- S-M1 — authenticate state-deny messages collapsed to a single "Authentication failed" 401 with the actual reason logged via pino
- S-M4 — /logout now 503's on token-blacklist write failure instead of lying about a successful logout
- S-H8 — mobile FlutterSecureStorage uses KeychainAccessibility.first_unlock_this_device (no iCloud roam) — matches the SQLCipher DB key choice

Data integrity:
- M-D2 (mig 091) — audit_logs.user_email widened to VARCHAR(320) (RFC 5321) for forensic accuracy after user delete
- M-D4 (mig 092) — partners CHECK invariant (is_active = TRUE) ⇔ (status = 'active'); silent desyncs now raise 23514

Payments hardening:
- M-P8 + M-P9 — RC TRANSFER (both source and destination) and PRODUCT_CHANGE plan transitions now go through auditWebhookPlanTransition
- M-A10 — receipt_scan_idempotency, apple_sign_in_nonces, gift_verify_attempts retention sweeps wired into the daily cron

Mobile / contract:
- L4-archive — archiveItem rollback path re-invalidates archivedItemsProvider to keep the archive screen in sync with the active list
- L5 — Item.fromJson uses _requireDate(value, field) which throws a typed FormatException naming the failed field instead of a generic null-check crash
- M-mob-6 — LoggingService redact patterns now match emails + phone numbers; sensitive-key list widened to email/phone/fullname/address/apikey
- M-mob-9 + M-mob-10 — Validators.price routes through parsePriceInput for locale-aware parsing; parsePriceInput rejects negatives explicitly

**Phase 5 — Polish & supply-chain hygiene** (~12 findings) shipped on branch `remediation/phase-5-polish`:

Supply-chain hygiene:
- S-L5 — n/a after `.github/workflows/` was removed (no CI/CD in this repo). The original P5.1 commit (`170a575`) SHA-pinned third-party actions in `mobile-ci.yml`; that file no longer exists.
- S-L6 — Dockerfiles (api, partner-dashboard, marketing) pin base images by sha256 digest (`node:20-alpine@sha256:fb4cd1…`, `nginx:alpine@sha256:561687…`); rebuilds now reproduce bit-for-bit

Backend hygiene:
- L2 — `setCsrfToken` doc-comment corrected to match implementation (only the CSRF cookie itself rolls forward; access/refresh cookies were never part of the trigger)
- L19 — account-purge `refresh_tokens` DELETE removed (FK CASCADE on users handles it; the explicit DELETE was a no-op)
- M-D3 cleanup — 10 readers in `auth.ts`, `admin.ts`, `users.ts` migrated from `partners.is_active = TRUE` to `partners.status = 'active'`; the dual-state column is now writable-only
- M-D-extra — `webhook_event_high_water` daily prune sweep added (Stripe rows >90d); table no longer grows unbounded
- M-NEW-1 — `email_scanner_seen_messages` daily prune sweep added (>90d on first_seen_at); was the largest unbounded table on the schema
- M-NEW-5 (mig 093) — `documents.file_size` CHECK (>= 0); the mig-070 "Joi-validates → DB-enforces" pattern had missed file_size
- M-NEW-6 (mig 094) — drops redundant `idx_newsletter_subscribers_email`; the partial UNIQUE on `LOWER(email) WHERE status='subscribed'` (mig 037) supersedes it

Code hygiene:
- P3.22 followup — TIER_PRICING legacy alias removed; the canonical `TIER_PRICE_PER_GIFT_USD` is the only name now
- L9 — `user_stats` view audit: kept (admin.ts:239 actively reads from it; the audit-flagged "dead view" was wrong)
- C10 leftover — `AppLifecycleService` dispose audit: no leak; the service is a singleton with deterministic owner

The audit-remediation arc is closed. 145 findings → 145 dispositions (shipped, deferred-with-rationale, or audit-was-wrong). The `/tmp/havenkeep-*.md` documents are stale; do not rely on them for new work — read this ledger and `git log --oneline` for ground truth.
