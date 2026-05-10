# HavenKeep — End-to-End Audit Report

**Date:** 2026-05-10
**Method:** 8 parallel agents traced every flow end-to-end across `apps/api`, `apps/mobile`, `apps/partner-dashboard`, `apps/marketing`, `packages/{api_client,shared_models,shared_ui}`, and the database layer.
**Per-agent reports:** [`docs/audit-runs/01..08-*.md`](audit-runs/) — each agent's full file:line citations live there.

---

## Headline counts

| Severity | Count | Where |
|---|---|---|
| **Critical** | **27** | spread across all 8 surfaces |
| High | 51 | |
| Medium | 76 | |
| Low | 60 | |

This report consolidates the per-agent findings, **cross-references the cases where multiple agents flagged the same issue from different angles**, and ranks fixes by what to ship first.

---

## How to read this

Findings are grouped by theme, not by agent. Each top-level item has:
- a **fingerprint** (file:line) — the canonical place to fix it
- the agent reports that flagged it (so you can read the context if needed)
- a **cross-reference cluster** when multiple agents touched the same theme — those are the highest-confidence findings

The numbering is **C1, C2, …** for the consolidated report; the original per-agent IDs (e.g. `C-MS-1`, `H-MP-3`) are kept in parens for traceability.

---

# Part 1 — Critical findings (must fix before TestFlight / staging-customer access)

## Cluster A — Account deletion drift (4 sources, 2 wrong numbers)

**This is the most reproducible finding in the audit.** Four agents independently flagged it.

| Source | Says |
|---|---|
| `apps/api/src/routes/users.ts:643` | `INTERVAL '30 days'` (the truth) |
| `apps/api/src/services/account-purge.service.ts` | 30-day cooling-off (matches API) |
| `apps/api/src/services/email.service.ts` | "anonymized analytics … up to 30 days" |
| `apps/marketing/src/pages/legal/privacy.astro:108` | **7-day** grace |
| `apps/marketing/src/pages/legal/delete-account.astro:24,57` | **7-day** grace |
| `apps/mobile/lib/features/settings/delete_account_screen.dart:73-77,110-113` | "permanent / cannot be undone" — no grace mentioned |

**C1 — Privacy policy lies about the cooling-off period (regulatory exposure)**
- Agent reports: marketing (C1), auth (C6), mobile features (H1)
- Fix: change both `privacy.astro:108` and `delete-account.astro:24,57` from "7-day" → "30-day".
- **Why this matters legally:** A user who reads the privacy policy expecting a 7-day window, exercises GDPR Art. 17, and then sees their email/full_name in a Stripe webhook 14 days later has a regulator complaint with documented evidence.

**C2 — Mobile UI tells the user "permanent / cannot be undone" — directly contradicts the API behavior**
- File: `apps/mobile/lib/features/settings/delete_account_screen.dart:73-77,110-113`
- Agent reports: mobile features (H1), marketing (C1)
- Fix: replace the "permanent" header with "Your account will be deleted in 30 days. You can recover it at any time during that period by signing in."

**C3 — Password users have a 1-hour effective recovery window, not 30 days**
- File: `apps/api/src/routes/auth.ts:470-499` (login state-deny) + `apps/api/src/middleware/auth.ts:138-146` (recover bypass) + `apps/api/src/routes/users.ts:703-748` (recover endpoint)
- Agent report: auth (C4)
- The `/auth/login` route returns `403 ACCOUNT_PENDING_DELETION` *with no tokens*. `/me/recover` requires `authenticate` → a valid access token. After the original access token expires (1h), recovery is permanently closed for password users — yet the API response says "log back in to recover" and the privacy policy promises 30 days.
- Fix: mint a short-lived recovery-only token (purpose `'account_recover'`, 15-min TTL) when login hits the `ACCOUNT_PENDING_DELETION` branch; the middleware bypass at `auth.ts:138-146` accepts that token type only for `/me/recover`. Combined with C4 below.

**C4 — Mobile has zero handling for `ACCOUNT_PENDING_DELETION` and no recover-account UI**
- File: entire mobile codebase has zero references to `ACCOUNT_PENDING_DELETION`, `recoverAccount`, or `/me/recover`
- Agent report: auth (C5)
- Combined with C2 + C3, this means the 30-day cooling-off is a phantom feature. The user sees "permanent" before delete, sees "scheduled in 30 days" in the toast after delete, and finds no recovery surface anywhere.
- Fix: add a `RecoverAccountScreen`. When sign-in returns `ACCOUNT_PENDING_DELETION`, route to it. The screen calls `/users/me/recover` with the recovery token from C3.

---

## Cluster B — TLS pinning is a privacy-policy lie

Two agents independently flagged this from different angles.

**C5 — Privacy policy claims "Mobile clients additionally pin the leaf certificate" — false on two counts**
- File: `apps/marketing/src/pages/legal/privacy.astro:97`
- Agent reports: marketing (C2), mobile sync/storage (C-MS-1)
- (1) Pinning is **NOT wired in any release path.** `packages/api_client/lib/src/client.dart:202-217` only documents an SPKI-pinning recipe in a doc comment. The constructor at `client.dart:252-277` is the only construction point and `apps/mobile/lib/main.dart:110` calls it as `ApiClient(baseUrl: config.apiBaseUrl)` — no `httpClient:` argument. No `TLS_PIN_*` / `SPKI_*` value in any `.env.*`.
- (2) "Leaf certificate" is wrong terminology — the doc-comment describes **SPKI pinning** (issuer's public-key hash). They are not interchangeable; leaf-cert pinning would brick the app every 90 days when Let's Encrypt rotates.
- Fix: Either (a) implement the pinned client in release builds and update the policy to say "SPKI pin", or (b) delete the sentence from the privacy policy until pinning ships. Option (a) is required before TestFlight; (b) is the interim fix.

---

## Cluster C — Three OAuth bypasses (MFA, soft-delete, suspended)

All three are in the same handler family and were flagged in one agent report. They share a root cause: `/auth/google` and `/auth/apple` skip security checks that `/auth/login` performs.

**C6 — MFA challenge token doubles as a valid access token (full MFA bypass)**
- Files: `apps/api/src/middleware/auth.ts:77-80` + `apps/api/src/services/mfa.service.ts:92-100`
- Agent report: auth (C1)
- `mintMfaChallengeToken` signs a JWT with the same secret as access tokens. The `authenticate` middleware never inspects the `purpose: 'mfa_challenge'` claim. After login, the attacker (who has the password) holds the challenge token, sends `Authorization: Bearer <mfa_token>` to any other route, and is in. The 5-min TTL is the only thing that bounds the window.
- Fix: in `middleware/auth.ts` after `jwt.verify`, reject if `decoded.purpose === 'mfa_challenge'`. Mirror the symmetric guard `verifyMfaChallengeToken` already does.

**C7 — `/auth/google` and `/auth/apple` skip MFA entirely**
- Files: `apps/api/src/routes/auth.ts:1282-1456` (Google), `1471-1748` (Apple)
- Agent report: auth (C2)
- `/auth/login` checks `MfaService.getStatus(user.id)` and returns an MFA challenge when a verified factor exists. The OAuth handlers go straight to `createAuthSession`. A user with TOTP enrolled who *also* signed up with Google has MFA bypassable via Google sign-in.
- Fix: hoist the MFA check into a helper `requireMfaOrIssueChallenge(userId, ...)` and call it from both OAuth handlers right before `createAuthSession`.

**C8 — `/auth/google` and `/auth/apple` issue tokens to soft-deleted and admin-suspended users**
- Files: same as C7
- Agent report: auth (C3)
- The H-A1 audit fix added `deleted_at != NULL` and `plan = 'suspended'` guards to `/login`. The OAuth handlers don't have them. A credential-stuffer who happens to also own a same-email Google account can pop a fraud-suspended account; the audit log records `auth.oauth_login success=true`.
- Fix: add the same H-A1 guard to both OAuth handlers after the `userResult` lookup.

---

## Cluster D — Mobile gift activation is broken end-to-end

Three findings combine to mean **partner-gifted users who sign up via deep link cannot actually redeem.**

**C9 — `pendingGift` query param is never consumed by the welcome screen**
- File: `apps/mobile/lib/features/onboarding/welcome_screen.dart:50-77`
- Agent report: mobile features (C1)
- `router.dart:163-170` rewrites unauthenticated `/gift/<code>` deep links to `/welcome?pendingGift=<code>`, and `gift_activation_screen.dart:74-81` ALSO stashes the code in SharedPreferences under `pending_gift_code`. But the welcome screen only reads `pendingReferral` and the `referral_code` SP key. None of the three sign-up paths (email, Google, Apple) reads `pending_gift_code` and resumes activation.
- Fix: in `welcome_screen.dart`, after a successful auth call, read `prefs.getString('pending_gift_code')`, and if non-empty `context.go('/gift/$code')` then `prefs.remove('pending_gift_code')`. Show a banner analogous to `_buildReferralBanner`.

**C10 — Gift activation success screen always shows the default 6 months**
- File: `apps/mobile/lib/features/gifts/gift_activation_screen.dart:140` + `apps/mobile/lib/core/router/router.dart:622-631`
- Agent report: mobile features (C2)
- The activation screen passes `?months=$_premiumMonths` (query string) but the router reads from `state.extra` (the route extra dictionary). A 12-month gift renders as "6 Months Premium."
- Fix: read from `state.uri.queryParameters['months']` in the route builder, OR pass `extra: {'premiumMonths': _premiumMonths}` from the activation screen.

**C11 — Free-plan item limit is bypassable via direct-route entry**
- Files: `apps/mobile/lib/features/add_item/{quick_add,manual_entry,barcode_scan,receipt_scan}_screen.dart`
- Agent report: mobile features (C3)
- `add_item_screen.dart` (the gateway) correctly watches `isAtItemLimitProvider`. None of the four direct add-screens do. Any caller pushing those routes (push notification, deep link, dashboard empty-state CTA) routes around the limit.
- Fix: extract a shared `AddItemGuard` widget that reads `isAtItemLimitProvider` and wraps every add-screen body.

**C12 — `apps/mobile/lib/features/add_item/wizard/` is dead code (Rule 3 violation)**
- Agent report: mobile features (C4)
- 5 files (`add_item_wizard_screen.dart`, `wizard_step1_basics.dart`, `wizard_step2_warranty.dart`, `wizard_step3_details.dart`, `add_item_draft.dart`) define a multi-step wizard with draft-restore logic. **No route, no caller.**
- Fix: either wire it up as the canonical add path (and delete `manual_entry_screen.dart` + `quick_add_screen.dart`), or delete the wizard folder. Per CLAUDE.md Rule 3, dead code must be deleted.

---

## Cluster E — Mobile sync silently loses data

Five separate failure modes in the offline-first stack. Each is independent; together they make the offline-first promise fragile.

**C13 — `refreshAccessToken` clears tokens on ANY non-200 response**
- File: `packages/api_client/lib/src/client.dart:480-488`
- Agent report: mobile sync (C-MS-2)
- The H-B9 fix in `restoreSession` distinguishes refresh-genuinely-rejected from transport-blip and only clears tokens on the former. But `refreshAccessToken` itself collapses every non-200 (502 from Caddy / 503 from a deploying API / 500 from middleware) into `ApiAuthRequiredException` AND calls `clearTokens()` BEFORE throwing. The H-B9 catch can't tell that this was transient — by the time it sees the exception, tokens are already gone.
- Fix: branch on `response.statusCode` — 401/403 = clear + auth-required; 5xx = `ApiServerException` (don't clear); other 4xx = throw without clearing.

**C14 — 7-day stale-eviction wipes FAILED queue entries**
- File: `apps/mobile/lib/core/database/database.dart:188-189`
- Agent report: mobile sync (C-MS-3)
- `removeEntriesOlderThan` deletes by `createdAt` only — no `status` filter. A failed-write older than 7 days is silently deleted, erasing the user's "lost write" record.
- Fix: one-line filter — `..where((t) => t.status.equals('pending') | t.status.equals('in_flight'))`. Failed rows require explicit user dismiss or a longer cap (90 days).

**C15 — Per-user DB lives in iCloud-backed Documents while its key is device-bound; restore corrupts the user**
- Files: `apps/mobile/lib/core/database/database.dart:249-252`, `apps/mobile/lib/core/services/secure_storage_service.dart:37-44`
- Agent report: mobile sync (C-MS-4)
- The SQLCipher file is in `getApplicationDocumentsDirectory()` (iCloud-backed by default on iOS). The encryption key is in keychain with `KeychainAccessibility.first_unlock_this_device` (intentionally NOT iCloud-replicable — correct security). On iCloud restore to a new device: the encrypted file lands; the key doesn't; `getOrCreateDbEncryptionKey` generates a fresh one; `PRAGMA key=` against the old-encrypted file → SQLCipher returns SQLITE_NOTADB → no fallback → crash on first query → perma-broken local-data path.
- Fix: (a) move DB to `getApplicationSupportDirectory()` AND set `NSURLIsExcludedFromBackupKey`; (b) wrap the first query after `PRAGMA key` in try/catch — on wrong-key, delete the file and recreate.

**C16 — `_parkUpdateConflict` loses the local edit when the preflight `getItemById` fails**
- File: `apps/mobile/lib/core/services/offline_sync_service.dart:460-493`
- Agent report: mobile sync (C-MS-5)
- On 409 from a queued `update_item`, `_parkUpdateConflict` calls `getItemById` to snapshot the server version. If that 404s (item deleted on another device) or hits a network error, the conflict is never written to `sync_conflicts`, the queue entry exhausts retries, and the user's edit vanishes silently.
- Fix: park the conflict FIRST with a synthetic server snapshot (`{"tombstone": true}` if preflight failed), THEN attempt the preflight as enrichment. Wrap park + queue-mark in a transaction.

**C17 — ~30 of 32 enum.fromJson factories silently coerce unknown values**
- File: `packages/shared_models/lib/src/enums.dart` (entire file) + several per-feature enum files
- Agent report: mobile sync (C-MS-6)
- Only `ClaimStatus` and `PartnerStatus` route through `_byName + logUnknownEnumValue`. The other 30 use `Values.firstWhere(orElse:)` with no telemetry. **`WarrantyPurchaseStatus` doesn't know about the `cancelling` enum value (mig 098)** — a user mid-cancel sees the warranty status flip to `active`. The unknown-enum funnel is the team's only signal that a server change drifted before the mobile binary ships; ~30 enums fly under it.
- Fix: add `cancelling` to `WarrantyPurchaseStatus`. Then route every fromJson through the `_byName + logUnknownEnumValue` shape.

---

## Cluster F — Database layer

**C18 — Migration runner's "non-transactional" detection regex never fires**
- File: `apps/api/src/db/migrations/run-migration.ts:14-19, 26-31`
- Agent report: database (C1)
- The regex uses only the `i` flag, not `m` (multiline). Without `m`, `^` matches the start of the string, not the start of each line. Every migration starts with `-- Migration NNN:` so the SQL string never starts with `ALTER TYPE` / `CREATE INDEX CONCURRENTLY` and the regex returns `false` for every file. **The CLAUDE.md claim that "the runner auto-detects ALTER TYPE ADD VALUE and CREATE INDEX CONCURRENTLY" is false in implementation.**
- Currently masked: PG12+ allows `ALTER TYPE … ADD VALUE` in tx as long as the new value isn't referenced; no `CREATE INDEX CONCURRENTLY` migrations exist yet.
- Fix: scan line-by-line, stripping line-comments first.

**C19 — `audit_logs` UUID PK + microsecond `created_at` ordering produces verifier false-positives**
- Files: `apps/api/src/db/migrations/004_audit_system.sql:78-82` + `065_audit_log_hash_chain.sql:31-34,73` + `082_audit_chain_advisory_lock_fix_casts.sql:26-29`
- Agent report: database (C2)
- Trigger reads predecessor by `ORDER BY created_at DESC, id DESC LIMIT 1`. Verifier walks by `(created_at ASC, id ASC)`. UUIDs are random, so the secondary sort produces a different order between rows that share `created_at` (microsecond resolution — collisions happen under load). Verifier walking the rows after a tie can encounter them in a different order than they were committed → flags the chain as broken when it isn't.
- Fix: add a strictly-monotonic `seq BIGSERIAL` column. Trigger picks predecessor by `seq DESC`; verifier walks by `seq ASC`.

**C20 — `verify_audit_chain()` skips `this_hash IS NULL` rows; `audit_cleaner` can hide compromising rows**
- Files: `apps/api/src/db/migrations/065_audit_log_hash_chain.sql:94-95`, `031_audit_logs_immutable.sql:25` (the `audit_cleaner` UPDATE exemption)
- Agent reports: database (C3, H1)
- Mig 031's immutable trigger exempts `audit_cleaner` from BOTH UPDATE and DELETE — the migration comment says "DELETE only" but the implementation allows UPDATE. An attacker with `audit_cleaner` membership can `UPDATE audit_logs SET this_hash = NULL WHERE id = 'compromising-row'`. The verifier silently skips NULL `this_hash` rows → tampering passes verification.
- Fix: in mig 031, scope the exemption by `TG_OP` — `IF TG_OP = 'DELETE' AND audit_cleaner THEN RETURN OLD;`. Backfill `this_hash` for pre-mig-065 rows once, then `ALTER TABLE audit_logs ALTER COLUMN this_hash SET NOT NULL`.

---

## Cluster G — Email scanner: cost runaway + token leak

**C21 — Outlook scans bypass the OpenAI per-user daily budget cap entirely**
- File: `apps/api/src/services/email-scanner.service.ts:1036`
- Agent report: email-scanner (C1)
- `scanGmail` correctly threads `userId` into `extractReceiptData(emailData, signal, userId)` (line 946) so `recordScannerUsage` writes to `openai_usage`. **`scanOutlook` does NOT pass `userId`** — the recording is gated on `if (userId)` (line 1268), so Outlook traffic never writes to the usage table. The pre-scan check reads `openai_user_daily_cost`, which only sees Gmail rows. **An Outlook user can run unlimited scans/day.**
- Fix: pass `userId` into the Outlook call and remove the `if (userId)` gate.

**C22 — Budget cap checked once per scan, but a single scan burns ~500 OpenAI calls**
- File: `apps/api/src/services/email-scanner.service.ts:747`
- Agent report: email-scanner (C2)
- `withinOpenAIBudget` runs once at the top of `performScan`. The inner loop iterates `TRUSTED_RETAILER_DOMAINS` (10 entries) × up to 50 messages = **500 OpenAI calls per scan**, none of which re-check the cap.
- Fix: re-check `withinOpenAIBudget` inside the per-message loop in both `scanGmail` and `scanOutlook`.

**C23 — Refresh-token rotation silently dropped → Outlook integrations die within ~24h**
- File: `apps/api/src/services/email-scanner.service.ts:460-540`
- Agent report: email-scanner (C3)
- `refreshAccessTokenForIntegration` types the response as `{ access_token?, expires_in? }` and never reads `refresh_token`. **Microsoft Identity Platform issues a rotated refresh_token on every refresh-token grant** and the old one stops working. After the first refresh, the next refresh fails with `invalid_grant`. Outlook integrations silently die.
- Fix: read `refresh_token` from the JSON response and re-encrypt and persist alongside the rotated access token in the same UPDATE.

**C24 — Revoke does NOT call the provider's revocation endpoint**
- File: `apps/api/src/services/email-scanner.service.ts:316`
- Agent report: email-scanner (C4)
- `revokeIntegration` only NULLs the local cache and stamps `revoked_at`. It never POSTs to `https://oauth2.googleapis.com/revoke` or Microsoft's logout endpoint. **The OAuth grant remains active server-side at the provider for ~6 months.** The mobile UI's "we revoke the OAuth tokens on the server" microcopy at `email_scanner_screen.dart:703` is **materially false** — privacy-policy-grade misrepresentation.
- Fix: before clearing the row, decrypt the refresh token and POST to the provider's revocation endpoint. Tolerate 4xx silently; 5xx → surface to user.

---

## Cluster H — Partner dashboard

**C25 — `next.config.js` rewrite footgun bypasses the entire proxy when `API_UPSTREAM_URL` is set**
- File: `apps/partner-dashboard/next.config.js:74-83`
- Agent report: partner-dashboard (C1)
- The block, when the env var is set, ships browser cookies (incl. `hk_access_token` httpOnly + `csrf_token`) directly upstream, bypassing the proxy's strip + CSRF + same-origin guards entirely. The env var isn't documented, isn't read elsewhere, and isn't in `.env.local.example`. It's a footgun stub — code that does nothing in documented environments but silently turns the proxy off if anyone copy-pastes the env var.
- Fix: **delete the rewrite block.** The proxy at `src/app/api/v1/[...path]/route.ts` is the single supported upstream path.

---

## Cluster I — Marketing + cross-cutting

**C26 — Plaintext secrets in `/.env.staging` working tree (incl. Firebase service-account RSA private key)**
- File: `/.env.staging` (gitignored, but in every dev's working tree)
- Agent report: marketing (C3)
- Contains: `POSTGRES_PASSWORD`, `JWT_SECRET`, `REFRESH_TOKEN_SECRET`, `REDIS_PASSWORD`, both MinIO keys, and the **full RSA private key** for `firebase-adminsdk-fbsvc@havenkeep-firebase-project.iam.gserviceaccount.com`. The file IS gitignored (verified) so not committed, but presence in every dev's working tree is a leak vector — laptop theft, screen-share, accidental tarball, AI assistants reading working-tree files, etc.
- Fix:
  1. **Treat all secrets as compromised. Rotate every one.** Especially the Firebase service-account key — revoke it in GCP IAM → Service Accounts → Keys, then issue a new one.
  2. Stop committing this shape. Per CLAUDE.md Part 2, staging secrets live in `/opt/staging/havenkeep/.env.api` on the droplet. Delete `/.env.staging` from local working trees after rotation.
  3. Add a pre-commit guard rejecting any commit touching `*.env*` except `.env.example`.

**C27 — `apps/mobile/.env.example` is missing keys the mobile actually reads**
- File: `apps/mobile/.env.example`
- Agent report: marketing (C4)
- `firebase_options.dart:27,35` reads `FIREBASE_ANDROID_API_KEY` / `FIREBASE_IOS_API_KEY`; `environment_config.dart:206,210` requires both at startup. The `.env.example` lists only `API_BASE_URL`, `LOKI_URL`, `REVENUECAT_API_KEY`, `OUTLOOK_*`, `GOOGLE_SERVER_CLIENT_ID`, `APPLE_*`. Missing: `FIREBASE_*` (multiple), `APP_URL`, `SUPPORT_EMAIL`, `GMAIL_REDIRECT_URI`. New devs hit `flutter run --flavor staging` and the app silently falls back to Firebase API key `''` — Crashlytics fails on first crash with a confusing error.
- Fix: regenerate `apps/mobile/.env.example` from the union of every `dotenv.get(...)` call in `apps/mobile/lib/`.

---

# Part 2 — High findings (next priority)

Selected highlights — full list in per-agent reports. Themes:

## Money paths

- **H1 (H-MP-1)** — `createGift` Phase-2 catch swallows non-Stripe `AppError`s ("Tier amount invalid", "Stripe customer deleted", "No saved PM") and rewrites them as generic 402 declines. **Partners chase the wrong failure mode** — a 500-class config bug masquerades as a card decline. (`apps/api/src/services/partners.service.ts:628-695`)
- **H2 (H-MP-2)** — Self-service payout sums dollars in JS floats: `paidTotal += Number(row.amount)`. The centralized `money.ts` exists for this; the call site went rogue. Reconciliation pain at scale. (`apps/api/src/routes/partners.ts:929-981`)
- **H3 (H-MP-3)** — **No daily retry / alert for `webhook_events.status='dead_letter'`.** A bug in a webhook handler eats refunds for 3 days, hits attempt 8, dead-letters, and we never hear about it.
- **H4 (H-MP-4)** — `charge.refunded` with `amount=0` divides by zero → NaN proportion → fails CHECK constraint → silent dead-letter. Combine with H3 for silent data loss. (`apps/api/src/routes/webhooks.ts:688-740`)

## Auth

- **H5 (H1)** — Account-purge cron writes no `audit_logs` row for the actual hard-delete. The GDPR-relevant erasure event exists only in transient observability logs. (`apps/api/src/services/account-purge.service.ts:82-145`)
- **H6 (H2)** — OAuth account-delete requires no server-side re-authentication. The mobile UI does the dance; the API trusts it. A stolen token can permanently delete an OAuth user's account with one HTTP call. (`apps/api/src/routes/users.ts:592-700`)
- **H7 (H3)** — `/refresh` and `/logout-all` silently swallow blacklist failures. `/logout` does the right thing (returns 503) — the same Redis hiccup during refresh leaves old access tokens alive for up to 1h.
- **H8 (H4)** — Concurrent-login race throws Postgres 23505 (unique violation on `refresh_tokens`) because refresh tokens lack a `jti` claim. Auth.test.ts:243 even has a `setTimeout(1100)` to dodge it.
- **H9 (H6)** — `/users/me/change-email` skips the `email_verified` precondition. **Account-takeover bypass** — register victim's email (no verify), change to attacker's, verify on the new side, and the account is attacker-controlled.

## Database

- **H10 (H2)** — Pool config lacks `application_name` and `keepalives`. A crashed migration runner can leak an advisory lock for ~2h (Linux TCP timeout) before the connection drops; ops can't tell which process holds the lock.
- **H11 (M10)** — `cleanup_old_audit_logs()` is a 2027 time-bomb: it deletes `info` rows older than 1 year, but **deleting any row from the hash chain breaks every subsequent verification**. First triggering ~2027-04-25.
- **H12 (H4)** — `decryptToken` walks all candidate keys but exposes no telemetry on legacy-key hits. Operators have no signal of "how many rows are still on the old key" — the rotation runbook can't tell when it's safe to drop a legacy entry.
- **H13 (H5)** — Audit-chain payload includes `created_at::text` which is TZ-sensitive. Verifier session with different `TimeZone` GUC produces different strings → every chain row appears broken.
- **H14 (H7)** — `request_idempotency` cleanup deletes the entire trailing day in one statement; under sustained replay-flood the cleanup tx blocks the pool for minutes.

## Mobile sync

- **H15 (H-MS-1)** — `redactSensitive` doesn't cover refresh tokens, OAuth state, activation codes, Apple nonces. If any future log line ever quotes a request body, those values leak.
- **H16 (H-MS-2)** — `enqueueChange` cap-check is non-transactional. Concurrent enqueues can exceed the 500-cap. Eviction is silent — user's optimistic UI shows the change applied but the queue row is gone.
- **H17 (H-MS-4)** — `auth_repository.signOut` reads via a duplicate `FlutterSecureStorage` with `KeychainAccessibility.first_unlock` (NOT `first_unlock_this_device`). On iOS these are separate keychain items. **Logout body is always empty** — the server can't revoke that specific refresh token. Dies on natural expiry only.
- **H18 (H-MS-5)** — `_processEntry` marks parked-conflict entries as `synced` (semantically wrong). Anything analyzing the queue history thinks the write succeeded when it was actually deferred to manual resolution.
- **H19 (H-MS-6)** — Optimistic-create offline uses `id: ''` so two offline creates collide on the empty key. UI selectors collapse the duplicates until refresh.

## Mobile features

- **H20 (H1)** — Mobile delete-account copy contradicts marketing 7-day grace policy (= **C1/C2** above).
- **H21 (H2)** — F124 reverse drift in `add_warranty_purchase_screen.dart:213`: `double.tryParse` validator + `Money.parseToDouble` submit. Inverse of the F124 fix; same pattern, opposite direction.
- **H22 (H3)** — Date pickers in 5 screens never normalize to local-midnight (F005 regression): edit_item, create_claim, log_maintenance, add_warranty_purchase, home_detail.
- **H23 (H4-H6)** — Three controller/notifier leaks: `profile_screen.dart` change-email dialog, `customize_schedule_screen.dart` add-task dialog, `email_scanner_screen.dart:_ScanProgressController.stage`.
- **H24 (H7)** — `receipt_scan_screen.dart:_saveItem` early-returns silently when user/home is null with no user feedback.
- **H25 (H8)** — `/referral/:code` is a routing dead-end for already-authenticated users — code is stashed in SP forever, never read after sign-up.

## Partner dashboard

- **H26 (H1, H2)** — `clearAuthCookies` and `redirectToLogin` don't delete `hk_role_check`. Stale role-cache cookie can drive middleware decisions on next request after logout (30s TTL).
- **H27 (H3)** — `/api/auth/refresh` 401-failure paths don't call `clearAuthCookies`. Inconsistent contract.
- **H28 (H4)** — Proxy buffers full request and response with no byte-cap. DOS surface — a logged-in malicious actor can send a 100 MB POST and the proxy buffers it.

## Email scanner

- **H29 (C7)** — All six OAuth `fetch()` calls have no HTTP timeout. A hung Google/Microsoft endpoint blocks the request handler indefinitely.
- **H30 (C8)** — Server-side state validation does not exist — it's mobile-only. CSRF defense for OAuth depends entirely on the mobile client behaving correctly.
- **H31 (C10)** — DKIM parser doesn't anchor to Gmail's `mx.google.com` authserv-id, doesn't verify `header.i=` alignment with `header.from=`, and doesn't require DMARC. **An attacker who injects an `Authentication-Results: foo.com; dkim=pass` header at the start of a message defeats the gate.**
- **H32 (H1)** — `redirectUriAllowed` uses `startsWith`. `https://staging.havenkeep.app/oauth-callback.attacker.com/abc` matches. Provider rejection is the primary defense; the API should not be the second-weakest link.
- **H33 (H2)** — Scope downgrade is checked at exchange time but never on subsequent refreshes. If a user revokes the read scope at Google but doesn't disconnect from HavenKeep, the next scan silently throws a generic error.
- **H34 (H4)** — `email_scanner_review_queue` has no cleanup policy. Unbounded growth.
- **H35 (H5)** — `cancelScan` only flips DB status; the in-process scan keeps burning OpenAI for up to 5 more minutes.
- **H36 (H6)** — Outlook never requests `internetMessageHeaders` from Graph API → DKIM is permanently unknown for Outlook → every Outlook receipt ends up in the review queue regardless of trust.
- **H37 (H8)** — `extractReceiptData` JSON-parse failures silently drop the receipt. User paid for the OpenAI call and got nothing.

## Marketing

- **H38 (H1)** — TLS-version drift: privacy says "1.2+", security says "1.3". Internal contradiction.
- **H39 (H2)** — Privacy claim "receipts and photos encrypted in object storage" un-verifiable from code — no SSE header on any `minioClient.putObject` call. Bucket-level default encryption must be enabled on MinIO; that's an ops config change not in this repo.
- **H40 (H3)** — Privacy + security claim "daily encrypted backups, 30-day retention, weekly restore drills" has no corresponding script in this repo.
- **H41 (H4)** — Security page advertises a bug bounty that doesn't exist (`security.astro:220`). A public claim of a bounty creates an implicit contract.
- **H42 (H5)** — Canonical URL hardcoded to `havenkeep.com` in `Layout.astro:58-63`. Staging emits prod canonical, breaking SEO + link previews.

---

# Part 3 — Themes worth calling out

## 7-vs-30-day deletion drift (Cluster A) — confirmed across 3 agents

The single most-confirmed finding. Marketing legal pages say 7 days, mobile UI says permanent (no grace), code does 30 days. Three agents independently flagged this from different angles.

**Resolution:** code is correct. Update marketing legal pages and mobile UI to say 30 days. See C1, C2, C3, C4 above.

## TLS pinning — privacy-policy-grade misrepresentation (Cluster B)

Two agents independently caught it. The privacy policy promises pinning; no code path implements it. This is a **regulatory issue** — privacy claims are contracts. Either implement or remove the sentence before staging-customer access.

## OAuth bypasses (Cluster C)

`/auth/google` and `/auth/apple` are missing three checks `/auth/login` performs (MFA, soft-delete, suspended). The fact that all three live in the same handler family suggests a single audit pass on those handlers would catch all of them. Worth doing before any external user (partner, beta tester) signs in via OAuth.

## Money paths

**No critical findings here** — the heavy audit work shows. Three-phase gift create, three-phase warranty cancel, full+partial commission clawback, on-demand payouts all have appropriate idempotency keys, Stripe-outside-DB-tx ordering, and replay-safe terminal-state guards. The Highs are recovery gaps (dead-letter has no alert; stuck `cancelling` rows have no recovery cron) and money-formatter drift (the centralized `money.ts` exists; several call sites went rogue back to floats).

## Audit chain

Three Criticals at the chain integrity layer (C18, C19, C20) plus a 2027 time-bomb (H11) — the cleanup function isn't compatible with the chain feature. The chain is the system's tamper-evidence contract; these gaps undermine it. C18 (regex bug) is trivial to fix. C19/C20 (UUID ordering, audit_cleaner UPDATE exemption) require migrations.

## Mobile sync stack

Six Criticals concentrated here. The pattern: each individual choice was reasonable in isolation (iCloud-backed Documents dir; `first_unlock_this_device` keychain; sealed-class catch; 7-day stale eviction) but the combinations have data-loss paths. Worth treating as one cohesive change rather than 6 individual fixes.

## Email scanner

Four Criticals — cost runaway (C21, C22), Outlook integration silently dies (C23), false revocation claim (C24). C21 + C22 together are a real cost-runaway scenario; an attacker with a free account could probably run hundreds of dollars of OpenAI per day before the manual rate limit catches them. Worth fixing before any partner-managed account uses the scanner.

---

# Part 4 — Verified-correct (worth keeping in the audit so it's not all bad news)

Items multiple agents confirmed are sound:

## Money paths
- Three-phase gift create with reverse-compensation refund on phase-3 failure
- `claimWebhookEvent` race-safety with explicit FOR UPDATE row lock
- Commission clawback ledger preserves original earning row; CHECK constraints (`chk_partner_commissions_reversal_shape`, `chk_partner_commissions_paid_has_transfer`) enforce shape
- 30-day auto-approve cron correctly excludes reversal-sibling rows + KYC-incomplete partners
- `mig 097` immutable trigger CASCADE relaxation (allows parent-claim CASCADE delete; still blocks UPDATE)
- Stripe webhook signature verification with raw-body BEFORE any DB work
- RevenueCat webhook auth via constant-time SHA-256 comparison
- Stripe transfer idempotency keys; `off_session: true` paired with explicit `payment_method`
- Stripe SDK pinned at `^21.0.1` (matches CLAUDE.md note about v22 CJS-typing regression)

## Auth
- Refresh-token rotation atomicity (DELETE...RETURNING)
- Refresh-token storage uses keyed HMAC (no plaintext)
- bcrypt SHA-256 pre-hash applies on register, login, change-password
- Apple Sign-In nonce store correctly rejects replays (Redis SET NX EX with DB fallback)
- Apple `aud` array verification with algorithm pinning + `alg: none` rejection tested
- Google `aud` array verification with `email_verified` enforcement
- TOTP comparison is constant-time (otplib's `verifySync`)
- Backup codes are single-use, atomically consumed
- Generic 401 consistency for user-not-found / deleted_at / suspended (S-M1)
- `invalidateUserCache` called on every auth-state-mutating route

## Database
- Mig 098 `ALTER TYPE … ADD VALUE` works inside transaction on PG12+
- Mig 087 `webhook_events.id INT4 → BIGINT` correctly handles sequence + column type
- Mig 092 partners is_active/status invariant CHECK is correct
- Mig 030a/030b deliberate two-file split for `ALTER TYPE` + reference
- Schema-version tracking via SHA-256 with drift warnings
- `oauth-encryption.ts` IV uniqueness + GCM auth correctness

## Mobile sync
- Sealed switch in offline-sync replay covers all 9 ApiException subtypes
- Idempotency key minted at enqueue, not at retry
- Single-flight refresh deadlock-safe
- `_bytesToHex` zero-out after PRAGMA key
- No legacy `path:` API usage in mobile codebase
- No TODO/FIXME/HACK markers in audited files
- `KeychainAccessibility.first_unlock_this_device` on auth tokens AND DB key
- Auth-gated connectivity listener (sync only runs when authenticated)

## Mobile features
- F005 anchor applied in quick_add, manual_entry, receipt_scan
- F124 (Money.parseToDouble) applied in create_claim, manual_entry, quick_add, edit_item (only `add_warranty_purchase_screen.dart` is wrong)
- `PopScope` consistently used (no `WillPopScope`)
- AnimationControllers disposed correctly
- Confetti pause on backgrounding
- Premium screen reads live RevenueCat offering with fallback

## Partner dashboard
- Proxy strips cookies + enforces header allowlist + double-submit CSRF + same-origin guard + response-header reduction
- Proxy's `out.delete('cookie')` after allowlist iteration is the right idiom
- Edge middleware uses API-derived `hk_role_check` (Ch10-W008) instead of unverified JWT claims
- Logout is CSRF-checked (S2-N)
- `formatCurrency` accepts string OR number (no float drift on `DECIMAL` columns)

## Email scanner
- AES-256-GCM IV uniqueness (12 random bytes per encryption)
- Multiple email accounts per user (UNIQUE on `(user_id, provider, provider_email)`)
- Outlook PKCE-omission (correct given API holds secret)
- Mobile state generation via `Random.secure()` 32 bytes
- Mobile query-vs-fragment parsing
- `OPENAI_API_KEY` missing returns 503 cleanly
- `completion_message` populated on success

## Marketing
- Caddy CSP (no `unsafe-inline` on script-src; `frame-ancestors 'none'`; HSTS+preload; strict referrer + permissions)
- AASA file content + routing + Caddy `Content-Type` override
- assetlinks.json (both `handle_all_urls` + `get_login_creds` relations; upload-key SHA-256 wired; Play-signing placeholder still present which is correct pre-launch)
- Mobile router `/gift/:code` + `/referral/:code` exactly matches AASA scope
- OG-image coverage 16/16
- Every `target="_blank"` has `rel="noopener noreferrer"`
- bcrypt cost 12 verified across all `bcrypt.hash` calls
- Free-tier limit (5) consistent across marketing/api_client/api config
- Partner tier prices ($99/$149/$249) consistent
- No advertising SDKs in pubspec.yaml

---

# Part 5 — Suggested fix order

1. **Cluster I (C26, C27)** — rotate `.env.staging` secrets first. Everything else can wait; a leaked Firebase service-account private key cannot.
2. **Cluster H (C25)** — delete the `next.config.js` rewrite footgun. One file, one block, removes a major bypass surface.
3. **Cluster C (C6, C7, C8)** — three OAuth handler fixes. Same family, one pass, covers MFA bypass + soft-delete bypass + suspended bypass.
4. **Cluster B (C5)** — implement TLS pinning OR delete the privacy claim. Required before TestFlight either way.
5. **Cluster A (C1, C2, C3, C4)** — deletion drift. Update marketing copy + mobile UI + add recover-account screen. The contract is currently false in three places.
6. **Cluster G (C21, C22, C23, C24)** — email-scanner cost/security. Outlook in particular is silently broken (refresh token, DKIM, revoke).
7. **Cluster D (C9, C10, C11, C12)** — mobile gift activation flow. Partner gifts can't currently be redeemed via deep link by new users.
8. **Cluster E (C13–C17)** — mobile sync data-loss paths. One cohesive change.
9. **Cluster F (C18, C19, C20)** — audit chain integrity. C18 is trivial; C19 and C20 require migrations.
10. **Highs** — work through Part 2 by surface, in agent-report order.

Tracking each cluster as a single PR / task is more efficient than 27 individual tickets.

---

# Appendix: where each agent's full report lives

- [`docs/audit-runs/01-auth-accounts.md`](audit-runs/01-auth-accounts.md) — auth + accounts (6C / 7H / 9M / 7L)
- [`docs/audit-runs/02-money-paths.md`](audit-runs/02-money-paths.md) — money paths (0C / 4H / 8M / 5L)
- [`docs/audit-runs/03-database-migrations.md`](audit-runs/03-database-migrations.md) — DB + migrations (3C / 7H / 12M / 6L)
- [`docs/audit-runs/04-mobile-sync-storage.md`](audit-runs/04-mobile-sync-storage.md) — mobile sync + storage (6C / 8H / 8M / 4L)
- [`docs/audit-runs/05-mobile-features.md`](audit-runs/05-mobile-features.md) — mobile feature screens (4C / 10H / 17M / 15L)
- [`docs/audit-runs/06-partner-dashboard.md`](audit-runs/06-partner-dashboard.md) — partner-dashboard (1C / 5H / 15M / 12L)
- [`docs/audit-runs/07-email-scanner.md`](audit-runs/07-email-scanner.md) — email scanner + OCR (4C / 8H / 5M / 8L)
- [`docs/audit-runs/08-marketing-cross-cutting.md`](audit-runs/08-marketing-cross-cutting.md) — marketing + cross-cutting (4C / 5H / 5M / 2L)

Per-agent reports include "Verified-clean" and "Out-of-scope-noticed" sections that are not duplicated in this consolidated report. Read them when planning fixes.
