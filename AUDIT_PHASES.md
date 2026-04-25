# HavenKeep — Audit Remediation Plan (10 Phases)

**Source:** `AUDIT.md` (2026-04-24, 1,285 findings across 13 chapters).
**This file:** Sequencing + scope. Every finding ID is listed against the phase that owns it.
**Convention:** Finding IDs match the AUDIT.md doc exactly (e.g., `Ch01-F014`, `Ch08-Item-D008`). 🔴 = Critical. Sev: Critical / High / Medium / Low. File:line references in AUDIT.md itself — go there for the full body.

---

## How to use this plan

1. **Land phases in order.** Phase N+1 assumes Phase N is on `main`. Skipping order will reintroduce defects that downstream phases assume gone.
2. **Phase 1 is the only cross-cutting phase.** It pulls every 🔴 critical from every chapter and ships them as one urgent slice. Phases 2–10 follow the dependency graph and may revisit related items during broader cleanup of their subsystem (intentional overlap — Phase 1 = stop-the-bleeding, later phases = clean the wound).
3. **Verify "likely-stale" items first.** Each phase lists IDs that may already be resolved by recent commits (`58a8bda` Google/Apple sign-in, `741c43d` marketing domain, `241231e` privacy/legal pages, `c05bd4e` mobile deploy, `d8ea43e` Android/iOS compliance). Confirm with `git log -p` on the cited file before re-implementing.
4. **CLAUDE.md rules apply throughout** — purge dead code, no backfill shims, no deferred work, lint/typecheck/test must be clean per phase. "Already-broken" warnings in touched files are part of the phase's scope.
5. **Each phase's acceptance gate**: full clean of the four checks listed in `CLAUDE.md` for the affected app(s) — `tsc --noEmit` + `npm test` (api), `flutter analyze` + `flutter test` + `flutter build apk --debug` (mobile), `npm run build` (marketing/dashboard).

## Recent-commit verification list

Before starting any phase, sanity-check these files against `git log` to skip findings already fixed:

| Commit | Touched | Phases that may have stale items |
|---|---|---|
| `741c43d` | marketing domain + EU hosting claim | 10 (W067, W071, W101, W112) |
| `241231e` | marketing privacy + legal pages | 10 (W095, W096, W097, W098, W099, W110) |
| `c05bd4e` | mobile-deploy gaps | 9 (none direct — sanity check) |
| `58a8bda` | Google + Apple sign-in iOS/Android | 4 (Ch01-F022, F023, F024, F025, F026, F027, F028) |
| `d8ea43e` | Android Fastlane + iOS export compliance | 9 (none direct — sanity check) |

---

## Phase summary

| Phase | Title | Findings | Critical | Apps |
|---|---|---|---|---|
| 1 | Critical security & data-loss blockers | ~84 (cross-cutting) | 🔴 84 | all |
| 2 | DB schema + migration foundation | 67 | 4 | api |
| 3 | API infra: middleware/headers/logger/redis/utils | 85 | 5 | api |
| 4 | Auth surface (users/admin/OAuth/CSRF/sessions) | 88 | 2 | api |
| 5 | Payments / partners / webhooks / Stripe Connect | 178 | 7 | api + dashboard |
| 6 | Uploads / documents / items CRUD / receipts / OCR | 91 | 2 | api + mobile |
| 7 | Warranty / maintenance / notifications / stats / scanner / audit / barcode / newsletter / contact / health | 158 | 8 | api |
| 8 | Payload drift alignment (Dart ↔ Joi ↔ DB, 20 entities) | 89 | 3 | api + packages |
| 9 | Mobile (screens / core / packages) | 348 | 18 | mobile + packages |
| 10 | Partner dashboard + marketing site + test suite | 142 | 21 | dashboard + marketing + api |

Phase 1 deliberately overlaps the others: its IDs reappear inside the chapter that owns the broader cleanup. Don't skip them in the later phase — Phase 1 ships the stop-gap, the later phase ships the sweep.

---

# Phase 1 — Critical security & data-loss blockers

**Goal.** Patch every 🔴 critical finding in the audit before doing anything else. These items (a) actively lose money or PII, (b) bypass auth, (c) destroy paid records, (d) enable MITM/SSRF/stored-XSS, or (e) leave mobile data unencrypted at rest.

**Files touched.** Spans `apps/api`, `apps/mobile`, `apps/partner-dashboard`, `packages/`. This phase is intentionally cross-cutting — pre-1.0 stop-the-bleed.

**Depends on.** Nothing. This is the entry point.

**Success criteria.**
- All 🔴 IDs below either fixed or marked stale-verified.
- Full test/typecheck/build sweep across all affected apps.
- New tests for the auth-bypass, data-loss, and money paths (no test that asserts buggy behavior — see Ch12-R001..R020 for the worst offenders).

### Critical items (84 unique IDs, grouped by blast radius)

#### Money / billing / Stripe Connect (12)
- 🔴 **Ch00-DB031** — `warranty_purchases` ON DELETE CASCADE wipes paid policies → SET NULL/RESTRICT.
- 🔴 **Ch00-DB032** — `warranty_claims` CASCADE destroys settled claims → SET NULL/RESTRICT.
- 🔴 **Ch00-DB033** — `partner_commissions` CASCADE wipes commission history → ON DELETE RESTRICT.
- 🔴 **Ch00-DB034** — `partner_gifts` CASCADE wipes gift records → ON DELETE RESTRICT.
- 🔴 **Ch03-F002** — RC webhook ignores SANDBOX environment → gate on `environment !== 'PRODUCTION'`.
- 🔴 **Ch03-F011** — `charge.refunded` doesn't clawback paid commissions → add `reversed` enum + clawback ledger.
- 🔴 **Ch03-F012** — Commission `paid` is a DB flag with no Stripe transfer → wire `stripe.transfers.create` with idempotency key.
- 🔴 **Ch03-F013** — Pay endpoint TOCTOU enables double payout → conditional `UPDATE WHERE status='approved'`.
- 🔴 **Ch03-F045** — Body parsing order can break Stripe signature verify → mount `express.raw()` for `/webhooks/stripe`.
- 🔴 **Ch03-F054** — `paid_commissions` sum lies (no payout wired) → filter on `stripe_transfer_id IS NOT NULL`.
- 🔴 **Ch03-F067** — Connect model self-inconsistent (partner pays + earns) → pick destination charges or drop platform commissions.
- 🔴 **Ch11-I044** — `STRIPE_WEBHOOK_SECRET` optional in prod → promote to `PRODUCTION_REQUIRED`.

#### Auth bypass / session integrity (8)
- 🔴 **Ch01-F011** — `/auth/verify-email` accepts change-email tokens → branch on metadata.
- 🔴 **Ch01-F020** — `/auth/refresh` trusts `decoded.userId` → only invalidate via `token_family_id`.
- 🔴 **Ch04-F088** — `audit_logs` mutable (UPDATE/DELETE permitted) → add BEFORE trigger preventing mutation.
- 🔴 **Ch04-F090** — `/audit/cleanup` has no MFA recheck → require strong confirmation + immutable system log.
- 🔴 **Ch10-W018** — Reset-password bypasses signup password complexity → share `validatePassword` util.
- 🔴 **Ch11-I002** — Stripe raw body mount fragile vs json bodyparser → route-specific raw on POST.
- 🔴 **Ch12-T030** — Forged `isAdmin` token grants untested → sign `isAdmin:true`; assert 403.
- 🔴 **Ch12-T031** — Mass assignment on PUT `/users/me` untested → submit `is_admin/plan`; assert ignored.

#### Data exfil / proxy / SSRF / dashboard (6)
- 🔴 **Ch10-W001** — Dashboard proxy forwards browser cookies alongside re-issued admin Bearer → allowlist headers; strip cookie.
- 🔴 **Ch10-W002** — Proxy path traversal via `..` segments enables SSRF → validate segment regex.
- 🔴 **Ch10-W003** — No CSRF/origin guard on cookie-authed proxy → require `Sec-Fetch-Site: same-origin` + double-submit token.
- 🔴 **Ch10-W005** — Wholesale upstream headers leaked incl. `Set-Cookie`/CORS → allowlist response headers.
- 🔴 **Ch10-W028** — Gift-page mutations have no CSRF token; `SameSite=Lax` → issue double-submit token.
- 🔴 **Ch07-P014** — `api_client` URL path concat allows path injection → segments-based API with percent-encoding.

#### PII / prompt injection / data flow (10)
- 🔴 **Ch04-F003** — `savings_feed` splices unsanitized city → stored XSS → whitelist template; strip city.
- 🔴 **Ch04-F059** — Gmail OAuth token accepted from client → use server-side OAuth code flow.
- 🔴 **Ch04-F108** — Newsletter has no double-opt-in (subscribe-anyone) → add `pending_confirmation` + confirm email.
- 🔴 **Ch09-FlowA-T-A3** — `logger.warn` ships full OpenAI response with PII to Loki → slice content + redact digit runs.
- 🔴 **Ch09-FlowA-T-A9** — OpenAI total unbounded (NaN/Inf/negative) reaches DB → `Number.isFinite` + range bounds.
- 🔴 **Ch09-FlowA-T-A14** — Base64 body may flow to logs unredacted → add `req.body.image` to pino redact.
- 🔴 **Ch09-FlowB-T-B1** — Request logger may capture third-party access token → add `access_token`/`accessToken` to pino redact.
- 🔴 **Ch09-FlowB-T-B6** — Prompt injection in email body bypasses `isRelevantPurchase` → trusted sender domain list or review queue.
- 🔴 **Ch09-FlowB-T-B7** — Generic catch-all Gmail query lets spoofed sender auto-import items → drop or vet from-domain.
- 🔴 **Ch11-I056** — Pino has no redact paths → add redact for auth/cookie/password/token/api keys.

#### Partner gift fraud / activation code (6)
- 🔴 **Ch09-FlowC-T-C2** — 32-bit activation code online-feasible to brute-force → raise to 64–80 bits + per-IP limiter.
- 🔴 **Ch09-FlowC-T-C3** — `/verify-code` is enumeration oracle → require email as 2nd factor.
- 🔴 **Ch09-FlowC-T-C5** — Homebuyer email check accepts unverified accounts; self-gift fraud → require `email_verified=TRUE` at activate.
- 🔴 **Ch09-FlowC-T-C9** — Partner self-gifts via secondary email → check partner-network emails + manual review.
- 🔴 **Ch09-FlowC-T-C10** — Stripe Connect transfer never initiated by code → create transfer in admin pay route or remove Connect.
- 🔴 **Ch09-FlowC-T-C16** — `activation_code/url` plaintext in DB + email + logs → store `SHA-256(code)`, verify by hash.

#### Mobile placebo security / data at rest (10)
- 🔴 **Ch06-C104** — Sync mutex hole on `_pendingSync` → drop `pendingSync`; re-enter on listener.
- 🔴 **Ch06-C105** — 401 retry transitions `failed↔pending` in same pass → single update.
- 🔴 **Ch06-C108** — Conflict resolver silently last-write-wins → park to conflicts table, prompt dialog.
- 🔴 **Ch06-C109** — `signOut`/`deleteAccount` don't wipe local DB or queue → clear DB and SecureStorage before invalidate.
- 🔴 **Ch06-C110** — Biometric unlock is placebo (only toggle calls auth) → `WidgetsBindingObserver` lock screen on resume.
- 🔴 **Ch06-C128** — `isPremiumProvider` OR-joins RC and plan → single server-side source of truth.
- 🔴 **Ch06-C136** — `error.toString()` not scrubbed (token/password leak) → add `error` to scrubber + Bearer regex.
- 🔴 **Ch06-C145** — Local SQLite unencrypted (PII at rest) → adopt `drift_sqlcipher` with key from secure storage.
- 🔴 **Ch06-C151** — Single global DB across users → wipe on signout or prefix file by user-hash.
- 🔴 **Ch06-C176** — No certificate pinning (MITM) → pin SPKI in release builds.

#### Mobile money / warranty math / OAuth (8)
- 🔴 **Ch05-F021** — `_addMonthsSafe` off-by-one near month edges → safe month arithmetic with last-day clamp.
- 🔴 **Ch05-F034** — Gift expiry computed with naive month math → share `_addMonthsSafe` helper.
- 🔴 **Ch05-F100** — Hardcoded prices bypass RevenueCat offerings → fetch Offerings, render `priceString`.
- 🔴 **Ch05-F109** — OAuth account delete trusts JWT alone → re-auth via provider SDK before delete.
- 🔴 **Ch05-F130** — Purchase `expiresAt` set to start date → compute via safe-add or server.
- 🔴 **Ch06-C167** — Receipt sent as base64-in-JSON (OOM) → switch to multipart upload.
- 🔴 **Ch06-C180** — Backoff applied between distinct entries (queue stall) → apply only on retry of same entry.
- 🔴 **Ch07-P020** — No TLS pinning hook → inject `IOClient` with pinned `SecurityContext`.

#### File upload / receipt / log redaction (5)
- 🔴 **Ch06-C167** (above)
- 🔴 **Ch07-P021** — Logging callback can leak tokens → add `_redact` for JWT regex.
- 🔴 **Ch11-I047** — `FREE_TIER_ITEM_LIMIT` `NaN` disables free-plan gate → `Number.isFinite` guard.
- 🔴 **Ch11-I073** — SVG accepted; stored XSS vector → explicit deny / sanitize / `Content-Disposition`.
- 🔴 **Ch04-F002** — `amount_saved = repair - out_of_pocket` invariant unenforced → DB CHECK + service cross-check.

#### Health-score / dashboard cost (1)
- 🔴 **Ch04-F048** — Health score recomputed on every dashboard hit → cache; invalidate on writes.

#### Schema-default sabotage (1)
- 🔴 **Ch04-F012** — Warranty cancel never refunds Stripe payment → calculate prorated refund and call `refunds.create`.
- 🔴 **Ch08-WebhookEvent-D076** — `webhook_events.status DEFAULT 'processed'` defeats migration 027 retry → `ALTER COLUMN SET DEFAULT 'pending'`.

#### Tests that codify bugs (9)
- 🔴 **Ch12-R001** — EXPIRATION test asserts `plan='free'` even with active gift.
- 🔴 **Ch12-R002** — Unsuspend defaults to free; locks in plan loss.
- 🔴 **Ch12-R003** — Recover-account drops plan to free unconditionally.
- 🔴 **Ch12-R004** — `if(200) ... else 400` always passes.
- 🔴 **Ch12-R014** — `getAuthToken` signs with mismatched email.
- 🔴 **Ch12-R015** — `charge.refunded` cancels paid commissions unconditionally.
- 🔴 **Ch12-R020** — Rate limiters globally mocked everywhere.
- 🔴 **Ch12-T002** — RC INITIAL_PURCHASE with non-UUID `app_user_id` untested.
- 🔴 **Ch12-T004** — Refund overwrites paid commission to cancelled.
- 🔴 **Ch12-T005** — Concurrent `createGift` on same `payment_intent` untested.
- 🔴 **Ch12-T006** — Concurrent `activateGift` race untested.
- 🔴 **Ch12-T013** — Rate limiter never exercised.
- 🔴 **Ch12-T030** / **T031** (above).
- 🔴 **Ch12-T049** — Tests will TRUNCATE prod if `DATABASE_URL` misconfigured → guard on `DB_NAME` contains "test".

#### Payload drift critical (3)
- 🔴 **Ch08-PartnerGift-D062** — PartnerGift has NO Dart model at all.
- 🔴 **Ch08-PartnerCommission-D065** — PartnerCommission has NO Dart model.
- 🔴 **Ch08-WebhookEvent-D076** (above).

#### Idempotency / dashboard duplicate-charges (1)
- 🔴 **Ch09-FlowC-T-C20** — 401-refresh retry creates duplicate gifts/charges → client `Idempotency-Key` header used by Stripe + DB dedupe.

### Likely-stale (verify first)
None of Phase 1's items map to recent commits. All 84 should be assumed real until file-level verification.

---

# Phase 2 — DB schema + migration foundation

**Goal.** Make the database the single source of truth — no `schema.sql` drift, idempotent migrations, transactional DDL, search-path hardening, integer-cents money columns, sane CASCADE rules, RLS policies present (or marketing claim corrected). Pool config locked in: SSL CA, idle-tx timeout, slow-query warns, NaN-guarded env reads, server-listens-after-DB-ready.

**Files touched.**
- `apps/api/src/db/schema.sql`
- `apps/api/src/db/migrations/*.sql` (001–027 + new files for fixes)
- `apps/api/src/db/migrations/run-migration.ts`
- `apps/api/src/db/index.ts`
- `apps/api/src/config/index.ts`, `config/validator.ts`

**Depends on.** Phase 1 (CASCADE fixes from DB031–DB034 land here as part of the broader sweep — Phase 1 just shipped the stop-gap migration).

**Success criteria.**
- Fresh DB bootstrap from migrations only (no schema.sql) produces identical state to existing prod schema.
- Re-running every migration is idempotent.
- `pg_trgm` / `search_path` / `SECURITY INVOKER` set on all functions.
- Integer-cents columns added where money was DECIMAL.
- New `schema_version` table or equivalent gates partial-bootstrap detection.
- `tsc --noEmit` + `npm test` clean for `apps/api`.

### Findings (67 total)

#### Migration runner & schema bootstrap
- **Ch00-DB001** — schema.sql missing `documents.updated_at` trigger.
- **Ch00-DB002** — `ALTER TYPE ADD VALUE` inside same txn as use.
- **Ch00-DB003** — `ensureBaseSchema` races partial DB state.
- **Ch00-DB004** — `CREATE INDEX` lacks `IF NOT EXISTS` (013, 019, 004).
- **Ch00-DB005** — `004_audit_system.sql` non-idempotent (CREATE TABLE/TYPE).
- **Ch00-DB025** — runner `BEGIN` blocks `CONCURRENTLY`.
- **Ch00-DB026** — `027_webhook_events_status.sql` `DROP+ADD CHECK` takes AccessExclusiveLock.
- **Ch00-DB054** — no `ANALYZE` after seeds.

#### Function safety / search_path
- **Ch00-DB006** — plpgsql functions have NO `SET search_path`.
- **Ch00-DB007** — `calculate_health_score()` uses FLOAT for integer counts.
- **Ch00-DB008** — health-score UPDATE no-op when row missing.
- **Ch00-DB009** — `health_score_history` JSONB grows unbounded.
- **Ch00-DB010** — `get_dashboard_stats()` sums nullable cost without default.

#### Enums / dead values / case
- **Ch00-DB011** — `partner_commissions.type` has dead enum values.
- **Ch00-DB012** — `warranty_purchase_status` dead `pending`.
- **Ch00-DB013** — `gift_status` dead `payment_failed`.

#### CHECK constraints
- **Ch00-DB014** — `chk_partner_gifts_stripe_charge_required` omits `'sent'`.
- **Ch00-DB015** — `chk_partner_gifts_activation_consistency` doesn't guard `expired+activated`.
- **Ch00-DB016** — `chk_partner_gifts_homebuyer_email_format` is `LIKE '%@%.%'`.
- **Ch00-DB017** — App writes `'completed'` default for warranty claims.
- **Ch00-DB018** — `partner_commissions.commission_rate` DEFAULT `0.15` freezes rate.
- **Ch00-DB019** — `users.referral_code` UNIQUE added without dedup check.
- **Ch00-DB020** — `partner_gifts.activation_code` UNIQUE backfill 32-bit entropy.
- **Ch00-DB044** — `partners.is_active` default change not backfilled.
- **Ch00-DB045** — `partners.stripe_onboarded` default note.
- **Ch00-DB046** — `partners.subscription_tier` nullable (causes 500).
- **Ch00-DB047** — `first_reminder_days` lacks CHECK.
- **Ch00-DB048** — `reminder_time VARCHAR(5)` accepts garbage.
- **Ch00-DB049** — `brand_color` lacks hex CHECK.

#### Indexes
- **Ch00-DB021** — `idx_audit_logs_user_created` duplicated in 004 & 005.
- **Ch00-DB022** — duplicated items index (003 file).
- **Ch00-DB023** — prefix-redundant items indexes.
- **Ch00-DB024** — `CREATE INDEX` never `CONCURRENTLY`.
- **Ch00-DB035** — missing index on `users.referred_by` pre-011 (informational).
- **Ch00-DB041** — legacy `SERIAL` on tips/webhook_events.
- **Ch00-DB042** — `tips.is_active` nullable index misses NULL.
- **Ch00-DB043** — `is_required_for_warranty` nullable.

#### CASCADE / soft-delete / state overload (Phase 1 also touches DB031-034)
- **Ch00-DB029** — `audit_logs.user_id` ON DELETE SET NULL loses traceability.
- **Ch00-DB030** — `notification_history` CASCADE destroys history.
- **Ch00-DB031** 🔴 — `warranty_purchases` CASCADE.
- **Ch00-DB032** 🔴 — `warranty_claims` CASCADE.
- **Ch00-DB033** 🔴 — `partner_commissions` CASCADE.
- **Ch00-DB034** 🔴 — `partner_gifts` CASCADE.
- **Ch00-DB036** — `maintenance_history` lacks `updated_at`.
- **Ch00-DB037** — `email_scans` lacks `updated_at`.
- **Ch00-DB038** — `documents` lacks `deleted_at` + CASCADEs.
- **Ch00-DB039** — `plan='suspended'` overloaded ban vs deletion.
- **Ch00-DB040** — `plan_expires_at NULL` ambiguous.

#### Webhook events table
- **Ch00-DB027** — `webhook_events.status DEFAULT 'processed'` corrupts idempotency.
- **Ch00-DB028** — `webhook_events` retention job missing.

#### Newsletter / contact
- **Ch00-DB051** — UNIQUE on email blocks re-subscribe.
- **Ch00-DB052** — `(ip,created_at)` composite missing for rate-limiting.
- **Ch00-DB053** — `audit_logs` cleanup not partitioned.

#### RLS / security (claim vs reality)
- **Ch00-DB050** — zero `CREATE POLICY` despite RLS marketing claim.

#### DB pool & config (from Ch11)
- **Ch11-I036** — `rejectUnauthorized:true` with no CA file.
- **Ch11-I037** — No `idle_in_transaction_session_timeout`.
- **Ch11-I038** — Error path logs full SQL text.
- **Ch11-I039** — No slow-query warn.
- **Ch11-I040** — `getClient` leaks if caller forgets release.
- **Ch11-I041** — Pool error only logs; readiness unaffected.
- **Ch11-I042** — Empty DB password silently accepted.
- **Ch11-I047** 🔴 — `FREE_TIER_ITEM_LIMIT NaN` (also Phase 1).
- **Ch11-I048** — All `parseInt` no NaN guard.
- **Ch11-I050** — Validator imports config it validates.
- **Ch11-I051** — Requires both `DATABASE_URL` and discrete vars.
- **Ch11-I052** — URL envs not validated as URLs.
- **Ch11-I053** — Substring check for "dev" in DB password.
- **Ch11-I054** — Stripe/RC/SendGrid keys not strength-checked.
- **Ch11-I088** — `listen()` before DB readiness probe.

### Likely-stale
None.

---

# Phase 3 — API infra: middleware / headers / logger / redis / utils

**Goal.** Harden the API process boundary: Helmet/CORS/CSRF posture, body-parser ordering, rate-limit ordering, request-logger redaction, error envelope consistency, AsyncLocalStorage trace IDs, Redis client hygiene, file validation default-deny, date-utility UTC math, type-augmentation cleanup, graceful shutdown.

**Files touched.**
- `apps/api/src/app.ts`
- `apps/api/src/middleware/*` (csrf, errorHandler, requestLogger, validate, rateLimiter)
- `apps/api/src/utils/*` (logger, redis, token-blacklist, async-handler, errors, response, file-validation, dates, referral-code)
- `apps/api/src/types/express.d.ts`
- `apps/api/src/config/minio.ts`
- `apps/api/src/index.ts`

**Depends on.** Phase 2 (config validator + pool work lands first).

**Success criteria.**
- Pino redact list covers all sensitive keys (tokens, cookies, base64 image, OAuth access_tokens).
- CSRF middleware is the source of truth — no Bearer-bypass loopholes.
- Helmet COEP/CORP set explicitly; CSP ships (report-uri to the API audit endpoint).
- File validation default-denies unknown MIMEs; SVG explicitly rejected.
- Date utils use UTC accessors; property-based tests for month math.
- `tsc --noEmit` + `npm test` clean.

### Findings (85 total)

#### Helmet / CORS / app.ts middleware order
- **Ch11-I001** — Helmet COEP/CORP not explicit.
- **Ch11-I002** 🔴 — Stripe raw body mount path-scoped/fragile (also Phase 1).
- **Ch11-I003** — `express.json` no depth/strict guard.
- **Ch11-I004** — `compression()` pre-bodyparse enables BREACH.
- **Ch11-I005** — `trust proxy=1` spoofable through 2-hop Caddy.
- **Ch11-I006** — CORS origin array silently allows w/o ACAO.
- **Ch11-I007** — `allowedHeaders` missing `x-request-id`.
- **Ch11-I008** — Rate limiter installed after body parsing.
- **Ch11-I098** — Raw body applies to all methods.
- **Ch11-I099** — `config.rateLimit` possibly unused.

#### CSRF
- **Ch11-I009** — CSRF skipped for any `Authorization: Bearer` prefix.
- **Ch11-I029** — `SameSite=Strict` breaks OAuth round-trip.
- **Ch11-I030** — Token compared with `!==` (not constant time).
- **Ch11-I031** — Validator skips when cookie absent.
- **Ch11-I032** — Webhook bypass relies on mount order.

#### Response envelope / error handler
- **Ch11-I010** — Inconsistent success/error envelopes.
- **Ch11-I011** — `sendSuccess` accepts `any`.
- **Ch11-I012** — `message` at body root collides with `data.message`.
- **Ch11-I013** — `sendMessage` shape inconsistent.
- **Ch11-I014** — `async-handler` double-logs every rejection.
- **Ch11-I015** — Sync throws in non-async fn escape.
- **Ch11-I016** — `test` env leaks stack; AppError 4xx logged as error.
- **Ch11-I017** — No `requestId` in log/response.
- **Ch11-I018** — Joi `details` never sent.
- **Ch11-I019** — PG codes 23502/22001/22P02 fall through to 500.
- **Ch11-I025** — `ValidationError.details` never surfaced.
- **Ch11-I026** — `AppError` lacks `cause`/`originalError`.
- **Ch11-I027** — `code` optional and not enumerated.
- **Ch11-I028** — `message` used both for log and user response.

#### Validate middleware
- **Ch11-I023** — `stripUnknown` silently drops fields.
- **Ch11-I024** — One target per middleware; params often unchecked.

#### Request logger
- **Ch11-I020** — `userId` not attached on finish.
- **Ch11-I021** — UA not truncated; cardinality blow-up.
- **Ch11-I022** — `/health` spams logs.

#### MinIO config
- **Ch11-I033** — `getPublicUrl` emits internal hostname (also AUDIT C11).
- **Ch11-I034** — 32-bit unpredictability in object key.
- **Ch11-I035** — Sanitization preserves `..`.

#### Logger / pino
- **Ch11-I043** — Staging not in JWT secret env checks.
- **Ch11-I045** — Google/Apple `clientId` silently empty.
- **Ch11-I046** — CORS origins not normalized (slash/space).
- **Ch11-I049** — JWT secret re-read each access.
- **Ch11-I055** — `process.exit(1)` without log flush.
- **Ch11-I056** 🔴 — Pino has no redact paths (also Phase 1).
- **Ch11-I057** — `pid`/`hostname` on every prod line.
- **Ch11-I058** — No `pino.final` on `uncaughtException`.
- **Ch11-I059** — No `traceId`/AsyncLocalStorage threading.

#### Redis
- **Ch11-I060** — Two redis clients per process.
- **Ch11-I061** — TOCTOU on first connect; leaked client.
- **Ch11-I062** — Duplicated `isReady` state.
- **Ch11-I063** — No ping after reconnect.
- **Ch11-I064** — No cluster awareness.
- **Ch11-I065** — `close()` doesn't `removeAllListeners`.

#### Token blacklist / breaker
- **Ch11-I066** — Full JWT stored as Redis key.
- **Ch11-I067** — 10s auth cache window post-revoke.
- **Ch11-I068** — Per-worker breaker state inconsistent.
- **Ch11-I069** — Breaker amplifies redis blip to 70s outage.
- **Ch11-I070** — Breaker counts auth/network errors equally.

#### File validation (also touches Phase 6)
- **Ch11-I071** — Unknown MIME default-allow.
- **Ch11-I072** — Polyglot files pass header check.
- **Ch11-I073** 🔴 — SVG accepted; stored XSS (also Phase 1).
- **Ch11-I074** — No zip-bomb / pdf-bomb guard.
- **Ch11-I075** — `Buffer.slice` deprecation.

#### Referral code utility
- **Ch11-I076** — 32-bit referral codes.
- **Ch11-I077** — TOCTOU between SELECT and INSERT.
- **Ch11-I078** — No profanity blacklist.
- **Ch11-I079** — Case-sensitive lookup.

#### Date utils
- **Ch11-I080** — Local-TZ `getMonth`/`setMonth` corrupts warranties.
- **Ch11-I081** — Fractional months silently truncated.
- **Ch11-I082** — Negative months untested.
- **Ch11-I083** — Feb-29 → non-leap edge.

#### Type augmentation
- **Ch11-I084** — Augmentation not module-scoped.
- **Ch11-I085** — Booleans `isAdmin`/`isPartner` allow conflicting roles.
- **Ch11-I086** — `suspended` in plan union but never reaches handlers.
- **Ch11-I087** — `planExpiresAt` typed string but `Date` at runtime.

#### index.ts boot / cron / shutdown
- **Ch11-I089** — Rate limiter falls back to memory silently if Redis down.
- **Ch11-I090** — Scheduler 9am uses local TZ.
- **Ch11-I091** — Long `setTimeout` unreliable across suspend.
- **Ch11-I092** — One hung job blocks others.
- **Ch11-I093** — `getDay()` local TZ.
- **Ch11-I094** — 30s forced-exit timer not unref'd.
- **Ch11-I095** — `uncaughtException` can recurse into shutdown.
- **Ch11-I096** — `unhandledRejection` logs but doesn't exit.
- **Ch11-I097** — No external error tracker.
- **Ch11-I100** — Early SIGTERM dereferences undefined server.

### Likely-stale
None.

---

# Phase 4 — Auth surface (users / admin / OAuth / CSRF / sessions)

**Goal.** Tighten the auth path end-to-end: validators, register/login/refresh/logout state machine, session/device binding, change-email/forgot-password timing safety, OAuth (Google/Apple) audience handling, admin write hardening, suspend/unsuspend plan retention, RC entitlement reconciliation.

**Files touched.**
- `apps/api/src/routes/auth.ts`, `users.ts`, `admin.ts`
- `apps/api/src/middleware/auth.ts`, `csrf.ts`, `rateLimiter.ts`
- `apps/api/src/utils/token-blacklist.ts`
- `apps/api/src/validators/index.ts`, `users.validator.ts`

**Depends on.** Phases 2 + 3.

**Success criteria.**
- Refresh-token family invalidation enforced on rotation; mass-logout no longer possible by stale userId.
- Admin suspend/unsuspend preserves plan via `plan_before_suspend` column.
- Change-email and forgot-password are constant-time on user-existence.
- Apple Sign-In nonce validated; Google audience accepts platform-specific client IDs.
- `tsc --noEmit` + `npm test` clean. New tests cover OAuth audiences, refresh family, suspend plan retention, mass-assignment via PUT `/users/me`.

### Findings (88 total)

#### Validators
- **Ch01-F001** — Password regex unanchored.
- **Ch01-F002** — Email lacks trim/lowercase.
- **Ch01-F003** — Login password no upper bound.
- **Ch01-F024** — `email_verified` truthy check fragile (verify post-58a8bda).
- **Ch01-F064** — `paginationSchema` reused with unvalidated `partner_type`.
- **Ch01-F066** — Hand-rolled status validator drifts from enum.
- **Ch01-F067** — Hand-rolled UUID regex.
- **Ch01-F071** — `deleteAccountSchema` empty body passes.
- **Ch01-F072** — `changePasswordSchema` lacks blocklist/email check.
- **Ch01-F073** — Avatar URL hostname uses `includes` substring.
- **Ch01-F079** — `refreshTokenSchema` no max length DoS.

#### Register / login / bcrypt
- **Ch01-F004** — Register timing reveals email existence.
- **Ch01-F005** — Bcrypt 72-byte truncation undefended.
- **Ch01-F006** — Refresh tokens have no session/device binding.
- **Ch01-F007** — `capRefreshTokens` runs after insert.
- **Ch01-F008** — `hashtext` 32-bit lock collisions.
- **Ch01-F009** — Token VARCHAR oversized lacks length CHECK.

#### Verify-email / change-email
- **Ch01-F010** — Change-email inlines own sha256.
- **Ch01-F011** 🔴 — Verify-email accepts change-email tokens (also Phase 1).
- **Ch01-F012** — Verify-email UPDATE/DELETE outside txn.
- **Ch01-F013** — Logout doesn't invalidate `email_verification_tokens`.

#### Logout
- **Ch01-F014** — `/auth/logout` accepts unauthenticated.
- **Ch01-F015** — Logout blacklists tokens without verifying signature.
- **Ch01-F048** — Logout doesn't clear user Redis cache.

#### Forgot-password / reset
- **Ch01-F016** — Forgot-password timing leaks account existence.
- **Ch01-F017** — Forgot-password skips `email_verified` check.
- **Ch01-F018** — Reset-password blacklist of caller token is dead code.
- **Ch01-F019** — Reset token hashed unkeyed.

#### Refresh
- **Ch01-F020** 🔴 — Refresh trusts `decoded.userId` (also Phase 1).
- **Ch01-F021** — Refresh ignores soft-delete and suspended.
- **Ch01-F047** — Refresh auto-grants admin to stale tokens.

#### OAuth (verify against commit 58a8bda first)
- **Ch01-F022** — Google audience single-string risks.
- **Ch01-F023** — Google merges into email account silently.
- **Ch01-F025** — Apple lacks nonce validation.
- **Ch01-F026** — `apple_user_id` only set when NULL.
- **Ch01-F027** — Apple error message enumerates users.
- **Ch01-F028** — Apple users get password via forgot-password.

#### Users routes
- **Ch01-F029** — Change-email error reveals OAuth account.
- **Ch01-F030** — Change-email race creates two tokens.
- **Ch01-F031** — Change-email awaits SMTP blocking.
- **Ch01-F032** — Verify-premium downgrades on RC error silently.
- **Ch01-F033** — Verify-premium overwrites richer gift expiry.
- **Ch01-F034** — Premium downgrade leaves gift state stale.
- **Ch01-F035** — Bearer auth bypasses CSRF entirely.
- **Ch01-F076** — Change-email enumerates emails 30/15min.
- **Ch01-F077** — Email-existence check racy with register.
- **Ch01-F080** — Password change doesn't revoke external sessions.

#### CSRF (paired with Phase 3 work)
- **Ch01-F036** — CSRF skipped when no cookie set.
- **Ch01-F037** — CSRF cookie `httpOnly:false`.
- **Ch01-F038** — `sameSite:strict` breaks OAuth callback CSRF.

#### Auth middleware
- **Ch01-F039** — `adminCache` duplicates Redis user-cache.
- **Ch01-F040** — `authenticate` ignores `deleted_at`.
- **Ch01-F041** — Partner role activation has 10s lag.
- **Ch01-F042** — JWT `email` claim drifts from DB.
- **Ch01-F043** — Redis fail floods logs and DB.
- **Ch01-F044** — Raw token used as Redis key memory bomb.
- **Ch01-F045** — Clock skew TTL≤0 skip blacklisting (informational).
- **Ch01-F046** — Redis flap → mass logout cascade.
- **Ch01-F051** — Blacklist no upper bound DoS Redis.
- **Ch01-F078** — JWT bakes `isAdmin/isPartner` stale up to 10s.

#### Rate limiter
- **Ch01-F049** — Rate limiter keyed only on `req.ip`.
- **Ch01-F050** — Single auth limiter shared across 6 routes.

#### Admin routes
- **Ch01-F052** — Admin suspend records no reason.
- **Ch01-F053** — Admin suspend doesn't cancel RC entitlement.
- **Ch01-F054** — Suspend error leaks admin status.
- **Ch01-F055** — Admin write routes have no rate limiter.
- **Ch01-F056** — Unsuspend doesn't clear `deleted_at`.
- **Ch01-F057** — Unsuspend nukes premium plan (paired with Ch12-R002).
- **Ch01-F058** — Audit description includes raw email injection.
- **Ch01-F059** — Admin DELETE no reason or two-phase confirm.
- **Ch01-F060** — Partner approve double-audits on re-approve.
- **Ch01-F061** — Partner reject indistinguishable from pending.
- **Ch01-F062** — Partner approve no notification or cache invalidation.
- **Ch01-F063** — Admin list returns `stripe_account_id` to all admins.
- **Ch01-F065** — Partner listing shows ghost partners.
- **Ch01-F068** — Commissions stats has no caching.
- **Ch01-F069** — `DATE(created_at)` has no timezone.
- **Ch01-F070** — `user_stats` view lacks admin fields.
- **Ch01-F074** — `/admin/me` accessible to non-admins.
- **Ch01-F075** — Admin stats include soft-deleted users.

#### Test pairing (forced from Ch12)
- **Ch12-R002** 🔴 — Unsuspend defaults to free (also Phase 1).
- **Ch12-R003** 🔴 — Recover-account drops plan to free (also Phase 1).
- **Ch12-T016** — `/auth/apple` malformed/expired/wrong-aud untested.
- **Ch12-T017** — `/auth/google` expired/aud-mismatch/email_unverified untested.
- **Ch12-T018** — Password reset token replay untested.
- **Ch12-T019** — Refresh-token family invalidation not asserted.
- **Ch12-T022** — Admin unsuspend behavior untested (loses premium).
- **Ch12-T023** — Admin hard-delete cascade across 19 tables untested.
- **Ch12-T030** 🔴 — Forged `isAdmin` token grants untested (also Phase 1).
- **Ch12-T031** 🔴 — Mass assignment on PUT `/users/me` untested (also Phase 1).
- **Ch12-T046** — Email verification token replay untested.
- **Ch12-T054** — Email case-folding registration race untested.
- **Ch12-T055** — Email change re-verification untested.

### Likely-stale (verify against `git log` of `auth.ts` since `58a8bda`)
- **Ch01-F022, F023, F024, F025, F026, F027, F028** — Google + Apple Sign-in commit may already address these.

---

# Phase 5 — Payments / partners / webhooks / Stripe Connect

**Goal.** Land the money path correctly: webhook idempotency + ordering + age windows; partner gift state machine sealed (pending_payment → created → sent → activated|expired|payment_failed|reversed); commission lifecycle ties to Stripe transfers (no DB-flag-only "paid"); refund clawback ledger; Connect onboarding/destination charges chosen and consistent; activation code 64–80 bits + IP-scoped lockout + email 2FA; gift email durable retry.

**Files touched.**
- `apps/api/src/routes/webhooks.ts`, `partners.ts`
- `apps/api/src/services/partners.service.ts`, `reconciliation.service.ts`, `email.service.ts`
- `apps/api/src/validators/partners.validator.ts`
- New: gift state-machine helper, transfer idempotency wrapper, retention/cleanup cron for `webhook_events`.
- Tests: webhook idempotency, refund clawback, concurrent createGift / activateGift races.

**Depends on.** Phases 2 (CASCADE + webhook_events default + indexes) + 3 (raw-body, idempotency-key support) + 4 (auth on partner routes).

**Success criteria.**
- Stripe + RC webhook tests cover replay, age window, signature failure, sandbox/prod, `INITIAL_PURCHASE` non-UUID, EXPIRATION + active gift, refund clawback, TRANSFER, dispute.
- Activation code path passes brute-force, enumeration, race-on-activate, expired-after-pay.
- `paid_commissions` only counts rows with non-null `stripe_transfer_id`.
- `tsc --noEmit` + `npm test` clean. New `partners.test.ts` and `reconciliation.test.ts`.

### Findings (178 total)

#### Webhook auth / safety / ordering (Stripe + RC)
- **Ch03-F001** — RC webhook auth token-only, not body-bound.
- **Ch03-F002** 🔴 — RC ignores SANDBOX environment (also Phase 1).
- **Ch03-F007** — Non-UUID `app_user_id` crashes pg, poisons retry.
- **Ch03-F009** — RC event ordering not protected.
- **Ch03-F042** — Refund replay re-mutates already-expired gift.
- **Ch03-F044** — 5-min age window drops events with no record.
- **Ch03-F045** 🔴 — Body parsing order can break Stripe sig (also Phase 1).
- **Ch03-F046** — Poison-pill events loop forever.
- **Ch03-F047** — Re-claim ignores `last_error`/claim drift.
- **Ch03-F048** — Truncated errors persist secret patterns.

#### RC product/plan/entitlement
- **Ch03-F003** — Null expiry indistinguishable from free vs lifetime.
- **Ch03-F004** — Trial period not persisted.
- **Ch03-F005** — Any product grants premium; `entitlement_ids` unchecked.
- **Ch03-F006** — RC TRANSFER no-op; premium stranded.
- **Ch03-F008** — RC `SUBSCRIBER_ALIAS` doesn't bind alias.

#### Stripe webhook handlers
- **Ch03-F010** — Stripe webhook ignores `metadata.gift_id`.
- **Ch03-F011** 🔴 — `charge.refunded` doesn't clawback paid commissions (also Phase 1).
- **Ch03-F114** — No `account.updated/deauthorized` handler.
- **Ch03-F125** — No `payment_intent.canceled` or dispute handlers.
- **Ch03-F124** — `otherGifts` check ignores `expires_at`.

#### Commission state machine + payouts
- **Ch03-F012** 🔴 — Commission paid is DB flag (also Phase 1).
- **Ch03-F013** 🔴 — Pay endpoint TOCTOU enables double payout (also Phase 1).
- **Ch03-F054** 🔴 — `paid_commissions` sum lies (also Phase 1).
- **Ch03-F067** 🔴 — Connect model self-inconsistent (also Phase 1).
- **Ch03-F014** — Admin commission endpoints lack rate limit + audit.

#### Partner registration / lifecycle
- **Ch03-F015** — `partner_type` editable post-registration.
- **Ch03-F018** — `createGift` skips `is_active` partner check.
- **Ch03-F100** — `requirePartner` skips `is_active` check.
- **Ch03-F101** — Suspended/deleted users can self-register as partner.
- **Ch03-F102** — Brand churn triggers CDN cost.

#### Validators
- **Ch03-F016** — Unknown fields silently stripped.
- **Ch03-F017** — `homebuyerEmail` no max length.
- **Ch03-F053** — Date filter validation only at route.
- **Ch03-F106** — `companyName` empty-string handling.

#### Gift creation / Stripe charge
- **Ch03-F019** — Tier price/commission read twice without lock.
- **Ch03-F020** — `amount * 100` floating cents.
- **Ch03-F021** — Stripe idempotency key expires after 24h.
- **Ch03-F022** — Phase 2 catch lacks `pending_payment` guard.
- **Ch03-F023** — Phase 2 writes overloaded `'expired'` on failure.
- **Ch03-F024** — Failed gift permanently consumes activation code.
- **Ch03-F040** — `expires_at` hardcoded 6 months ignoring `premium_months`.
- **Ch03-F107** — No partner-side receipt email.
- **Ch03-F108** — `amount_charged` stored dollars not cents (representation).
- **Ch03-F121** — No reconciliation between `gift.amount` and Stripe charge.

#### Activation code / verify / lockout
- **Ch03-F025** — 8-hex code 32 bits brute-forceable.
- **Ch03-F026** — `verifyActivationCode` reveals UUIDs for activated/expired.
- **Ch03-F027** — Code lock enables remote DoS of legitimate gifts.
- **Ch03-F028** — Redis errors swallowed; brute-force unprotected.
- **Ch03-F029** — Tracking endpoints leak gift existence via status code.
- **Ch03-F030** — First-item tracking 404s on `activated_user` mismatch.
- **Ch03-F034** — Resend rate limit per-IP not per-gift.
- **Ch03-F036** — `homebuyer_email` immutable after gift create.
- **Ch03-F037** — Email comparison `.toLowerCase()` not full case-fold.
- **Ch03-F062** — Concurrent code creation hits unique 500.
- **Ch03-F088** — Stored `activation_url` not re-validated at send.
- **Ch03-F093** — Code uppercasing fragile against migration mix.
- **Ch03-F105** — No retry on activation_code unique collision.
- **Ch03-F112** — Tracking write-once not DB-enforced.

#### Activate gift
- **Ch03-F035** — `resendGiftEmail` allows invalid status transitions.
- **Ch03-F038** — `activateGift` skips `stripe_charge_id` verification.
- **Ch03-F039** — Activation un-bans suspended users.
- **Ch03-F041** — `interval` arithmetic TZ-sensitive.
- **Ch03-F094** — Race overwrites `activated_user_id` on duplicate emails.
- **Ch03-F095** — User email change blocks own activation.
- **Ch03-F096** — No audit trail when premium stacks.
- **Ch03-F097** — Unactivated gifts leave commission pending forever.
- **Ch03-F098** — `user_analytics` insert idempotent (verdict OK).

#### Email service (gift / partner welcome)
- **Ch03-F031** — `sanitizeUrl` returns empty for non-https staging.
- **Ch03-F032** — `brand_color + 'dd'` breaks Outlook 8-char hex.
- **Ch03-F033** — Email failures silently dropped.
- **Ch03-F082** — `escapeHtml` misses backticks/slashes.
- **Ch03-F083** — Tracking pixel URL lacks HMAC signing.
- **Ch03-F084** — Partner welcome lacks tracking pixel.
- **Ch03-F085** — `days_remaining` interpolated unescaped.
- **Ch03-F086** — `itemUrl` could deep-link arbitrarily if drift.
- **Ch03-F087** — Inconsistent SG error catching across callers.
- **Ch03-F089** — Partner-controlled `fromName` enables impersonation.
- **Ch03-F090** — Subject hardcoded "expires in 6 months".
- **Ch03-F091** — `logo_url` unsanitized in public preview.
- **Ch03-F092** — `homebuyer_name` leaks PII via gift UUID.

#### Reconciliation service
- **Ch03-F049** — `parseFloat→DECIMAL` roundtrip drifts.
- **Ch03-F050** — Reconciler 0's legitimate savings on item delete.
- **Ch03-F051** — Reconciler lacks transaction.
- **Ch03-F052** — Full-table scan thrashes DB at scale.

#### Stats / analytics
- **Ch03-F055** — `activation_rate` integer cast loses precision.
- **Ch03-F056** — Earnings month wraps across year boundary.
- **Ch03-F057** — Earnings sum excludes pending+cancelled ambiguously.
- **Ch03-F058** — Empty months missing from earnings array.
- **Ch03-F059** — Email mask leaks single-char local part.
- **Ch03-F060** — `full_name` unmasked alongside masked email.
- **Ch03-F061** — `item_count` leaks engagement signal.
- **Ch03-F103** — `getGift` exposes `stripe_charge_id`.
- **Ch03-F104** — Commission shows `homebuyer_name` post-erasure.
- **Ch03-F117** — Money math scattered without helper.
- **Ch03-F118** — `parseFloat` on DECIMAL in analytics.
- **Ch03-F119** — `parseFloat` on DECIMAL in earnings.
- **Ch03-F120** — Duplicate of F055 cast.
- **Ch03-F126** — `/partners/me` exposes `stripe_account_id`.

#### Stripe Connect
- **Ch03-F063** — `(partner as any).email` bypasses type safety.
- **Ch03-F064** — `stripe.accounts.create` lacks idempotency key.
- **Ch03-F065** — Onboarded partner gets onboarding link again.
- **Ch03-F066** — `GET /status` writes `stripe_onboarded` sticky flag.
- **Ch03-F113** — Sticky flag misses Stripe deactivation.

#### Webhook events table & migrations (paired with Phase 2)
- **Ch03-F068** — `webhook_events` lacks `event_created_at`.
- **Ch03-F069** — Activation consistency CHECK blocks future states.
- **Ch03-F070** — `stripe_charge` CHECK omits `'sent'`.
- **Ch03-F071** — Email LIKE check accepts garbage.
- **Ch03-F072** — Codes derived from UUID predictable.
- **Ch03-F073** — Dead `'subscription'` commission_type enum.
- **Ch03-F074** — `brand_color` regex `/i` flag load-bearing.
- **Ch03-F075** — `partner_commissions.amount` allows negative.
- **Ch03-F076** — Missing `(partner_id,created_at)` composite index.
- **Ch03-F077** — Missing `(partner_id,created_at)` on `partner_gifts`.
- **Ch03-F078** — Stripe webhook scans full table on `charge_id`.
- **Ch03-F079** — `expires_at` lacks `> created_at` constraint.
- **Ch03-F080** — Webhook status CHECK omits `dead_letter`.
- **Ch03-F081** — `SERIAL id` wastes space.
- **Ch03-F109** — `is_active` default flip not backfilled.
- **Ch03-F110** — Migration 022 duplicates 011's pending_payment add.
- **Ch03-F111** — `payment_failed` enum added but never written.
- **Ch03-F115** — `webhook_events` no retention cron.
- **Ch03-F116** — `commission_rate` DEFAULT contradicts tier rates.

#### Verdict-OK items kept for completeness
- **Ch03-F099** — Auth route ordering verified OK.
- **Ch03-F123** — `handleChargeFailed` cancel scope OK.

#### Webhook routes performance
- **Ch03-F122** — N+1 query loop across RC aliases.

#### Flow C (Ch09 — partner gift purchase)
- **Ch09-FlowC-T-C1** — Proxy forwards cookie + bearer (companion to Ch10-W001).
- **Ch09-FlowC-T-C2** 🔴 — 32-bit code online-feasible (also Phase 1).
- **Ch09-FlowC-T-C3** 🔴 — verify-code is enumeration oracle (also Phase 1).
- **Ch09-FlowC-T-C4** — Redis fail-open on lockout checks.
- **Ch09-FlowC-T-C5** 🔴 — Self-gift fraud via unverified email (also Phase 1).
- **Ch09-FlowC-T-C6** — `TIER_PRICING` float * 100 = non-integer cents.
- **Ch09-FlowC-T-C7** — `amount_charged` dollars vs cents ambiguity.
- **Ch09-FlowC-T-C8** — Gift email send fire-and-forget.
- **Ch09-FlowC-T-C9** 🔴 — Partner self-gift via secondary email (also Phase 1).
- **Ch09-FlowC-T-C10** 🔴 — Connect transfer never initiated (also Phase 1).
- **Ch09-FlowC-T-C11** — `TIER_PRICING` JSON.parse at module load crashes.
- **Ch09-FlowC-T-C12** — `max_gifts_per_month` not enforced.
- **Ch09-FlowC-T-C13** — `PARTNER_TIERS` hardcoded duplicates `TIER_PRICING`.
- **Ch09-FlowC-T-C14** — `expires_at` hardcoded in service AND template.
- **Ch09-FlowC-T-C15** — Activation code in plaintext email body.
- **Ch09-FlowC-T-C16** 🔴 — Code/url plaintext in DB+email+logs (also Phase 1).
- **Ch09-FlowC-T-C17** — Refund downgrade ignores RC entitlement state.
- **Ch09-FlowC-T-C18** — Webhook ignores `metadata.gift_id` fallback.
- **Ch09-FlowC-T-C19** — `user_analytics` ON CONFLICT brittle.
- **Ch09-FlowC-T-C20** 🔴 — 401-refresh retry creates duplicate charges (also Phase 1).
- **Ch09-FlowC-T-C21** — `FRONTEND_URL` silent localhost in prod.
- **Ch09-FlowC-T-C22** — Public preview reveals `is_activated/expires_at`.
- **Ch09-FlowC-T-C23** — Partner welcome email fire-and-forget.
- **Ch09-FlowC-T-C24** — `amount_charged` not reconciled vs `amount_received`.
- **Ch09-FlowC-T-C25** — Webhook UPDATE misses `pending_payment` race.
- **Ch09-FlowC-T-C26** — Proxy forwards `content-length`/`transfer-encoding`.
- **Ch09-FlowC-T-C27** — Partner `logo_url` remote-loaded.
- **Ch09-FlowC-T-C28** — No `List-Unsubscribe` / DKIM hygiene.
- **Ch09-FlowC-T-C29** — Admin commission routes lack audit + transactions.
- **Ch09-FlowC-T-C30** — `APP_BASE_URL` localhost default in email logo.

#### Test pairing (Phase 5 owns these tests)
- **Ch12-R001** 🔴 (also Phase 1).
- **Ch12-R004** 🔴 (also Phase 1).
- **Ch12-R007** — Tier shape only.
- **Ch12-R008** — Truncated `webhook_events` masks idempotency.
- **Ch12-R015** 🔴 (also Phase 1).
- **Ch12-R016** — Asserts `plan='free'` on register.
- **Ch12-T002** 🔴 (also Phase 1).
- **Ch12-T003** — `charge.refunded` idempotency untested.
- **Ch12-T004** 🔴 (also Phase 1).
- **Ch12-T005** 🔴 (also Phase 1).
- **Ch12-T006** 🔴 (also Phase 1).
- **Ch12-T024** — Webhook replay-window age check.
- **Ch12-T025** — RC `BILLING_ISSUE`/`PRODUCT_CHANGE`/`TRANSFER`/`SUBSCRIBER_ALIAS`/`UNCANCELLATION`.
- **Ch12-T026** — Gift activation email-mismatch lockout.
- **Ch12-T027** — Gift activation Redis lockout.
- **Ch12-T037** — Tier rate values (lock 0.10/0.15/0.20).
- **Ch12-T038** — Reconciliation cross-user drift.
- **Ch12-T041** — Future-timestamp signature.
- **Ch12-T042** — Refund of transferred gift.
- **Ch12-T051** — Stripe charge with no metadata.
- **Ch12-T052** — Concurrent webhook claim race.

### Likely-stale
None.

---

# Phase 6 — Uploads / documents / items CRUD / receipts / OCR

**Goal.** Lock down file ingestion: magic-byte default-deny, image-bomb protection, MinIO object-key entropy, owner-scoped object paths, atomic upload + DB write, dead-letter for orphan keys; receipts via multipart (no base64-in-JSON OOM), per-user OpenAI cost budget, receipt prompt-injection guard. CRUD: ownership checks, keyset pagination, CSV formula injection prevention, archive-mode flag, lifespan_percentage in list payload.

**Files touched.**
- `apps/api/src/routes/items.ts`, `homes.ts`, `documents.ts`, `uploads.ts`, `receipts.ts`
- `apps/api/src/utils/file-validation.ts` (already partly in Phase 3)
- `apps/api/src/config/minio.ts` (already in Phase 3)
- `packages/shared_models/lib/src/item.dart` (drift fixes overlap with Phase 8)

**Depends on.** Phases 2 (schema CASCADE/index) + 3 (file-validation default-deny + MinIO key entropy).

**Success criteria.**
- Receipt OCR multipart upload supported; per-user daily OpenAI budget enforced (cost-center matrix Ch09-CostMatrix).
- Document upload+thumbnail+audit are transactional with dead-letter on partial failure.
- Items CRUD ownership-checked and keyset-paginated.
- CSV exports formula-injection-safe (`=,+,-,@` prefixed) and respect `?archived=`.
- `tsc --noEmit` + `npm test` clean. New tests for cross-user upload denial, magic-byte mismatch, oversized + bad MIME, prompt-injection.

### Findings (91 total)

#### Items routes
- **Ch02-F001** — `warranty_end_date` doc lies about `GENERATED`.
- **Ch02-F002** — `stripUnknown` silently drops typos.
- **Ch02-F003** — `ALLOWED_UPDATE_FIELDS` missing real columns.
- **Ch02-F004** — `addedVia` enum diverges client/server/DB.
- **Ch02-F005** — List vs detail responses inconsistent.
- **Ch02-F006** — Items list `SELECT *` leaks internal columns.
- **Ch02-F008** — List runs separate count query.
- **Ch02-F009** — OFFSET pagination duplicates/skips on edits.
- **Ch02-F010** — Count vs create-limit disagree under stress.
- **Ch02-F011** — Extra SELECT outside txn for warranty recompute.
- **Ch02-F012** — PUT items `home_id` not ownership-verified.
- **Ch02-F017** — 22 positional params drift on column add.
- **Ch02-F018** — Duplicated `updated_at` assignment risks 42701.
- **Ch02-F019** — `addMonthsSafe` uses local-TZ `Date`.
- **Ch02-F020** — Lifespan ms-arithmetic 365.25.
- **Ch02-F049** — CSV LIMIT/OFFSET is O(N²).
- **Ch02-F050** — CSV export has no timeout.
- **Ch02-F051** — Audit fired before any row written.
- **Ch02-F052** — CSV `escapeCsv` lacks formula injection prefix.
- **Ch02-F053** — CSV export mixes archived items by default.
- **Ch02-F058** — `nextMaintenanceDue` not `>= purchaseDate`.
- **Ch02-F059** — Archive scheduler filter omission risk.
- **Ch02-F060** — `purchaseDate.max('now')` TZ-naive.
- **Ch02-F061** — Installation/maintenance dates not ordered.
- **Ch02-F062** — `updated_at` exposed at microsecond precision.
- **Ch02-F063** — `archived_at` asymmetric serialization.
- **Ch02-F064** — `lifespan_percentage` missing from list.
- **Ch02-F065** — Items list lacks per-route rate limit.
- **Ch02-F066** — CSV export has no dedicated rate limit.

#### Homes routes
- **Ch02-F007** — `Home.fromJson` falls back to `now()`.
- **Ch02-F014** — Home delete locks every user home.
- **Ch02-F015** — Items reassigned to nondeterministic home.
- **Ch02-F016** — Order leaks 1-home state via wrong error.
- **Ch02-F054** — `homes` GET `SELECT *` leaks fields.
- **Ch02-F055** — null vs empty string inconsistent persistence.
- **Ch02-F056** — Home rename has no client invalidation.
- **Ch02-F057** — Home delete leaves analytics stale.
- **Ch02-F013** — Concurrent upload orphans MinIO on item delete.

#### Uploads
- **Ch02-F030** — Item-images path missing user_id segment.
- **Ch02-F031** — Replacing item image leaves orphan.
- **Ch02-F032** — Avatar key predictable allowing overwrite.
- **Ch02-F033** — Avatar upload not atomic with user UPDATE.

#### File validation
- **Ch02-F021** — Magic-bytes returns true for unknown MIME.
- **Ch02-F022** — JPEG check misses 4th byte marker.
- **Ch02-F023** — PDF magic only checks 4 bytes.
- **Ch02-F024** — SVG handling absent.

#### Documents
- **Ch02-F025** — Sharp default pixel limit decompression bomb.
- **Ch02-F026** — Multer `memoryStorage` blocks event loop.
- **Ch02-F027** — `generateObjectKey` 32-bit entropy.
- **Ch02-F028** — Sanitization permits leading dots/dotfiles.
- **Ch02-F029** — Sanitization unicode-lossy no length cap.
- **Ch02-F034** — HEIC accepted but Sharp lacks HEIF.
- **Ch02-F035** — MinIO cleanup loop swallows errors.
- **Ch02-F036** — Audit log not transactional with upload.
- **Ch02-F037** — Thumbnail orphans on main put failure.
- **Ch02-F038** — DELETE swallows MinIO errors silent leak.
- **Ch02-F039** — Documents list has no LIMIT pagination.
- **Ch02-F040** — `file_url` stores hostname coupling DB to MinIO.
- **Ch02-F068** — Multer rejects before schema validation.
- **Ch02-F067** — `uploadDocumentSchema` relies on validate options.

#### Receipts / OCR
- **Ch02-F041** — 5MB check dead behind 1MB body parser.
- **Ch02-F042** — Base64 prefix-only regex incorrect.
- **Ch02-F043** — No schema validation on OpenAI response.
- **Ch02-F044** — Prompt-injection via receipt text.
- **Ch02-F045** — OpenAI fetch has no timeout.
- **Ch02-F046** — No per-user OpenAI cost attribution.
- **Ch02-F047** — Base64 image bypasses magic-byte validation.
- **Ch02-F048** — Rate limiter runs before `requirePremium`.

#### Flow A (Ch09 — receipt scanning)
- **Ch09-FlowA-T-A1** — `express.json(1mb)` pre-empts route's 5MB.
- **Ch09-FlowA-T-A2** — OpenAI fetch has no timeout/AbortController.
- **Ch09-FlowA-T-A3** 🔴 — `logger.warn` ships full OpenAI response with PII (also Phase 1).
- **Ch09-FlowA-T-A4** — Receipt-scan rate limit per-IP only.
- **Ch09-FlowA-T-A5** — Endpoint limiters fall back to per-process memory.
- **Ch09-FlowA-T-A6** — Base64 regex validates only first 100 chars.
- **Ch09-FlowA-T-A7** — `ItemCategory.fromJson` silently coerces unknown.
- **Ch09-FlowA-T-A8** — Item name defaults to category label.
- **Ch09-FlowA-T-A9** 🔴 — OpenAI total unbounded reaches DB (also Phase 1).
- **Ch09-FlowA-T-A10** — No idempotency, double-tap = double bill.
- **Ch09-FlowA-T-A11** — Warranty/serial/model fields dropped.
- **Ch09-FlowA-T-A12** — `requirePremium` 24h grace burns OpenAI.
- **Ch09-FlowA-T-A13** — `data:image/jpeg` asserted regardless of MIME.
- **Ch09-FlowA-T-A14** 🔴 — Base64 body to logs unredacted (also Phase 1).

#### Test pairing
- **Ch12-T010** — Magic-byte mismatch never exercised.
- **Ch12-T011** — Oversized + bad-MIME upload untested.
- **Ch12-T012** — Receipt prompt-injection untested.
- **Ch12-T014** — CSV export cross-user permissions untested.
- **Ch12-T029** — CSV injection prefix untested.
- **Ch12-T039** — Future purchase date untested.
- **Ch12-T043** — SQL injection on sort/order params untested.
- **Ch12-T044** — Pagination negative/huge values untested.
- **Ch12-T053** — Cross-user upload to A's `itemId` untested.
- **Ch12-T056** — Negative price untested.
- **Ch12-R011** — MinIO mock always succeeds.

### Likely-stale
None.

---

# Phase 7 — Warranty / maintenance / notifications / stats / scanner / audit / barcode / newsletter / contact / health

**Goal.** Sweep the remaining service routes and their schedulers: warranty claims state machine + savings-feed XSS, warranty purchases refund/cancel + idempotency, maintenance dedup + cost math, notifications quiet-hours/digest/cascade + delivery channel, stats caching/health-score recompute, Gmail scanner OAuth + retry budget + duplicate counting, audit-log immutability + hash chain, barcode privacy + per-user quotas, newsletter double-opt-in, contact CAPTCHA, health-check actually checks.

**Files touched.**
- `apps/api/src/routes/warranty-claims.ts` + service + validator
- `apps/api/src/routes/warranty-purchases.ts` + service + validator
- `apps/api/src/routes/maintenance.ts` + service + validator
- `apps/api/src/routes/notifications.ts` + service + validator
- `apps/api/src/routes/stats.ts` + service
- `apps/api/src/routes/email-scanner.ts` + service
- `apps/api/src/services/fcm.service.ts`, `email.service.ts`, `audit.service.ts`
- `apps/api/src/routes/categories.ts`, `health.ts`, `barcode.ts`, `newsletter.ts`, `contact.ts`, `audit.ts`
- Migrations carry over to Phase 2 if any new DDL emerges.

**Depends on.** Phases 2 + 3 + 4.

**Success criteria.**
- Warranty claim state machine enforced; savings-feed sanitized; OOC math correct.
- Warranty purchase cancel issues prorated Stripe refund + decrements partner commission.
- Maintenance dedup index added; cost roll-up correct.
- Notifications respect quiet-hours/digest server-side; FCM multicast + channelId set.
- Email scanner: server-side OAuth code flow; per-user OpenAI budget; per-scan failure budget; Gmail quota check.
- Audit log immutable; hash chain; X-Forwarded-For only when proxy whitelisted.
- Barcode per-user quota; newsletter double-opt-in; contact CAPTCHA; `/health` checks DB.
- Tests cover state-machine transitions, OAuth path, prompt-injection, FCM error paths, idempotent re-scans.

### Findings (158 total)

#### Warranty claims
- **Ch04-F001** — No state machine; status free-form VARCHAR.
- **Ch04-F002** 🔴 — `amount_saved=repair-out_of_pocket` invariant unenforced (also Phase 1).
- **Ch04-F003** 🔴 — Stored XSS via city in savings_feed (also Phase 1).
- **Ch04-F004** — `parseFloat` on DECIMAL across multiple sites.
- **Ch04-F005** — Count/rows race in pagination.
- **Ch04-F006** — `savings_feed` retains deleted users' PII.
- **Ch04-F007** — `deleteClaim` uses READ-COMMITTED.
- **Ch04-F008** — Negative limit values 500 the request.
- **Ch04-F009** — No rate limit on read endpoints.
- **Ch04-F010** — No actor/timestamp tracked for status transitions.
- **Ch04-F011** — Null `outOfPocket` produces NaN in update.

#### Warranty purchases
- **Ch04-F012** 🔴 — Cancel never refunds Stripe payment (also Phase 1).
- **Ch04-F013** — Expire path emits no notification.
- **Ch04-F014** — Quote math NaN's on null `item.price`.
- **Ch04-F015** — Quote math uses `float * 100 + round`.
- **Ch04-F016** — Duplicate check ignores `'pending'`.
- **Ch04-F017** — `startsAt` accepts dates 73 years in future.
- **Ch04-F018** — Duration validation duplicated service+validator.
- **Ch04-F019** — Client-supplied `commissionRate` trusted.
- **Ch04-F020** — No idempotency on `stripe_payment_intent_id`.
- **Ch04-F021** — `getExpiringWarranties` scans without composite index.
- **Ch04-F022** — Cancel doesn't decrement partner commission.

#### Maintenance
- **Ch04-F023** — Schedules not user-customizable.
- **Ch04-F024** — Duplicate maintenance logs gameable.
- **Ch04-F025** — UPDATE missing `user_id` (already audited as H25).
- **Ch04-F026** — Summary doesn't distinguish caught-up vs no-schedule.
- **Ch04-F027** — `addMonthsSafe` uses local TZ semantics.
- **Ch04-F028** — Falls back to `created_at` instead of `installation_date`.
- **Ch04-F029** — Per-log SUM lets duplicates inflate `prevents_cost`.
- **Ch04-F030** — Two UPDATEs; null `prevents_cost` silently dropped.
- **Ch04-F031** — `GREATEST(0,...)` hides reconciliation drift.
- **Ch04-F032** — Cost max $1M is implausible.

#### Notifications
- **Ch04-F033** — Server-side quiet-hours/digest/cascade absent.
- **Ch04-F034** — No digest batching.
- **Ch04-F035** — `recordAction` has no allowlist.
- **Ch04-F036** — All cron jobs share one `setTimeout` chain.
- **Ch04-F037** — DST drift produces duplicate annual notifications.
- **Ch04-F038** — FCM-failed rows still surface to user.
- **Ch04-F039** — Template re-injection via single-pass loop.
- **Ch04-F040** — `createNotification` bypasses preferences.
- **Ch04-F041** — ON DELETE CASCADE wipes notification trail.
- **Ch04-F042** — `markAsRead` does 3 round-trips.
- **Ch04-F043** — `first_reminder_days` accepts up to 365.
- **Ch04-F044** — `/tip` runs 5+ queries with no cache.
- **Ch04-F045** — Day-of-year uses local time.
- **Ch04-F046** — `scheduled_at` aliased to `sent_at`.
- **Ch04-F047** — `warranty_offers` default TRUE = implicit opt-in.

#### Stats
- **Ch04-F048** 🔴 — Health score recomputed on every dashboard hit (also Phase 1).
- **Ch04-F049** — `health_score_history` JSONB grows unbounded.
- **Ch04-F050** — `GET /stats/health-score` is write-on-read.
- **Ch04-F051** — Dashboard stats include archived items.
- **Ch04-F052** — Session race produces negative duration.
- **Ch04-F053** — No per-user cap on engagement tracking.
- **Ch04-F054** — `feature` string allows arbitrary value.
- **Ch04-F055** — `getItemsNeedingAttention` pagination unbounded.
- **Ch04-F056** — date subtraction depends on pg version.
- **Ch04-F057** — Upsert-on-read churns WAL.
- **Ch04-F058** — Raw JSONB blob returned without versioning.

#### Email scanner
- **Ch04-F059** 🔴 — Gmail OAuth token from client (also Phase 1).
- **Ch04-F060** — Granted scopes never verified.
- **Ch04-F061** — Background scan stuck on container restart.
- **Ch04-F062** — PII masking incomplete.
- **Ch04-F063** — OpenAI calls lack retry/cost cap.
- **Ch04-F064** — OpenAI axios no timeout.
- **Ch04-F065** — `email_scans_completed` counts no-op scans.
- **Ch04-F066** — `warranty_months` hardcoded to 12.
- **Ch04-F067** — Same email matches multiple queries; double-billed.
- **Ch04-F068** — Category allowlist diverges from validator.
- **Ch04-F069** — TOCTOU between FOR UPDATE and count.
- **Ch04-F070** — `error_message` reused for warnings.
- **Ch04-F071** — Outlook axios no timeout.

#### FCM
- **Ch04-F072** — No multicast batching.
- **Ch04-F073** — Badge hardcoded to 1.
- **Ch04-F074** — Android missing `channelId`/priority.
- **Ch04-F075** — No silent/data-only push variant.
- **Ch04-F076** — Cleanup misses sender-id-mismatch/quota.
- **Ch04-F077** — Lazy init causes cold-start latency.
- **Ch04-F078** — Empty token list returns 0 silently.
- **Ch04-F079** — Tokens have no `last_seen_at`.
- **Ch04-F080** — No topic-based broadcasts.

#### Email service (transactional / unsubscribe)
- **Ch04-F081** — SendGrid no retry/circuit breaker.
- **Ch04-F082** — Gift email lacks unsubscribe + postal address.
- **Ch04-F083** — One-Click unsubscribe target is app deep link.
- **Ch04-F084** — `sanitizeColor` rejects 3-digit shorthand.
- **Ch04-F085** — `sanitizeUrl` allows `http://localhost` in prod email.
- **Ch04-F086** — `replyTo` set to user-controlled email (CR/LF).
- **Ch04-F087** — `brand_color+'dd'` breaks on 3-digit hex.

#### Audit
- **Ch04-F088** 🔴 — Audit log mutable (also Phase 1).
- **Ch04-F089** — `/audit/logs` GET no rate limit.
- **Ch04-F090** 🔴 — `/audit/cleanup` no MFA recheck (also Phase 1).
- **Ch04-F091** — `getIpAddress` trusts XFF unverified.
- **Ch04-F092** — Deep OFFSET scans lock table.
- **Ch04-F093** — Retry swallows non-transient FK errors.
- **Ch04-F094** — `metadata` JSONB unbounded size.
- **Ch04-F095** — No hash chain; rows tamperable by DBA.

#### Categories
- **Ch04-F096** — `:category` param unvalidated.
- **Ch04-F097** — No cache on rarely-changing categories.
- **Ch04-F098** — No admin write route for `category_defaults`.

#### Health
- **Ch04-F099** — `/health` doesn't check DB.
- **Ch04-F100** — `/ready` skips Redis/MinIO checks.
- **Ch04-F101** — New Redis client per call.
- **Ch04-F102** — `error.message` may leak credentials.

#### Barcode
- **Ch04-F103** — `upcitemdb` 100/day shared.
- **Ch04-F104** — Barcode shared with third-party without disclosure.
- **Ch04-F105** — 404 cached for 24h hides new products.
- **Ch04-F106** — `AbortController` `response.json()` may hang.
- **Ch04-F107** — Regex allows 9-11 digit invalid barcodes.

#### Newsletter
- **Ch04-F108** 🔴 — No double-opt-in (also Phase 1).
- **Ch04-F109** — Unsubscribe not RFC 8058 one-click.
- **Ch04-F110** — Unsubscribe HMAC truncated to 128 bits.
- **Ch04-F111** — Email regex too permissive.
- **Ch04-F112** — IP relies on `trust proxy` config.
- **Ch04-F113** — Subscribe error path differs from success (verdict OK).

#### Contact
- **Ch04-F114** — No CAPTCHA on contact form.
- **Ch04-F115** — `name` verbatim in subject; CR/LF possible.
- **Ch04-F116** — 5000-char messages with no retention.
- **Ch04-F117** — No admin GET for contact submissions.

#### Migrations
- **Ch04-F118** — `012_fix_warranty_claims_default.sql` historical state not backfilled.
- **Ch04-F119** — `014_add_item_categories.sql` ALTER TYPE not reversible.
- **Ch04-F120** — `018_dynamic_tips.sql` `'organization'` tagged tips never selected.
- **Ch04-F121** — `020_seed_maintenance_schedules.sql` ON CONFLICT without unique constraint.
- **Ch04-F122** — `023_add_pending_warranty_purchase_status.sql` `'pending'` never written.

#### Flow B (Ch09 — Gmail scanner)
- **Ch09-FlowB-T-B1** 🔴 — Request logger captures third-party access token (also Phase 1).
- **Ch09-FlowB-T-B2** — Ownership check uses email not provider sub.
- **Ch09-FlowB-T-B3** — 5min in-memory `setTimeout` dies with process.
- **Ch09-FlowB-T-B4** — Gmail date-range NaN produces zero-result.
- **Ch09-FlowB-T-B5** — HTML stripper misses numeric entities.
- **Ch09-FlowB-T-B6** 🔴 — Prompt injection in email body (also Phase 1).
- **Ch09-FlowB-T-B7** 🔴 — Generic catch-all query (also Phase 1).
- **Ch09-FlowB-T-B8** — Privacy copy stronger than implementation.
- **Ch09-FlowB-T-B9** — Gmail 401 mid-scan finalizes 'completed' with 0.
- **Ch09-FlowB-T-B10** — Pool client released twice on free-plan skip.
- **Ch09-FlowB-T-B11** — `isRelevantPurchase` exact-set category misses variants.
- **Ch09-FlowB-T-B12** — Default warranty 12 months stamped without source.
- **Ch09-FlowB-T-B13** — `items.notes` stamps raw email subject with PII.
- **Ch09-FlowB-T-B14** — OpenAI 401/429 silently returns null.
- **Ch09-FlowB-T-B15** — `user_analytics` UPDATE silently drops if row missing.
- **Ch09-FlowB-T-B16** — Polling 6min vs server 5min boundary thin.
- **Ch09-FlowB-T-B17** — Server local TZ off-by-one in date-range.
- **Ch09-FlowB-T-B18** — No per-user concurrent scan cap.
- **Ch09-FlowB-T-B19** — Privacy promise to disconnect from Settings unimplemented.

#### Test pairing
- **Ch12-R009** — `pending → completed` succeeds (not canonical).
- **Ch12-R013** — 202+pending success without verifying completion.
- **Ch12-R018** — Email-fail swallowed but DB row not asserted.
- **Ch12-T008** — Claim status transitions not enforced.
- **Ch12-T009** — Cancel after claim filed untested.
- **Ch12-T015** — No test asserts `audit_logs` writes.
- **Ch12-T020** — Home delete cascades for claims/docs untested.
- **Ch12-T021** — Health-score with zero items untested.
- **Ch12-T032** — Cross-user DELETE notification untested.
- **Ch12-T033** — Cross-user maintenance isolation tests.
- **Ch12-T034** — Barcode cache cross-user behavior unverified.
- **Ch12-T035** — Idempotency on rapid `/scan` untested.
- **Ch12-T036** — Items-needing-attention shape-only test.
- **Ch12-T040** — Archived-item warranty-claim filing untested.
- **Ch12-T046** — Email verification token replay untested.
- **Ch12-T047** — Partner reject audit/email untested.
- **Ch12-T058** — Degraded health untested.
- **Ch12-T059** — Push-token register/upsert/delete untested.
- **Ch12-T060** — Unknown category should 400 not 500.

### Likely-stale
None.

---

# Phase 8 — Payload drift alignment (Dart ↔ Joi ↔ DB across 20 entities)

**Goal.** Make the three representations agree for every entity. No more "Dart says nullable, DB says NOT NULL, Joi says optional." This is mechanical sweep work — but only after Phases 2/4/5/7 stabilize the API + DB shapes.

**Files touched.**
- `packages/shared_models/lib/src/*.dart` (20 model files)
- `apps/api/src/validators/*.ts` (per-entity validators)
- `apps/api/src/db/migrations/*.sql` (CHECK / NOT NULL / DEFAULT additions)

**Depends on.** Phases 2, 4, 5, 7 (API contract must be stable before Dart aligns).

**Success criteria.**
- Every entity has a hydrate-render test asserting `fromJson(toJson(x)) == x` against a representative sample.
- No `DateTime.tryParse(...) ?? DateTime.now()` fallbacks in `shared_models`.
- Every Dart enum has a `_byName` map; unknowns log to Loki rather than coerce to a default.
- DB CHECK constraints match Joi enum lists.
- `flutter analyze` clean; `tsc --noEmit` clean; CI lint passes.

### Findings (89 total)

#### User
- **Ch08-User-D001** — `auth_provider` silent default to `'email'`.
- **Ch08-User-D002** — `is_partner` fabricated client-side, no DB column.
- **Ch08-User-D003** — `deleted_at` invisible to client.
- **Ch08-User-D004** — `deletion_scheduled_for` invisible to client.
- **Ch08-User-D005** — `stripe_customer_id` no explicit strip.

#### Home
- **Ch08-Home-D006** — `Home.address` Joi 500 vs DB unlimited.
- **Ch08-Home-D007** — `toJson` sends server-readonly `created_at/updated_at`.

#### Item
- **Ch08-Item-D008** — `product_image_url` URI pattern blocks legacy non-URI rows.
- **Ch08-Item-D009** — DECIMAL price → double precision loss across edits.
- **Ch08-Item-D010** — `warranty_end_date` NOT NULL DB but nullable Dart.
- **Ch08-Item-D011** — `added_via` no DB CHECK.
- **Ch08-Item-D012** — `archived_at` not auto-synced with `is_archived`.
- **Ch08-Item-D013** — `installation_date` stripped by `toInsertJson`.
- **Ch08-Item-D014** — `last_maintenance_date` stripped by Dart.
- **Ch08-Item-D015** — `next_maintenance_due` stripped by Dart.
- **Ch08-Item-D016** — `warranty_months` no default on update.
- **Ch08-Item-D017** — `estimated_repair_cost` never seeded.
- **Ch08-Item-D018** — Category enum masquerades unknowns.

#### Document
- **Ch08-Document-D019** — `file_size` INTEGER blocks >2GB.
- **Ch08-Document-D020** — No `updateDocumentSchema` validator.
- **Ch08-Document-D021** — `toInsertJson` sends server-managed fields.

#### WarrantyClaim
- **Ch08-WarrantyClaim-D022** — Update schema missing `.max('now')`.
- **Ch08-WarrantyClaim-D023** — `out_of_pocket` nullable Dart, NOT NULL DB.
- **Ch08-WarrantyClaim-D024** — `ClaimStatus.inReview` camelCase mapping.
- **Ch08-WarrantyClaim-D025** — `claim_date.fromJson` defaults to `DateTime.now()`.

#### WarrantyPurchase
- **Ch08-WarrantyPurchase-D026** — `expires_at.fromJson` silently defaults.
- **Ch08-WarrantyPurchase-D027** — `commission_amount` no Joi max.
- **Ch08-WarrantyPurchase-D028** — `purchase_date` falls back to `now()`.
- **Ch08-WarrantyPurchase-D029** — No create-schema validator for status.

#### MaintenanceLog
- **Ch08-MaintenanceLog-D030** — `completed_date` required Dart but optional Joi.
- **Ch08-MaintenanceLog-D031** — `cost` tri-state inconsistent.

#### MaintenanceSchedule
- **Ch08-MaintenanceSchedule-D032** — `category` typed as `String` not `ItemCategory`.
- **Ch08-MaintenanceSchedule-D033** — `difficulty` free text.
- **Ch08-MaintenanceSchedule-D034** — `priority` Dart default 0 vs DB default 5.
- **Ch08-MaintenanceSchedule-D035** — Dart missing `updated_at`.

#### Notification
- **Ch08-Notification-D036** — `template_id` absent from Dart.
- **Ch08-Notification-D037** — `gift_id` missing breaks deep-link.
- **Ch08-Notification-D038** — `schema.sql` 8 types vs real 14.
- **Ch08-Notification-D039** — `actionData` fallback chain reads phantom `action_data`.
- **Ch08-Notification-D040** — `sent_at` NOT NULL DB but nullable Dart.
- **Ch08-Notification-D041** — `delivered_at` absent.
- **Ch08-Notification-D042** — `action_taken` absent.
- **Ch08-Notification-D043** — `action_taken_at` absent.
- **Ch08-Notification-D044** — `platform` absent.
- **Ch08-Notification-D045** — `fcm_message_id` absent.
- **Ch08-Notification-D046** — `scheduledAt` required Dart but no DB column.
- **Ch08-Notification-D047** — `actionType` required, server never emits.

#### NotificationPreferences
- **Ch08-NotificationPreferences-D048** — `first_reminder_days` no DB CHECK.
- **Ch08-NotificationPreferences-D049** — `created_at`/`updated_at` absent.

#### Partner
- **Ch08-Partner-D050** — No pure Partner Dart model.
- **Ch08-Partner-D051..D061** — Eleven missing fields (website, brand_color, logo_url, subscription_tier, default_message, default_premium_months, stripe_onboarded, is_active default mismatch, is_verified, service_areas, license_number).

#### PartnerGift
- 🔴 **Ch08-PartnerGift-D062** (Phase 1) — No Dart model at all.
- **Ch08-PartnerGift-D063** — `premium_months` no CHECK.
- **Ch08-PartnerGift-D064** — Status query Joi missing `'payment_failed'`.

#### PartnerCommission
- 🔴 **Ch08-PartnerCommission-D065** (Phase 1) — No Dart model.
- **Ch08-PartnerCommission-D066** — `amount` unbounded across all layers.
- **Ch08-PartnerCommission-D067** — `reference_type` free text.
- **Ch08-PartnerCommission-D068** — `payout_method` free text.

#### EmailScan
- **Ch08-EmailScan-D069** — Counts parsed via `int.tryParse(toString())`.
- **Ch08-EmailScan-D070** — `provider` varchar no CHECK.

#### AuditEvent
- **Ch08-AuditEvent-D071** — No Dart model (admin-only, expected).
- **Ch08-AuditEvent-D072** — `audit_action` enum drifts from TS union.
- **Ch08-AuditEvent-D073** — `resource_type` free text.
- **Ch08-AuditEvent-D074** — `http_method` free text.

#### WebhookEvent
- **Ch08-WebhookEvent-D075** — `source` free text.
- 🔴 **Ch08-WebhookEvent-D076** (Phase 1) — `status DEFAULT 'processed'`.
- **Ch08-WebhookEvent-D077** — No retention/cleanup cron.

#### NewsletterSubscriber
- **Ch08-NewsletterSubscriber-D078** — No validator file.
- **Ch08-NewsletterSubscriber-D079** — UNIQUE blocks resubscribe.
- **Ch08-NewsletterSubscriber-D080** — `source` free text.

#### ContactSubmission
- **Ch08-ContactSubmission-D081** — No validator and no Dart model.
- **Ch08-ContactSubmission-D082** — `email` no format CHECK.
- **Ch08-ContactSubmission-D083** — `message` no max length.

#### Category / brand_suggestions / tips
- **Ch08-Category-D084** — `warranty_months` default aligned.
- **Ch08-Category-D085** — `icon VARCHAR(16)` too small.
- **Ch08-Category-D086** — `ItemCategory` 44 values aligned post-014.
- **Ch08-Category-D087** — `brand_suggestions.brand` unbounded Dart vs `VARCHAR(255)`.
- **Ch08-Category-D088** — `tips` table no Dart model.
- **Ch08-Tips-D089** — `health_score_history` JSONB shape undocumented.

### Likely-stale
None.

---

# Phase 9 — Mobile (screens / core / packages)

**Goal.** Largest phase by line count. Mobile rebuild on stable backend: screens (140), core providers/services/db/router (104), packages api_client/shared_models/shared_ui (104). Sub-clusters: refresh-token mutex, biometric placebo, sqflite_sqlcipher migration, router redirect race, offline-sync integrity, premium source-of-truth, OAuth re-auth, TLS pinning, log redaction, i18n.

**Files touched.**
- `apps/mobile/lib/features/**`
- `apps/mobile/lib/core/**`
- `packages/api_client/**`
- `packages/shared_models/**` (overlap with Phase 8)
- `packages/shared_ui/**`

**Depends on.** Phases 1, 2, 3, 4, 5, 7, 8 (mobile binds to API contracts).

**Success criteria.**
- `flutter analyze` zero issues across `apps/mobile`.
- `flutter test` clean. New tests for offline-sync conflict, refresh-token race, premium source-of-truth, OAuth re-auth.
- `flutter build apk --debug` succeeds.
- All Phase 1 mobile criticals re-verified.

### Findings (348 total)

#### Chapter 5 — Mobile screens (140)
- **Ch05-F001..F140** — full list in catalogue (see `/tmp/audit_ch05_07.md` lines 5-144).
- 🔴 **F021** (warranty month math), 🔴 **F034** (gift expiry math), 🔴 **F100** (premium hardcoded), 🔴 **F109** (OAuth delete-account), 🔴 **F130** (warranty purchase expiresAt) — all Phase 1.
- Sub-clusters: add_item (F001-F026), email_scanner (F027-F031), gifts (F032-F037), home (F038-F045), item_detail (F046-F056), items (F057-F062), maintenance (F063-F074), notifications (F071-F074), onboarding (F075-F098), premium (F099-F103), search (F104-F105), settings (F106-F121), warranty_claims (F122-F127), warranty_purchases (F128-F133), platform (F134-F140).

#### Chapter 6 — Mobile core (104)
- **Ch06-C100..C203** — full list in catalogue.
- 🔴 **C101** (router redirect race), 🔴 **C104** (sync mutex), 🔴 **C105** (retry corruption), 🔴 **C108** (conflict resolver), 🔴 **C109** (signOut leaves DB), 🔴 **C110** (biometric placebo), 🔴 **C128** (premium OR-join), 🔴 **C136** (logger token leak), 🔴 **C145** (DB unencrypted), 🔴 **C151** (single global DB), 🔴 **C167** (receipt OOM), 🔴 **C176** (no TLS pin), 🔴 **C180** (sync backoff stall) — all Phase 1.
- Sub-clusters: router (C100-C103, C193-C196), offline-sync (C104-C108, C138, C148-C150, C180), auth/repository (C109-C112, C116-C118, C129-C130, C195), items/homes/notifications providers (C113-C115, C158-C161), email-scanner provider (C119-C120, C164-C165), push (C121-C125), premium (C126-C129), category/auto-archive (C131-C133), logging (C134-C137), connectivity/db tables (C139-C151), widgets (C152-C157), email-oauth (C164-C166), receipt scanner (C167-C168), api_client/repos (C169-C184), CSV/PDF (C185-C188), main bootstrap (C189-C192), warranty-claims/purchases providers (C198-C202), demo-mode (C201-C202).

#### Chapter 7 — Packages (104)
- **Ch07-P001..P104** — full list in catalogue.
- 🔴 **P014** (URL path injection), 🔴 **P020** (TLS pinning), 🔴 **P021** (token redaction) — all Phase 1.
- Sub-clusters: api_client (P001-P024), shared_models drift hygiene (P025-P069 — overlaps Phase 8 for the entity-level fixes; this phase owns the Dart code mechanics), shared_ui (P070-P099), Home/User/Notif drift carry-over (P100-P104).

### Likely-stale (verify against `git log` of `apps/mobile` since `c05bd4e` and `d8ea43e`)
- Mobile-deploy adjacent items: only files in `apps/mobile/android/**`, `apps/mobile/ios/**`, `Fastlane`, signing config — none of the audited findings are in those paths, so most should not be stale. Confirm via `git log --since=2026-04-22 -- apps/mobile/`.

---

# Phase 10 — Partner dashboard + marketing site + test suite

**Goal.** Land the dashboard with a hardened proxy + admin layout gating + CSRF + CSP + headers; sweep the marketing site for legal/security claim accuracy + privacy/cookies cleanup + CSP/headers; reform the test suite to stop mocking rate limiters globally, run real migrations, and stop codifying buggy behavior.

**Files touched.**
- `apps/partner-dashboard/src/app/api/v1/[...path]/route.ts` and surrounding routes
- `apps/partner-dashboard/middleware.ts`
- `apps/partner-dashboard/src/app/{login,signup,reset-password,onboarding,dashboard,admin}/**`
- `apps/partner-dashboard/src/{lib,components}/**`
- `apps/partner-dashboard/next.config.js`
- `apps/marketing/src/{pages,components,layouts}/**`
- `apps/marketing/astro.config.mjs`
- `apps/api/src/__tests__/**`
- `apps/api/src/__tests__/setup.ts`, `helpers.ts`

**Depends on.** Phases 1, 2, 3, 4, 5 (server contracts must be final before browser proxy + tests follow).

**Success criteria.**
- Dashboard `npm run build` clean with no warnings.
- Marketing `npm run build` clean.
- API `npm test` clean with rate-limiter integration suite added (no global mock).
- New tests for forged `isAdmin` JWT, mass-assignment via PUT `/users/me`, refresh-family invalidation, gift activation lockouts, webhook concurrency claim race, refund clawback split between paid/pending paths.
- Marketing claims about SOC2/RLS/MFA/encryption/E2E either backed by implementation or softened to in-progress.

### Findings (142 total)

#### Partner dashboard — proxy + middleware (W001–W050)
- 🔴 **Ch10-W001..W005** (Phase 1 stop-gap; this phase ships the structural sweep).
- **Ch10-W006** — Missing API_URL silently routes to localhost.
- **Ch10-W007** — Edge middleware refresh fetch has no timeout.
- **Ch10-W008** — JWT signature unverified.
- **Ch10-W009** — Refresh stores accessToken without shape validation.
- **Ch10-W010** — Refresh route accepts cross-origin requests.
- **Ch10-W011** — Auth errors echo upstream verbatim.
- **Ch10-W012** — Email validator differs from server.
- **Ch10-W013** — `fullName` auto-derived from email prefix.
- **Ch10-W014** — `/onboarding` accessible to onboarded partners.
- **Ch10-W015** — Homebuyer login enumeration.
- **Ch10-W016** — JWT body decoded with no try/catch.
- **Ch10-W017** — 5xx swallowed as success.
- 🔴 **Ch10-W018** (Phase 1) — Reset bypasses signup password complexity.
- **Ch10-W019** — Reset token in querystring.
- **Ch10-W020** — Server doesn't validate companyName non-empty.
- **Ch10-W021** — Double-submit risk on Complete setup.
- **Ch10-W022** — Stripe Connect URL hostname-only check.
- **Ch10-W023** — Stripe status refetches per focus event.
- **Ch10-W024** — `logo_url` renders without validation.
- **Ch10-W025** — Fetch on mount with no AbortController.
- **Ch10-W026** — `recent_activity` null fields render "Invalid Date".
- **Ch10-W027** — Gift fields lack server-mirror validation.
- 🔴 **Ch10-W028** (Phase 1) — Mutations have no CSRF token.
- **Ch10-W029** — `mailto` built without encoding.
- **Ch10-W030** — Activation URL not validated before clipboard.
- **Ch10-W031** — Resend double-click sends two emails.
- **Ch10-W032** — Analytics refetch per keystroke.
- **Ch10-W033** — `Promise.all` hides partial failures.
- **Ch10-W034** — 401 on `loadProfile` not redirected.
- **Ch10-W035** — Status derived from plan, ignores server status.
- **Ch10-W036** — `parseFloat` on DECIMAL drifts cents.
- **Ch10-W037** — `health` path inconsistent.
- **Ch10-W038** — Admin has no password change/2FA/session-revoke UI.
- **Ch10-W039** — Raw user PII shown without admin-side audit.
- **Ch10-W040** — Hard-delete behind native `confirm()`.
- **Ch10-W041** — Reject has no reason capture/notification.
- **Ch10-W042** — Optimistic commission flips with no rollback.
- **Ch10-W043** — `requireAdmin` serial with stats.
- **Ch10-W044** — Admin layout doesn't gate on role.
- **Ch10-W045** — Logout fallback leaves cookies set.
- **Ch10-W046** — Internal error strings leak to admin error UI.
- **Ch10-W047** — `getUser` conflates 401 with 5xx.
- **Ch10-W048** — Refresh-then-retry can loop on persistent 401.
- **Ch10-W049** — Retry replays consumed body.
- **Ch10-W050** — Client + proxy share 30s timeout race.

#### Partner dashboard — components / config / headers (W051–W066)
- **Ch10-W051** — Fallback to `havenkeep.app` (wrong TLD).
- **Ch10-W052** — Stringify of unbounded metadata blocks render.
- **Ch10-W053** — Fragment in map without key.
- **Ch10-W054** — `is_active` overloaded as pending+rejected.
- **Ch10-W055** — `partnerId` interpolated unencoded.
- **Ch10-W056** — Stale searchParams propagate via pagination.
- **Ch10-W057** — No `loading.tsx` for admin routes.
- **Ch10-W058** — No `error.tsx` for admin segment.
- **Ch10-W059** — `error.message` leaks to user.
- **Ch10-W060** — `getUser` fetched per page; not cached.
- **Ch10-W061** — No CAPTCHA on login/signup.
- **Ch10-W062** — No delivery status surface for gift emails.
- **Ch10-W063** — Spinners cause CLS.
- **Ch10-W064** — No robots.txt, X-Frame-Options, CSP.
- **Ch10-W065** — `images.remotePatterns` missing.
- **Ch10-W066** — No regression tests for refresh-race/partial-JWT.

#### Marketing site (W067–W112)
- **Ch10-W067** — `PUBLIC_API_URL` falls back to a personal subdomain. **(verify against 741c43d)**
- **Ch10-W068** — Contact form has no CSRF/bot/rate-limit.
- **Ch10-W069** — Implicit credentials policy on cross-origin POST.
- **Ch10-W070** — Auto `window.location` to `mailto` on failure.
- **Ch10-W071** — Newsletter POSTs to relative path on static host. **(verify against 741c43d)**
- **Ch10-W072** — Newsletter has no double opt-in/CAPTCHA.
- **Ch10-W073** — Success state auto-resets; allows re-submit.
- **Ch10-W074** — Google Fonts leak visitor IP; breaks strict CSP.
- **Ch10-W075** — OG image is SVG; broken unfurls.
- **Ch10-W076** — Single OG image across all pages.
- **Ch10-W077** — Title duplicates "HavenKeep".
- **Ch10-W078** — No CSP/X-Frame-Options.
- **Ch10-W079** — Animations bypass `prefers-reduced-motion`.
- **Ch10-W080** — Stats claims uncited.
- **Ch10-W081** — Possibly fabricated testimonials.
- **Ch10-W082** — Star SVGs lack `aria-hidden`.
- **Ch10-W083** — Footer SVGs lack `aria-hidden`.
- **Ch10-W084** — External links lack `target+rel`.
- **Ch10-W085** — App Store links open in same tab.
- **Ch10-W086** — Hero anchor `#how-it-works` not portable.
- **Ch10-W087** — Duplicate billing-toggle script.
- **Ch10-W088** — Best Value badge lacks `aria-label`.
- **Ch10-W089** — Inline scripts incompatible with strict CSP.
- **Ch10-W090** — `IntersectionObserver` never unobserves.
- **Ch10-W091** — Mobile menu lacks `aria-expanded/controls`.
- **Ch10-W092** — Hamburger has no accessible name.
- **Ch10-W093** — Blog posts hardcoded; no content collection.
- **Ch10-W094** — Featured/list dates lack `<time>` tag.
- **Ch10-W095** — SOC 2/RBAC/E2E claims contradict reality. **(verify against 241231e)**
- **Ch10-W096** — RLS claim with no DB policies. **(verify against 241231e)**
- **Ch10-W097** — 30-day delete promise without purge job. **(verify against 241231e)**
- **Ch10-W098** — Lists Intercom/Cloudflare/GA cookies that don't exist. **(verify against 241231e)**
- **Ch10-W099** — Promised Cookie Settings link missing. **(verify against 241231e)**
- **Ch10-W100** — `allowedHosts:true` disables Vite host check.
- **Ch10-W101** — Hardcoded canonical, staging points at prod. **(verify against 741c43d)**
- **Ch10-W102** — No sitemap.xml / robots.txt.
- **Ch10-W103** — Heading hierarchy inconsistencies.
- **Ch10-W104** — External subdomain links lack visual cue.
- **Ch10-W105** — Slug array can drift from filenames.
- **Ch10-W106** — No RSS link/feed.
- **Ch10-W107** — Hero font weights not preloaded.
- **Ch10-W108** — "60-second setup" claim unmeasured.
- **Ch10-W109** — "Works offline" contradicts mobile queue bugs.
- **Ch10-W110** — "MFA for all team members" not in product. **(verify against 241231e)**
- **Ch10-W111** — No CSP report-uri.
- **Ch10-W112** — Domain duplicated across config and layout. **(verify against 741c43d)**

#### Test suite — coverage gaps not owned by other phases (T001, T013, T028, T030, T031, T043, T044, T045, T048-T050, T053, T057)
- **Ch12-T001** — Full delete→suspend→recover→purge lifecycle untested.
- 🔴 **Ch12-T013** (Phase 1) — Rate limiter never exercised.
- **Ch12-T028** — Contact spam protection untested due to mock.
- 🔴 **Ch12-T030** (Phase 1) — Forged `isAdmin` token grants untested.
- 🔴 **Ch12-T031** (Phase 1) — Mass assignment on PUT `/users/me` untested.
- **Ch12-T043** — SQL injection on sort/order params untested.
- **Ch12-T044** — Pagination negative/huge values untested.
- **Ch12-T045** — Disposable-email rejection untested.
- **Ch12-T048** — `fullName` collision in fixtures.
- 🔴 **Ch12-T049** (Phase 1) — Tests will TRUNCATE prod if `DATABASE_URL` misconfigured.
- **Ch12-T050** — Migrations not enforced before tests.
- **Ch12-T057** — Audit pagination correctness untested.

#### Test suite — reinforced bugs not owned by other phases (R005, R006, R010, R012)
- **Ch12-R005** — Allows 500 on invalid refresh token.
- **Ch12-R006** — Asserts 500 for unknown category.
- **Ch12-R010** — Idempotent read may bump `opened_at`.
- **Ch12-R012** — Cache asserts call count not body equality.
- 🔴 **Ch12-R014** (Phase 1) — `getAuthToken` signs with mismatched email.
- 🔴 **Ch12-R020** (Phase 1) — Rate limiters globally mocked everywhere.

### Likely-stale (verify first)
- **Ch10-W067, W071, W101, W112** — domain/EU hosting touched by `741c43d`.
- **Ch10-W095, W096, W097, W098, W099, W110** — privacy/legal pages rewritten by `241231e`.

---

## Cross-phase dependency graph

```
Phase 1 (criticals) ──► every later phase
        │
        ▼
Phase 2 (DB + pool) ──► Phase 3 (API infra)
        │                     │
        ▼                     ▼
        ├──────────────► Phase 4 (auth)
        │                     │
        │                     ▼
        ├──────────────► Phase 5 (payments)  ◄── Phase 4
        │                     │
        ▼                     ▼
Phase 6 (uploads/CRUD) ──► Phase 7 (warranty/notif/etc.)
        │                     │
        └─────────┬───────────┘
                  ▼
            Phase 8 (drift)
                  │
                  ▼
            Phase 9 (mobile)
                  │
                  ▼
            Phase 10 (dashboard/marketing/tests)
```

Phase 5 depends on Phase 4 because partner gift activation links to user accounts; Phase 7 depends on Phase 5 because warranty-purchase cancellation refunds Stripe and decrements partner commissions.

## Per-phase acceptance gate (CLAUDE.md rule 5)

Every phase must finish with:
- `apps/api`: `cd apps/api && npx tsc --noEmit && npm test` — zero errors, zero warnings.
- `apps/marketing`: `cd apps/marketing && npm run build` — zero warnings.
- `apps/partner-dashboard`: `cd apps/partner-dashboard && npm run build` — zero warnings.
- `apps/mobile`: `cd apps/mobile && flutter analyze && flutter test && flutter build apk --debug` — zero issues.
- `packages/shared_models`, `packages/shared_ui`, `packages/api_client`: lint + typecheck via the consuming app's pipeline.

If a phase doesn't touch a particular app, that app's gate is skipped — but if the phase touches a shared package, **every consuming app's gate runs**. (E.g., Phase 8 touches `shared_models` → mobile + api gates both run.)

## What's not in this plan

Items the audit either marked OK on inspection (a few "verdict: OK" lines) or that explicitly cross-reference an earlier audit's C-number with no new evidence. They're carried in the catalogue for completeness but require no work beyond the phase that owns them.

This plan does NOT decide:
- The order in which Phase 1's 84 critical items ship within Phase 1 (sub-prioritize when starting Phase 1).
- Whether to split Phase 9 into 9a (screens) / 9b (core) / 9c (packages) — left to the next context based on team capacity.
- Whether marketing claim corrections (W080, W081, W095, W109) require legal review before merge — flag as you encounter them.
