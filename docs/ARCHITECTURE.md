# HavenKeep Architecture

This document describes the technical architecture of HavenKeep — what runs, where, and why. It is a working reference, not a marketing pitch. When the code disagrees with this doc, the code wins; please open a PR to fix the doc.

For *what we are building and why*, see [PRODUCT.md](./PRODUCT.md). For *how to run the system locally*, see [the root README](../README.md).

---

## 1. System overview

HavenKeep is a home asset and warranty tracker. Four user-facing surfaces share one Express API and one Postgres database:

```
                    ┌──────────────────────────────────────┐
                    │            apps/marketing            │
                    │   Astro static site (havenkeep.com)  │
                    │   Legal pages, blog, contact form    │
                    └─────────────────┬────────────────────┘
                                      │ POST /contact
                                      ▼
┌──────────────────┐  HTTPS  ┌──────────────────────┐  pg  ┌──────────────────┐
│  apps/mobile     │────────▶│      apps/api        │─────▶│   PostgreSQL     │
│  Flutter         │         │  Express + raw `pg`  │      │   (raw SQL,      │
│  iOS + Android   │         │  JWT + refresh       │      │    NOT Prisma)   │
└──────────────────┘         │  Stripe / RC / OAuth │      └──────────────────┘
                             │  Cron jobs           │             │
┌──────────────────┐         │                      │             │ MinIO
│ apps/partner-    │────────▶│                      │─────────────┘ Redis
│  dashboard       │         └──────────┬───────────┘
│  Next.js (proxy) │                    │
└──────────────────┘                    ▼
                              External services:
                              Stripe, RevenueCat,
                              SendGrid, Firebase,
                              Google/Apple/Microsoft
                              OAuth, OpenAI Vision
```

Two Dart packages keep the mobile + dashboard halves coherent:

- `packages/shared_models` — every data class the API hands back, with one enum module (`enums.dart`) and a shared "unknown enum" funnel so server-side enum drift surfaces in mobile logs and Crashlytics breadcrumbs.
- `packages/api_client` — a Dio-free HTTP wrapper around the Express API. Sealed `ApiException` hierarchy with nine typed subclasses, automatic refresh-on-401 with a single-flight mutex, `pathSegments` API to prevent URL injection, `Idempotency-Key` on every mutating method.
- `packages/shared_ui` — the design system (HavenColors / HavenSpacing / HavenRadius / HavenText / HavenMotion) + a small set of shared widgets (CategoryIcon, BrandAutocompleteField, WarrantyDurationPicker, ItemLimitBanner, ConfirmationDialog, SectionHeader, RoomPicker, HavenSkeleton, HavenAccordion, HavenSnackbar, WarrantyStatusBadge, DocumentTypeIcon).

The API is the single source of truth. Mobile + dashboard never talk to the database, MinIO, or Stripe directly — every call goes through Express, which enforces auth, audit, and idempotency.

---

## 2. Repository layout

```
havenkeep/
├── apps/
│   ├── api/                    # Express + Postgres backend
│   ├── mobile/                 # Flutter iOS/Android app
│   ├── partner-dashboard/      # Next.js admin/partner portal
│   └── marketing/              # Astro static site
├── packages/
│   ├── api_client/             # Dart HTTP wrapper
│   ├── shared_models/          # Dart data models + enums
│   └── shared_ui/              # Dart design system
├── docs/
│   ├── ARCHITECTURE.md         # this file
│   └── PRODUCT.md              # product spec
├── CLAUDE.md                   # session rules + outstanding work
└── README.md                   # how to get running
```

Workspace tooling is hybrid: the JS/TS half uses pnpm/npm workspaces, the Dart half uses pubspec path-dependencies. The mobile package never imports anything from the JS half and vice versa — the contract between them is the API JSON envelope, period.

---

## 3. Backend — `apps/api`

### 3.1 Stack

- **Express 4** with helmet, cors, pino, express-rate-limit, multer.
- **PostgreSQL** via the raw `pg` library — **no Prisma, no Drizzle, no query builder.** Every query is plain SQL. Connection is a pool initialised in `apps/api/src/db/index.ts`.
- **JWT auth** with HS256 access tokens (1h TTL) + opaque refresh tokens (7d TTL, stored hashed in `refresh_tokens`). Token rotation on every refresh.
- **MFA via TOTP** (mig 084: `user_mfa_factors` + `user_mfa_backup_codes`).
- **Redis** for rate-limit buckets, the user cache (10s TTL), and webhook idempotency cursors.
- **MinIO** (S3-compatible) for receipt photos, warranty cards, item images. Presigned URLs only; no public buckets.
- **Stripe SDK pinned at `^21.0.1`** with `apiVersion: '2026-03-25.dahlia'`. Pinned because v22 has a CJS-typing regression that breaks `Stripe.Charge` / `Stripe.PaymentIntent` resolution under our `tsconfig.module=commonjs`. See [`apps/api/src/utils/stripe-client.ts`](../apps/api/src/utils/stripe-client.ts).
- **Logging** is pino → Loki. `redactPaths` covers bearer tokens, refresh tokens, OAuth access tokens, base64 image bodies, password hashes, Stripe webhook secrets.
- **No Sentry** — Loki + Crashlytics (mobile) cover what Sentry would.

### 3.2 App bootstrap

[`apps/api/src/app.ts`](../apps/api/src/app.ts) wires the middleware chain in this order: helmet (CSP locked to `api.stripe.com` + `api.revenuecat.com`), CORS (function-form so unknown origins are explicitly rejected, not silently allowed), pino-http, raw-body-mounted Stripe + RevenueCat webhook routes (raw body must reach Stripe's signature verifier untouched), JSON parser, then every feature router under `/api/v1/*`.

[`apps/api/src/index.ts`](../apps/api/src/index.ts) does the actual `listen()` and starts the cron scheduler. Locks are declared in one place — [`apps/api/src/db/advisory-locks.ts`](../apps/api/src/db/advisory-locks.ts) — so two replicas can never double-fire and a reviewer can spot the next collision before it ships:

- `93422874` `NOTIFICATION_EXPIRATION` — expiration-notifications, daily 09:00 UTC
- `93422875` `MAINTENANCE_DUE` — maintenance-due, daily
- `93422876` `WARRANTY_OFFERS` — warranty-offers, daily
- `93422877` `PARTNER_GIFT_EXPIRY` — `expireUnactivatedPartnerGifts`, daily
- `93422878` `PARTNER_COMMISSION_AUTO_APPROVE` — `autoApproveAgedPendingCommissions`, daily (`COMMISSION_AUTO_APPROVE_HOLD_DAYS=30`)
- `93422879` `NOTIFICATION_DIGEST_FLUSH` — digest outbox flush, every 60s (H7: was sharing `93422878` with the daily auto-approve before the registry was introduced)

Also fire-and-forget every day inside the daily `Promise.allSettled` batch (no advisory lock — these are idempotent on the column they stamp):

- `AuditService.verifyHashChain()` — verifies the audit hash chain and pages if it can't.
- `alertOnDeadLetterWebhooks()` — pages once per dead-letter row via the `webhook_events.alerted_at` stamp (mig 105).
- `sendDay25GraceReminders()` — H78 day-25 deletion-grace nudge, stamps `users.last_grace_reminder_sent_at` on success (mig 111).

The scheduler is drift-resilient: it computes "minutes until next run" from `getUTCHours/getUTCMinutes` rather than `setInterval`, so a server clock that ticks off-rhythm doesn't accumulate skew.

### 3.3 Routes

24 routers under `apps/api/src/routes/`:

| Router | Surface |
|---|---|
| `auth` | register, login, refresh, logout, forgot/reset password, verify-email, change-email, MFA enroll/verify, OAuth (Google + Apple), `/role-check` (used by the dashboard's edge middleware) |
| `users` | `/me`, profile updates, account soft-delete + recover, gifts, account purge ops |
| `homes`, `items`, `documents` | The household graph. `items` is the busiest router. |
| `notifications` | List, mark read, dismiss, push tokens |
| `maintenance` | Schedules, history, due summary, customizations |
| `warranty-claims`, `warranty-purchases` | Claims and extended-warranty purchases |
| `partners` | Partner profile, gifts, commissions, payouts, Stripe Connect onboarding, analytics |
| `partner-onboarding`, `admin` | Approval workflow + admin tools |
| `email-scanner` | OAuth code-grant connect, scan trigger, review-queue mgmt |
| `webhooks` | Stripe + RevenueCat — claim + dead-letter pattern |
| `barcode-lookup`, `receipt-scan` | OCR + product DB integrations |
| `health`, `audit`, `contact`, `referrals`, `tips`, `uploads` | Misc |

Every mutation passes through `requestIdempotency` (mig 078: `request_idempotency` table keyed `(user_id, route_key, idempotency_key)`) so the mobile app's offline queue can replay safely.

### 3.4 Services

Services under `apps/api/src/services/`. Heavy hitters first; the rest are listed at the end.

- `auth.service` — token mint/verify, refresh family, MFA verify, ACCOUNT_PENDING_DELETION code path during the 30-day cooling-off window, S-M1 generic 401 to defend against state-deny enumeration. JWTs are pinned on iss + aud + jti (H13); the password-change / suspend paths bump `users.tokens_invalidated_at` (mig 107) so every previously-issued JWT becomes invalid in one shot.
- `mfa.service` — TOTP via otplib, AES-GCM-wrapped backup codes (mig 084 + 108), MFA challenge JWT minted on the first step of two-factor login.
- `partners.service` — gift creation as a 3-phase flow (reserve `pending_payment` row → create Stripe PaymentIntent outside the transaction → promote to `created` + commission insert; phase-3 failure triggers a refund-compensation step). Activation is rate-limited via Redis (5 attempts/hour, 15-min lockout). Handles partner-onboarding state machine (`pending` → `active` | `rejected`) and Stripe Connect `enabled` status before allowing payouts. Commission identity is snapshotted on insert (mig 102 `partner_*_at_event` columns) so 1099-NEC history survives a partner purge.
- `warranty-purchases.service` — three-phase cancel that uses the `cancelling` transient enum value (mig 098). Prorated refund computed via `proratedRefundCents`; idempotency key `warranty-refund-{purchaseId}`.
- `email-scanner.service` — `TRUSTED_RETAILER_DOMAINS` allowlist, `AUTO_CREATE_CONFIDENCE_THRESHOLD=0.85`, H42 DKIM-alignment gate (parses `Authentication-Results`, requires DMARC=pass or `header.d` / `header.i` matching the From: domain), H46 pulls `internetMessageHeaders` on Outlook so the same gate is evaluable, H41 paginates via Gmail `pageToken` / Outlook `@odata.nextLink` with `PER_SCAN_PROCESS_CAP=500`, H43 wraps the user body in `BODY_DELIM` and tells the system prompt to treat it as data only, H44 routes a JSON.parse failure to a sentinel `parseFailed: true` row so the scan lands in the review queue instead of being silently dropped. `OPENAI_DAILY_CAP_MICROS` budget enforced by querying the `openai_user_daily_cost` view before calling Vision. OAuth tokens encrypted AES-256-GCM with key-rotation legacy list (mig 109 adds `key_version` + AAD).
- `notifications.service` — daily digest, single warranty-expiry reminder at `first_reminder_days` (default 30), push delivery via FCM/APNs, digest outbox flushed every 60s.
- `audit.service` — append-only writes that go through the hash-chain trigger (mig 065, hardened by mig 101: trigger owned by `audit_cleaner` so the API role can't drop it; trigger payload uses `to_char(... AT TIME ZONE 'UTC')` so the chain is TZ-stable across writer/verifier sessions). `verifyHashChain()` reads the `verify_audit_chain()` Postgres function and pages on drift.
- `account-purge.service` — `ADVISORY_LOCK_KEY=0xa00d_4a13`, `MAX_PER_RUN=100`, anonymizes `warranty_purchases.user_email_at_purchase` before the cascade-delete.
- `grace-reminder.service` — H78 day-25 nudge during the 30-day deletion grace window. Queries `users` where `deletion_scheduled_for - NOW() BETWEEN 4d AND 5d`, sends one email per row, stamps `last_grace_reminder_sent_at` on success so the cron can't re-send tomorrow (mig 111).
- `webhook-dead-letter.service` — `alertOnDeadLetterWebhooks()` pages once per dead-lettered row via the `webhook_events.alerted_at` stamp (mig 105). Stripe webhook signature-verification failures also page via `EmailService.sendStripeWebhookSignatureFailureAlert()` with a 15-min throttle (H30).
- Plus: `email.service` (SendGrid templates), `homes.service`, `items.service`, `maintenance.service`, `documents.service`, `referrals.service`, `tips.service`, `fcm.service`.

### 3.5 Database

PostgreSQL 16. Schema lives in `apps/api/src/db/schema.sql` (base tables) plus 111 forward-only migrations under `apps/api/src/db/migrations/`. Key migrations:

- **028–039** — security/data-loss criticals (refresh-token hashing, audit logging, etc.)
- **040–045** — DB foundation (pool config, advisory locks, schema_version table)
- **050–051** — payments + uploads (Stripe payment-intent ledger, MinIO object keys)
- **060–067** — services (warranty claims, maintenance schedules)
- **065** — `audit_log_hash_chain` — every `audit_logs` row has `this_hash = sha256(prev_hash || row_data)`. Insert trigger `audit_logs_assign_hash()` runs BEFORE INSERT; verification function `verify_audit_chain()` returns broken rows.
- **070–074** — drift constraints, partner status enum, digest outbox, repair-cost defaults
- **078** — `request_idempotency` for at-least-once retry safety
- **080/082** — advisory lock around the audit hash chain so concurrent inserts don't race
- **083** — `warranty_*.user_id RESTRICT→SET NULL` + denormalized email columns so account-purge can anonymize without losing claim history
- **084** — TOTP MFA tables
- **090** — `category_defaults.lifespan_years` seeded from the items.ts hardcoded map
- **095** — partial index on `partner_commissions` for the 30-day auto-approve sweep
- **097** — the `warranty_claim_state_history` immutable trigger now allows FK CASCADE delete from the parent claim
- **098** — `warranty_purchase_status` enum gains `cancelling` for the three-phase cancel flow's transient state
- **099/100** — `cleanup_old_audit_logs()` rewritten as `SECURITY DEFINER` under the `audit_cleaner` role; SELECT grant added because PG needs SELECT to evaluate the WHERE clause for DELETE
- **101** — `audit_logs` + trigger functions re-owned by `audit_cleaner` so the API role can't `DROP TRIGGER trg_audit_logs_immutable` and rewrite history; revoke ALL from API, re-grant SELECT+INSERT; trigger payload now uses `to_char(... AT TIME ZONE 'UTC')` so the hash is TZ-stable across writer/verifier sessions.
- **102** — `partner_gifts` / `partner_commissions` partner_id → SET NULL on partner delete; new `partner_id_at_event`, `partner_company_name_at_event`, `partner_email_at_event` columns snapshot identity at INSERT so 1099-NEC commission history survives a user purge (same pattern as mig 083 for warranty rows).
- **103** — `request_idempotency` claim-placeholder row so `INSERT...ON CONFLICT DO NOTHING` distinguishes "first writer wins" from "duplicate replay."
- **104** — `audit_action` enum: new values for admin + MFA + payout flows.
- **105** — `webhook_events.alerted_at` so H30 ops alerts mark a row "we paged on this" and a retry doesn't re-page.
- **106** — functional unique index on `LOWER(email)` so case-variant duplicate accounts can't be created.
- **107** — `users.tokens_invalidated_at`; password change / suspend bumps it so every previously-issued JWT becomes invalid without per-row deletes.
- **108** — partial unique index on `user_mfa_factors` so a single user can only have one *unverified* TOTP enrollment in flight at a time.
- **109** — OAuth integration columns: `key_version` + AAD so AES-GCM rewrap surfaces the right key at decrypt time.
- **110** — `newsletter_subscribers.confirmation_expires_at` so H77 single-use confirm tokens carry a 7-day TTL the `/confirm` gate honours.
- **111** — `users.last_grace_reminder_sent_at` + partial index; H78 day-25 grace nudge marks rows once-sent so the cron can't re-send tomorrow.

The runner auto-detects `ALTER TYPE ADD VALUE` and `CREATE INDEX CONCURRENTLY` and runs those files outside transactions. `main()` is wrapped in `pg_advisory_lock` (H-D1) so two replicas booting simultaneously can't race on the same DDL. The `schema_version` table tracks bootstrap completion.

### 3.6 Auth flows

Three sign-in paths, all terminating at the Express API:

**Email/password** — `/api/v1/auth/register`, `/login`, `/refresh`. bcrypt with SHA-256 pre-hash so passwords longer than 72 bytes still use full entropy (rather than silently truncating, which is bcrypt's default behaviour).

**Google Sign-In** — Mobile uses the native SDK with `serverClientId`. Backend `/auth/google` accepts an array of audiences via `config.google.clientId` + `GOOGLE_AUDIENCES` env (so iOS, Android, and the Services ID all map to one user record).

**Apple Sign-In** — iOS uses the native SDK; Android (and any web/desktop client) uses `WebAuthenticationOptions` with an Apple Developer Services ID. Backend `/auth/apple` accepts both audiences via `config.apple.bundleId` + `config.apple.servicesIds` (comma-separated). Per-attempt nonce is generated client-side via `AppleSignInNonce.generate()` (raw + sha256 hashed pair) and verified server-side.

Token shape:
- **Access token** — JWT HS256, 1h TTL, claims `{ userId, email, isAdmin, isPartner, exp, iat }`. Signed with `JWT_SECRET`.
- **Refresh token** — opaque 32-byte hex string. Stored as SHA-256 hash in `refresh_tokens.token_hash` so a DB compromise can't replay sessions. Rotated on every use; the previous hash is marked `revoked_at = NOW()`.

A 401 on any authenticated endpoint with the special `code: ACCOUNT_PENDING_DELETION` tells the mobile app to show the "30-day cooling-off — recover account?" path instead of bouncing the user to the welcome screen.

The dashboard's edge middleware caches `is_admin` / `is_partner` in a separate `hk_role_check` cookie (30s TTL) populated from `/api/v1/auth/role-check`, so a demoted user sees the new role within 30s rather than waiting up to JWT_EXPIRES_IN.

### 3.7 Email scanner OAuth

- **Gmail** — Mobile opens `accounts.google.com/o/oauth2/v2/auth`, captures `code` via `flutter_web_auth_2`, forwards `code + redirect_uri` to `/api/v1/email-scanner/scan`. The API exchanges them server-side using `client_secret`. State parameter is a 32-byte base64-url random string minted by `_mintOAuthState`, validated on return.
- **Outlook** — Same shape. The Azure AD app **must** be registered as a confidential / web client (not "public client"), because the API redeems the code with `client_secret`. The mobile flow intentionally does NOT send PKCE (`code_challenge`); the API never sees a verifier and Microsoft would reject a half-completed PKCE handshake.

OAuth refresh tokens are encrypted AES-256-GCM (mig 038) with iv + tag, scoped via `granted_scope`, and revocable by writing `revoked_at`. Key rotation is handled by `getCandidateKeys()` in [`apps/api/src/utils/oauth-encryption.ts`](../apps/api/src/utils/oauth-encryption.ts) — the primary key is tried first; on auth-tag failure, a list of legacy keys is tried before the operation fails, so a key rotation doesn't immediately invalidate every stored token.

### 3.8 Stripe partner gifts (3-phase flow)

The gift creation flow is the most carefully orchestrated thing in the codebase. Naively it would be: create gift row → charge card → send email. But that creates a window where the card is charged and the row is missing (or vice versa). The actual flow:

1. **Reserve** — INSERT `partner_gifts` row with `status='pending_payment'` and a generated activation code (16 hex with dashes, hashed before storage). This happens *outside* the Stripe transaction so a Stripe failure doesn't leave the API in `25P02 in_failed_sql_transaction`.
2. **Charge** — `stripe.paymentIntents.create({ amount, currency, customer, payment_method, confirm: true, off_session: true })`. The `payment_method` is passed explicitly because Stripe's default-PM resolution is unreliable when the customer has multiple cards.
3. **Promote** — UPDATE `partner_gifts` to `status='created'`, INSERT `partner_commissions` (status `pending`, will auto-approve at +30 days). If this UPDATE fails, the `reverse compensation` step refunds the PaymentIntent so the partner isn't charged for a gift that doesn't exist.

Activation is gated by Redis lockout: 5 attempts/hour per `(activation_code_hash, ip)` pair, with a 15-min lock on the 6th. Successful activation extends the homebuyer's `users.plan_expires_at` by `premium_months` (stacking on top of any existing future expiry).

Stripe webhook `charge.refunded` triggers `clawbackCommissionForGift` which inserts a *sibling reversal row* with negative `amount` and `status='reversed'` — never updates the original row. Partial refunds are proportional. The reversal row's `reversal_of_commission_id` FK points back to the original.

### 3.9 Webhooks

`apps/api/src/routes/webhooks.ts` is 1602 lines because webhook safety is a forest of edge cases. The pattern:

1. Caddy routes the raw request body to Express without compression (the `infra/Caddyfile` block has a raw-body matcher for `/api/v1/webhooks/stripe` and `/api/v1/webhooks/revenuecat`).
2. `claimWebhookEvent(eventId)` does an INSERT...ON CONFLICT into `webhook_events` with a `FOR UPDATE` row lock. If the row already exists with `processed_at IS NOT NULL`, return 200 immediately (idempotent replay).
3. Process the event. On any error, increment `attempts`. At `attempts=8` (`MAX_WEBHOOK_ATTEMPTS`) the row is moved to `dead_letter=TRUE` and a daily cron retries it.
4. Per-subject high-water (mig 050) prevents an out-of-order `subscription.updated` event from un-doing a later `subscription.deleted`.

The same machinery handles RevenueCat events (`INITIAL_PURCHASE`, `RENEWAL`, `EXPIRATION`, `TRANSFER`) for IAP subscriptions.

### 3.10 Audit log

Every privileged action is appended to `audit_logs` via `auditLog()` calls scattered through the services. The mig 065 trigger computes `this_hash = sha256(prev_hash || row_data)` BEFORE INSERT, advisory-locked so concurrent inserts can't race. A daily cron calls `verify_audit_chain()` and emails the operator if it returns any rows.

Deletion is gated: `cleanup_old_audit_logs()` runs as `SECURITY DEFINER` under the `audit_cleaner` role (mig 099). The mobile app and dashboard only read scoped subsets (`/audit/logs/me` for the dashboard's recent-activity card; `/audit/logs` for admins).

### 3.11 Idempotency

The `request_idempotency` table (mig 078) keys `(user_id, route_key, idempotency_key)` and stores the first response body. Mobile generates UUIDs at enqueue time in `offline_sync_service.dart` so re-sent in-flight queue entries collapse server-side. The middleware sits in `apps/api/src/middleware/idempotency.ts` and runs on every mutating route.

### 3.12 Rate limiting

`apps/api/src/middleware/rateLimiter.ts` defines route-keyed buckets in Redis. Buckets are separated by IP for unauthenticated routes (login, register, forgot-password) and by user_id for authenticated routes. Limits range from 5/hour for login attempts to 100/min for read-heavy authenticated routes.

### 3.13 User cache

`invalidateUserCache(userId)` is called on every `users` row mutation (plan change, admin toggle, soft-delete, profile update). The cache is a Redis `GET/SET` with 10s TTL on `user:{id}`. Without this, `/me` would hit the DB on every navigation. With it, a plan upgrade is reflected within 10s — which is fine because the user just *did* the upgrade and the optimistic UI already shows it.

---

## 4. Mobile — `apps/mobile`

### 4.1 Stack

- **Flutter** with Dart SDK `^3.0.0`. Material 3 with a custom dark theme from `shared_ui`.
- **Riverpod** for state management. 19 providers cover auth, items, homes, maintenance, notifications, premium, partners, etc. Async providers everywhere; never `setState` for shared state.
- **Dio** is wrapped by `package:api_client` — mobile code never touches `dio` directly. All API calls go through the typed `ApiClient` exposed via `apiClientProvider`.
- **`sqflite_sqlcipher`** for the local Drift database. Per-user encrypted file at `havenkeep-{sha256(userId).slice(0,16)}.sqlite`. SQLCipher AES-256.
- **`flutter_dotenv`** for env config — NOT dart-defines. Different env files per flavor: `.env.development`, `.env.staging`, `.env.production`. `scripts/prepare-env.sh <flavor>` copies the right one to `.env` before `flutter run` / `flutter build`.
- **Bundle ID** `app.havenkeep.mobile` on both iOS and Android.

### 4.2 Bootstrap (`main.dart`)

[`apps/mobile/lib/main.dart`](../apps/mobile/lib/main.dart) is 455 lines because it's the place every cross-cutting concern lives:

- `runZonedGuarded` so any uncaught async error reaches Crashlytics as non-fatal.
- `FlutterError.onError` → `recordFlutterFatalError` for framework-level crashes.
- `PlatformDispatcher.instance.onError` for platform errors (records as fatal).
- `_crashlyticsReady` flag gates every Crashlytics call so a developer build with no Firebase API key still works.
- `registerUnknownEnumReporter` plugs into `shared_models`'s `_unknown_enum_log.dart` funnel and writes a Crashlytics breadcrumb (`enum_drift: ClaimStatus → unknown_value=foo, fallback=filed`) for every unknown enum the server emits. This is the early-warning system for "we shipped a server change, then it crashed five seconds later."
- Biometric lock with 30s grace via `_backgroundedAt` so the user isn't re-prompted for Face ID every time they switch apps for two seconds.
- A `ProviderScope` overrides `apiClientProvider` with the bootstrapped `ApiClient` (with TLS pinning enabled in release builds — see §4.7).

### 4.3 Routing (`go_router`)

[`apps/mobile/lib/core/router/router.dart`](../apps/mobile/lib/core/router/router.dart) defines a `ShellRoute` with a bottom navigation bar (Dashboard / Items / Maintenance) plus full-screen modals via `parentNavigatorKey: _rootNavigatorKey`. Auth guard redirects to `/welcome` when unauthenticated.

Deep links:
- `havenkeep://gift/<code>` and `https://havenkeep.com/gift/<code>` open the gift-activation screen. If the user is unauthenticated, the code is stashed in SharedPreferences (`pending_gift_code`) and the welcome screen resumes the flow after sign-up.
- `havenkeep://referral/<code>` mirrors the gift pattern for referral codes.

Web-only paths (`/verify-email`, `/reset-password`, `/verify-email-change`) intentionally do NOT universal-link into the app — the user might click those on a laptop or family member's phone, where opening the app on a different device is the wrong UX.

### 4.4 Offline-first sync

[`apps/mobile/lib/core/services/offline_sync_service.dart`](../apps/mobile/lib/core/services/offline_sync_service.dart) is the heart of the mobile architecture.

- **Queue**: Drift table `OfflineQueue` with FIFO replay, capped at 500 entries and a 7-day stale eviction.
- **Retry policy**: 3 retries with exponential backoff (300ms → 600ms → 30s).
- **Sealed-class catch**: every queue replay catches `ApiException` and switches on the subtype:
  - `ApiAuthRequiredException` → single retry after token refresh, then mark failed.
  - `ApiForbidden` / `NotFound` / `Validation` → mark failed, never retry (the request is broken; retrying won't fix it).
  - `ApiConflict` → for `update_item`, write to the `sync_conflicts` table for human resolution. Other entity types are marked failed.
  - `ApiRateLimited` / `Server` / `Network` / `Timeout` / `Unknown` → retriable.
- **Conflict resolution UI**: [`apps/mobile/lib/features/settings/conflicts_screen.dart`](../apps/mobile/lib/features/settings/conflicts_screen.dart) shows local vs server side-by-side and lets the user pick a winner.
- **Idempotency keys**: generated as UUIDs at enqueue time and stored in the queue row. A re-sent in-flight entry hits the API's `request_idempotency` table and collapses server-side.

### 4.5 Local database

[`apps/mobile/lib/core/database/database.dart`](../apps/mobile/lib/core/database/database.dart) is the Drift schema. `schemaVersion=5`. Key tables: `Items`, `Homes`, `Documents`, `Notifications`, `OfflineQueue`, `SyncConflicts`, `MaintenanceHistory`, `MaintenanceCustomizations`, `RecentlyViewed`, `KvStore`.

Per-user file: `havenkeep-{sha256(userId).slice(0,16)}.sqlite`. SQLCipher key (32 random bytes) is stored in flutter_secure_storage with `KeychainAccessibility.first_unlock_this_device` — explicitly NOT iCloud-replicable, so an attacker who compromises the user's iCloud Keychain on a fresh device can't restore the local DB. PRAGMA `cipher_version` is checked on open to ensure SQLCipher is actually active. `_bytesToHex` zeroes out the key buffer right after the `PRAGMA key=` call.

### 4.6 Riverpod providers

19 providers in `apps/mobile/lib/core/providers/`. The interesting patterns:

- `currentUserProvider` — `AsyncNotifier<User?>` that reads `/me` on init and listens to `apiClient.authStateChanges`. The mobile app's source of truth for "am I signed in".
- `itemsProvider` — Drift query first, API fetch in the background, merge on conflict. The home dashboard renders instantly from local data, then updates as the API responds.
- `currentHomeProvider` — drives the multi-tenancy filter cascade. `itemsProvider`, `maintenanceProvider`, `warrantyClaimsProvider`, etc. all consume it.
- `isPremiumProvider` — derived from `currentUserProvider`. RevenueCat status syncs to the server, so this is the single source of truth.
- `offlineSyncServiceProvider` — kicks off automatic sync on connectivity changes.

### 4.7 TLS pinning

Release builds construct the `ApiClient` with an `IOClient` backed by a `SecurityContext` pinned to the issuer's SPKI. Debug builds use the platform trust store. The pin is pulled from `.env.<flavor>` at boot. A `badCertificateCallback` runs `_spkiMatches(cert, expectedSpkiSha256)` on every TLS handshake; mismatch → connection rejected.

### 4.8 Telemetry

- **Always-on**: `dart:developer.log` on every meaningful event (`auth.login_success`, `sync.queue_drained`, `enum_drift`, etc.). Visible in Logcat / OSLog / `flutter logs`.
- **Crashlytics**: enabled in release builds via the `_crashlyticsReady` flag. Forwards FlutterError + zoned errors. Custom keys include `user_id`, `flavor`, `app_version`, `last_sync_at`.
- **No third-party analytics SDK.** The `Tip` `usage events` mentioned in the privacy policy are first-party HTTP POSTs, not Mixpanel/Segment.

### 4.9 Features (selected)

The mobile app has 19 feature folders. Highlights:

- **Add item** has 4 entry paths: quick-add (3x3 category grid), barcode scan (mobile_scanner + `barcode-lookup` API), receipt scan (camera + AI OCR), manual entry. The wizard variant ([`apps/mobile/lib/features/add_item/wizard/`](../apps/mobile/lib/features/add_item/wizard/)) is a 3-step flow with autosaved draft (24h TTL in SharedPreferences) so a backgrounded form isn't lost.
- **Item detail** ([`apps/mobile/lib/features/item_detail/`](../apps/mobile/lib/features/item_detail/)) covers view, edit, document upload (camera/gallery/file picker; image compression; persisted to app-support dir to survive temp-dir wipes), share-claim sheet, PDF preview.
- **Email scanner** ([`apps/mobile/lib/features/email_scanner/email_scanner_screen.dart`](../apps/mobile/lib/features/email_scanner/email_scanner_screen.dart)) walks the user through OAuth, shows connected accounts with disconnect buttons, displays the review queue (parsed receipts that didn't auto-import), and runs a progress dialog with a `Completer`-driven dismiss.
- **Maintenance dashboard** ([`apps/mobile/lib/features/maintenance/maintenance_screen.dart`](../apps/mobile/lib/features/maintenance/maintenance_screen.dart)) groups due tasks by item, supports bulk-mark-done, snooze, and a 7/30/90-day window filter that honors overdue tasks (overdue tasks are never "out of window").
- **Premium** ([`apps/mobile/lib/features/premium/premium_screen.dart`](../apps/mobile/lib/features/premium/premium_screen.dart)) reads the live RevenueCat offering and renders real `priceString` values so a price change in App Store Connect doesn't ship a stale label.
- **Settings** has a hidden 5-tap escape on the version label that opens [`developer_options_screen.dart`](../apps/mobile/lib/features/settings/developer_options_screen.dart) — runtime demo-mode toggle for QA without a separate build flavor.

---

## 5. Partner dashboard — `apps/partner-dashboard`

### 5.1 Stack

- **Next.js 15** (App Router) with React server components.
- **Tailwind** for styling, shared dark theme tokens with the marketing site.
- Deployed as a standalone Node.js app behind Caddy; the same-origin proxy at `/api/v1/[...path]` is the *only* way the browser reaches the Express API.
- **No client-side state library.** Server components fetch data via `serverApiClient` (cookie-bound JWT); client components use `useEffect` + `apiClient` from `lib/api.ts`.

### 5.2 Auth model

Three cookies:
- `hk_access_token` — httpOnly, secure (prod), `SameSite=Lax`, 1h TTL. JWT.
- `hk_refresh_token` — same flags, 7d TTL. Opaque.
- `csrf_token` — **not httpOnly** (the double-submit pattern needs JS read access), `SameSite=Lax`, 7d TTL. 24-byte base64-url random.

Edge middleware ([`apps/partner-dashboard/middleware.ts`](../apps/partner-dashboard/middleware.ts)) runs on every request:
1. Decode the access token; if expired (with 30s skew), POST `/api/v1/auth/refresh` with the refresh token. 5s timeout. On failure → `redirectToLogin`.
2. Cache `is_admin` / `is_partner` in a separate `hk_role_check` cookie (30s TTL, httpOnly) populated from `/api/v1/auth/role-check`. This is H-A8 from the audit: the JWT's `isAdmin` claim is from when the token was minted, so a demoted user kept seeing the admin shell for up to 1 hour. With the cache, demotion takes effect within 30s.
3. Route protection: `/admin/*` requires `isAdmin`; `/dashboard/*` requires `isPartner` (admins are also allowed via `requirePartnerOrAdmin`).
4. Mint the CSRF cookie if missing.

### 5.3 The proxy

[`apps/partner-dashboard/src/app/api/v1/[...path]/route.ts`](../apps/partner-dashboard/src/app/api/v1/[...path]/route.ts) is the security boundary. The browser ships a cookie-bound JWT to *the dashboard*; the proxy mints a `Bearer` header from that JWT and forwards the request to Express. The browser never sees the JWT.

Five guarantees:
1. **Path validation** — every segment must match `/^[A-Za-z0-9._~-]{1,128}$/`. Rejects `..`, encoded slashes, query-style chars.
2. **Header allowlist** — only `content-type`, `accept`, `accept-language`, `x-request-id`, `idempotency-key` are forwarded. Browser cookies and arbitrary headers are stripped.
3. **CSRF on mutations** — POST/PUT/PATCH/DELETE require `Sec-Fetch-Site` to be `same-origin` or `same-site` AND a valid double-submit `X-CSRF-Token` header matching the `csrf_token` cookie (constant-time-ish comparison in `lib/csrf.ts`).
4. **Cookie strip** — the `cookie` header is *never* forwarded. The Express API has a "no cookies = bypass CSRF check" branch; the proxy relies on this and runs its own CSRF check at the proxy layer. (Adding `cookie` to the allowlist would double-validate CSRF and silently break every mutation.)
5. **Response header reduction** — only `content-type`, `cache-control`, `etag`, `last-modified`, `x-request-id` come back. No `Set-Cookie` leak.

### 5.4 Pages

```
src/app/
├── (public)
│   ├── login/                          # email + password
│   ├── signup/                         # creates a user account; partner profile is in onboarding
│   ├── forgot-password/
│   ├── reset-password/[token]/
│   └── unauthorized/
├── onboarding/                         # 2-step partner profile wizard (after signup, before /dashboard)
├── dashboard/                          # /dashboard requires isPartner
│   ├── page.tsx                        # gifts/commissions/earnings overview
│   ├── gifts/                          # list + create gift modal + detail page
│   ├── referrals/
│   ├── analytics/                      # conversion funnel + earnings chart + date-range filter
│   ├── commissions/
│   ├── payouts/                        # request payout, tax docs link to Stripe Express dashboard
│   └── settings/                       # partner profile + Stripe Connect onboarding
└── admin/                              # /admin requires isAdmin (layout-level gate)
    ├── page.tsx                        # platform stats (DAU/WAU/MAU, premium %, total value protected)
    ├── users/                          # search, suspend, hard-delete (typed-DELETE confirm)
    ├── partners/                       # list + detail; approve / reject pending applications
    ├── commissions/                    # approve / pay / cancel
    ├── audit/                          # log viewer with severity filter + expandable metadata
    ├── analytics/                      # daily signups + items charts
    ├── health/                         # /health/detailed for db / redis / minio status
    └── settings/                       # admin account info
```

### 5.5 Hardening details

- Money formatting via `formatCurrency()` accepts both string (canonical wire format for `DECIMAL`) and number, so cents don't drift through float conversion.
- Logo URLs validated with `isSafeLogoUrl()` (http/https only, ≤2048 chars) before render.
- Activation-URL clipboard via `isSafeActivationUrl()` rejects anything not on a small allowlist of HavenKeep-owned hostnames — a tampered upstream response can't seed a phishing link.
- Audit-log metadata renders cap at 4096 bytes (`safeStringifyMetadata`) so an entry with a megabyte of upstream API payload doesn't block the main thread.
- `logError()` strips known sensitive keys (`authorization`, `cookie`, `password`, `csrf_token`, etc.) before forwarding to `console.error`.
- API-error rewrite: `serverApiClient` maps every non-2xx status to a generic message (`"The service is temporarily unavailable. Please try again."`) so internal stack-trace tails / DB-driver text never leak to admin UI.

### 5.6 Testing

`vitest` config in [`apps/partner-dashboard/vitest.config.ts`](../apps/partner-dashboard/vitest.config.ts). Tests live in `src/__tests__/` and cover login/signup actions, the proxy refresh-race scenario, the AuthForm component, the StatsCard, the Pagination, and lib/{api,auth,utils}.

---

## 6. Marketing site — `apps/marketing`

### 6.1 Stack

- **Astro** static site. Tailwind for styling, dark theme matched to the dashboard.
- **Self-hosted Inter** via `@fontsource/inter` so visitor IPs aren't leaked to Google Fonts and a strict CSP doesn't have to allow `fonts.googleapis.com`.
- Deployed as static files behind Caddy. CSP / X-Frame-Options / etc. are set by Caddy in front of the static host.
- Sitemap + RSS shipped by `astro-sitemap` and `src/pages/rss.xml.js`.

### 6.2 Pages

- `/` — landing (Hero, Stats, HowItWorks, Features, Testimonials, Pricing, CTA, Footer).
- `/features`, `/pricing`, `/partners`, `/about`, `/security`, `/contact`, `/faq`, `/roadmap`, `/careers`, `/cookies`, `/licenses`.
- `/blog` and 6 blog posts under `/blog/*`.
- **`/legal/privacy`, `/legal/terms`, `/legal/delete-account`** — required by App Store + Play Store. The delete-account page describes the in-app path *and* the email path (Google Play's policy mandates a no-login-required deletion option).
- **`/verify-email-change`** — consumes the change-email token via `POST /api/v1/auth/verify-email-change`. The mobile app's email-change flow points the link here.

### 6.3 Per-page OG images

[`apps/marketing/src/layouts/Layout.astro`](../apps/marketing/src/layouts/Layout.astro) auto-resolves `/og/<slug>.png` based on the current pathname (PAGES list in `scripts/build-og-image.cjs`), with fallback to `/og-image.png`. Adding a new page means adding it to that list before the next deploy.

### 6.4 Contact form

`/contact` POSTs to `/api/v1/contact` with same-origin `credentials: 'omit'`. Honeypot field (`name="website"`, visually + a11y hidden) — naive bots fill it; the API drops any submission with a non-empty value. IP rate limiting upstream. No third-party CAPTCHA.

---

## 7. Shared packages

### 7.1 `packages/shared_models`

Every JSON envelope the API hands back is mirrored here as a Dart class. Naming and field types match the database column shape (snake_case keys; `DECIMAL` columns parsed as both `num` and string). Each class has `fromJson`, `toJson`, `copyWith`, and where applicable a `toCreateJson` / `toInsertJson` that strips server-managed fields (id, created_at, updated_at, generated columns).

The `_unknown_enum_log.dart` funnel is the early-warning system for server/client enum drift. Every enum's `factory fromJson(String)` calls `logUnknownEnumValue` on a miss before falling back to a safe default. The bootstrap registers a custom reporter that writes a Crashlytics breadcrumb so we see the drift in production within seconds of a server deploy.

### 7.2 `packages/api_client`

`ApiClient` is a thin wrapper around `package:http`. The interesting pieces:

- **Sealed `ApiException`** with 9 typed subclasses (`ApiAuthRequiredException`, `ApiForbiddenException`, `ApiNotFoundException`, `ApiConflictException`, `ApiValidationException`, `ApiRateLimitedException`, `ApiServerException`, `ApiNetworkException`, `ApiTimeoutException`, `ApiUnknownException`). The factory `ApiException.fromResponse(status, message)` mints the right subtype.
- **`pathSegments` API** — segments are percent-encoded by `Uri`. The legacy `path:` API is `@Deprecated` and is acceptable only for hard-coded routes with no interpolation.
- **Auto-refresh on 401** — `_withAutoRefresh` catches a 401, calls `refreshAccessToken()` (single-flight via a `Completer` mutex so concurrent calls share one refresh), retries the original request once. Network errors during the *retry* are mapped to typed exceptions, not silently swallowed.
- **`Idempotency-Key` header** on every mutating method.
- **`x-request-id`** generated as 16 random bytes (32 hex chars) per request. Logged via `dart:developer.log`. The server's pino logger accepts and echoes it, so a "report this issue" path can copy a single id that resolves both halves of the trace.
- **`redactSensitive(String)`** — masks `Bearer <token>` and JWT-shaped strings before any error message reaches the log callback.
- **TLS pinning** — release builds construct the client with a pinned `IOClient`; debug builds use the platform trust store.
- **flutter_secure_storage** with `KeychainAccessibility.first_unlock_this_device` for the access + refresh tokens (NOT iCloud-replicable).
- **`restoreSession()`** is robust to network blips — only `ApiAuthRequiredException` clears tokens; transport errors leave tokens in place and surface as "we're offline".

### 7.3 `packages/shared_ui`

The design system. `HavenColors` (background / surface / elevated / primary / secondary / accent / gold / active / expiring / expired / textPrimary / textSecondary / textTertiary / border), `HavenSpacing` (xs/sm/md/lg/xl/xxl), `HavenRadius` (pill/input/button/card/chip/micro), `HavenIconSize`, `HavenText` (hero/stat/displayLarge/...), `HavenMotion` (fast/medium/slow/celebration durations + standard/emphasized/spring curves).

`HavenTheme.dark` produces the Material 3 ThemeData consumed by `apps/mobile`. Custom tap feedback (soft indigo glow), branded card shadows (indigo-tinted), and floating SnackBar config are theme-level rather than per-feature.

Reusable widgets: `BrandAutocompleteField` (with "Other..." fallback), `CategoryIcon` (emoji per `ItemCategory`), `WarrantyDurationPicker` (number + unit composition), `ItemLimitBanner` (free-plan progress UI), `ConfirmationDialog` (with `isDestructive` red variant), `SectionHeader` (small-caps), `RoomPicker`, `HavenSkeleton` (line/box/card with shimmer), `HavenAccordion`, `HavenSnackBar` helper, `WarrantyStatusBadge`, `DocumentTypeIcon`.

---

## 8. Staging deployment

Staging lives on a shared Digital Ocean droplet at `206.189.26.12` (Ubuntu 24.04, 8 GB / 2 vCPU). Eight apps share the box plus shared infra (Postgres, MinIO, Redis, Caddy, Dozzle). HavenKeep does NOT run its own Postgres/Redis/MinIO — it consumes the shared `infra-postgres` / `infra-redis` / `infra-minio` containers on the `staging-net` Docker network.

The deploy system lives at `~/Projects/staging/` (separate repo, not in this monorepo). Flow:

```sh
cd ~/Projects/staging
./ship.sh havenkeep            # builds 3 images on laptop, scps tarballs, deploys
./rollback.sh havenkeep        # roll back to previous image tag
```

`ship.sh` builds `havenkeep-api`, `havenkeep-dashboard`, `havenkeep-marketing` for `linux/amd64`, saves as gzipped tarballs, scps to `/opt/staging/havenkeep/images/`, then SSHes and triggers `/opt/staging/havenkeep/deploy.sh <tag>`. The droplet-side `deploy.sh` runs migrations as a one-shot container (`profile: migrate`) before flipping `IMAGE_TAG=` in `.env` and `docker compose up -d --force-recreate`. Failed healthchecks roll back automatically.

| Surface | URL | Container | Bound to |
|---|---|---|---|
| Marketing | `https://staging.havenkeep.app` | `havenkeep-marketing` | `staging-net:4321` (Astro preview) |
| API | `https://api.staging.havenkeep.app` | `havenkeep-api` | `staging-net:3000` |
| Partner dashboard | `https://partner.staging.havenkeep.app` | `havenkeep-dashboard` | `staging-net:3001` |

(Subdomain note: staging uses `partner.` singular — that's what the live Caddyfile binds.)

Staging secrets live on the droplet, not in this repo:
- `/opt/staging/havenkeep/.env` — just `IMAGE_TAG=<tag>`, read by compose.
- `/opt/staging/havenkeep/.env.api` — API runtime env.
- `/opt/staging/havenkeep/.env.dashboard` — Next.js runtime env.
- `/opt/staging/infra/.env` — shared infra (postgres root password, per-app DB passwords, MinIO root + 6 per-app keypairs, Redis password).

Logs: `https://logs.staging.kouakoudomagni.com` (Dozzle, basic auth) or `ssh root@206.189.26.12 'docker logs havenkeep-api -f'`.

---

## 9. Security model

- **Auth** — JWT HS256 with refresh-token rotation, hashed-at-rest in DB. MFA via TOTP. Generic 401s on auth failures so "user exists" can't be enumerated.
- **TLS** — TLS 1.2+ on every link. Mobile pins SPKI in release builds.
- **At-rest** — AES-256-GCM for sensitive fields (OAuth refresh tokens, MFA secrets); full-disk encryption on the database host; SQLCipher on the mobile DB; MinIO encrypts objects at rest.
- **CSRF** — double-submit pattern on dashboard mutations. The API trusts the proxy via the "no cookies = no CSRF check" branch.
- **CSP** — helmet-locked to `api.stripe.com` + `api.revenuecat.com`. Marketing site CSP set by Caddy.
- **Audit log** — sha256 hash chain with daily verification. `SECURITY DEFINER` cleanup function under `audit_cleaner` role.
- **Account deletion** — soft-delete with 30-day cooling-off → cryptographic erasure. `users.email` is anonymized; FK-cascaded rows have their `user_id` SET NULL with denormalized email columns retained for legal/audit purposes.
- **Rate limiting** — Redis-backed buckets per route, per IP (unauth) or per user (auth).
- **Webhooks** — signature verified on raw body; dead-letter at 8 attempts.
- **Path injection** — every dashboard proxy segment validated against a strict allowlist; mobile uses `pathSegments`.

---

## 10. Things that are NOT in this codebase

- **No GraphQL.** REST + JSON envelope.
- **No Prisma / Drizzle / Sequelize.** Raw `pg` queries.
- **No Redux / Bloc / GetX on mobile.** Just Riverpod.
- **No Sentry.** Loki + Crashlytics.
- **No advertising SDKs.** None in any surface.
- **No third-party analytics SDK on mobile.** First-party usage events only.
- **No production deployment.** Staging works; production is months away (see CLAUDE.md Part 3).
