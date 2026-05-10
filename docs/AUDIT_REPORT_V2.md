# HavenKeep — End-to-End Audit Report v2 (Deep)

**Date:** 2026-05-10
**Method:** 12 agents, per-file deep-dive against explicit 50-100 item checklists. SQL + crypto + on-wire layer reading. Code excerpts pasted, not just file:line. Per-agent reports in [`docs/audit-runs-v2/`](audit-runs-v2/).

---

## Headline counts — v2 vs v1

| | v1 (shallow) | v2 (deep) |
|---|---|---|
| **Critical** | 27 | **~60** |
| High | 51 | **~110** |
| Medium | 76 | **~170** |
| Low | 60 | **~110** |
| **Total** | ~214 | **~450** |

V2 found **2.1×** the bug count of v1 by reading code line-by-line, pasting actual excerpts, walking SQL invariants, and adding 4 new surfaces. Multiple v1 findings were **wrong** (false positives) and have been struck. Multiple v1 verified-clean items turned out to be broken on closer reading.

This consolidated report leans on the per-agent reports for full citations. Numbering is fresh (`V2-C1`, `V2-C2`, …); the original per-agent IDs are preserved in parens for traceability.

---

# Part 1 — Tier-zero criticals

These are the bugs you should triage *before* anything else. Each is either: (a) a privacy-policy lie, (b) a money bug, (c) an audit-chain integrity hole, or (d) a flow that's broken end-to-end and nobody noticed.

## Tier-zero #1 — `/auth/verify-email-change` is broken for everyone

**Source:** Agent 1 (auth deep) — C-AUTH-V2-1

`apps/api/src/routes/auth.ts:1216-1225` updates `email_change_pending = NULL, email_change_target = NULL`. Verified against `schema.sql` and every migration through 100: **those columns do not exist in `users`**. They are virtual columns derived via sub-SELECT in `users.ts:57-65`. **Every change-email confirmation throws PG `42703` and returns 500.**

The flow has been broken since written. The marketing-site verify-email-change page faithfully posts to `/auth/verify-email-change` → API throws → user sees an error. Fix is to drop the two SET clauses entirely.

**Confidence:** Very high. Verified by reading the schema. v1 missed this because it didn't cross-check the SQL.

## Tier-zero #2 — Audit chain is theater (API role owns the table)

**Source:** Agent 3 (DB+crypto deep) — C4

Mig 002's GRANT block is commented out. The API role is the **table owner** of `audit_logs`. **An attacker with API credentials (DB-level compromise — same role the API uses) can run `DROP TRIGGER trg_audit_logs_immutable; UPDATE audit_logs SET ... WHERE id = ...; CREATE TRIGGER trg_audit_logs_immutable ...;`** The hash-chain "immutability" guarantee evaporates. Compounds with:
- v2 DB H1 — trigger uses `current_user` not `session_user`; `SET ROLE audit_cleaner` inside a tx bypasses both UPDATE and DELETE blocks.
- v2 DB C2 — Mig 080→082 dropped the `FOR SHARE` lock hint; advisory lock alone is not sufficient under long outer txs (MVCC snapshot at outer-tx start can read stale predecessor → forked chains).
- v2 Crons F-E-1 — chain break emits one `logger.error` and nothing else. No `audit_logs` row, no email, no page. **Nobody knows when the chain breaks.**

The chain is the single tamper-evidence contract for the entire system, and it has four independent defeats.

## Tier-zero #3 — Three ways MFA doesn't work

**Source:** Agents 1, 6, and 11 (auth, dashboard, email/admin)

1. **Auth C-AUTH-V2-2** — MFA challenge token doubles as a valid access token (v1 finding still unfixed). After step 1 of MFA, the partial token authenticates every protected route.
2. **Auth C-AUTH-V2-6** — `/auth/google` and `/auth/apple` skip the MFA check (v1 finding still unfixed).
3. **Dashboard V2-C3** — Partner dashboard has zero MFA UI. **Any partner or admin who turns on TOTP via the mobile app immediately loses dashboard access** and sees "email or password is incorrect" instead of "MFA required."
4. **Auth H-AUTH-V2-20** — `mfa.test.ts` does not exist. **Zero automated coverage** of MFA enrollment / verify / challenge / disable. The mocked otplib in `__mocks__/otplib.cjs` returns `{valid: true}` for every code, so **the existing tests would pass even with broken MFA**.

MFA is shipped. MFA does not work in any meaningful sense. If a single user turned it on, three different things break.

## Tier-zero #4 — Money bugs (4 confirmed Criticals)

**Source:** Agent 2 (money deep)

1. **V2-C-MD-1 — Phantom refunds.** `warranty-purchases.service.ts:402-466` writes `refund_amount_cents` + `refunded_at=NOW()` even when Phase 2 Stripe call is skipped (no `stripe_payment_intent_id`). UI says "refunded $X"; **Stripe sees nothing**. Finance reconciliation diverges silently.
2. **V2-C-MD-2 — Gift create has no idempotency middleware.** The most expensive mutating call in the system ($99-$249/charge) lacks `writeRateLimiter` AND `idempotency`. Stripe's per-gift `idempotencyKey: gift-<id>` doesn't help because two requests create two distinct gift rows. **Double-click → two charges land.**
3. **V2-C-MD-3 — `proratedRefundCents` does float math.** `Math.round(priceDollars * 100 * fraction)` while the same file imports `dollarsToCents`. Pattern violation, off-by-one cent on edges.
4. **V2-C-MD-4 — Clawback rounds in dollars not cents.** `Math.round(Number(row.amount) * proportion * 100) / 100`. After certain partial-refund sequences, **commission ledger sums to non-zero forever** (off by $0.01).

v1 said "no Criticals" on money paths. v1 was wrong.

## Tier-zero #5 — Account deletion is broken at five layers

**Source:** Agents 1, 5, 8, 10, 12 — convergent finding

Already established in v1 that the cooling-off window has a 7/30/permanent text drift. v2 reveals the actual code is broken much deeper:

| Layer | Bug | Source |
|---|---|---|
| API: `DELETE /me` | No `WHERE deleted_at IS NULL`. **Retried delete slides the purge clock 30 days every time** | Auth C-AUTH-V2-7 |
| API: recovery window | Password user has 1h effective recovery (v1 C4) — token expires before user can recover | Auth (v1 confirmed) |
| API: cron + recover race | Neither side takes `FOR UPDATE`. Recover landing during cron's harvest leaves a hollowed-out user | Auth H-AUTH-V2-1/-21 |
| API: hard-delete partner CASCADE | `partners → partner_gifts → partner_commissions` CASCADE. **All historical commission records evaporate.** IRS / 1099-NEC retention violation. | Crons F-P-5 |
| API: notification history | `notification_history.user_email_at_send` (mig 044) never populated by the purge tx. Only warranty rows get denorm-email | Crons F-B-7 |
| API: push tokens | `user_push_tokens` not deleted on soft-delete (only hard-delete via FK CASCADE). User receives notifications for 30 days while in cooling-off. | Push A6 |
| API: push tokens on logout | Logout doesn't delete push tokens either. Signed-out user still gets pushes for ~60 days. | Push A5 |
| API: OAuth integrations | Revoke runs OUTSIDE the soft-delete tx. **Revoke failure leaves OAuth tokens fully usable for 30 days post-deletion.** | Auth H-AUTH-V2-14 |
| API: OAuth at provider | `revokeIntegration` never POSTs to provider's revocation endpoint. The OAuth grant remains active at the provider for ~6 months. | Email scanner C4 |
| API: hard-delete audit log | Account-purge cron writes zero `audit_logs` rows on hard-delete. **GDPR-relevant erasure event has no immutable record.** | Crons F-B-10 / Auth H-AUTH-V2-21 |
| Mobile: ACCOUNT_PENDING_DELETION code | API returns the specific code; mobile silently treats it as a generic error. **A user mid-grace can never cancel deletion in-app.** | Mobile features C5 |
| Mobile: deletion screen copy | "permanent / cannot be undone" — no grace period mentioned. Contradicts privacy policy. | v1 confirmed |
| Marketing: privacy.astro | Says 7-day grace; code does 30 | v1 confirmed |
| Marketing: delete-account.astro | Says 7-day grace; code does 30 | v1 confirmed |
| Marketing: privacy → "Settings → Privacy → Telemetry" | Promised opt-out screen does not exist. | Marketing C3 |
| Marketing: privacy → "Settings → Data → Export" | Promised data-export screen does not exist. Only `/api/v1/items/export.csv` (no warranties, no documents). **GDPR Art. 20 violation.** | Marketing C4 |

That's **15 layers of brokenness** for one promised feature. Pre-launch, fix this end-to-end as a single workstream.

## Tier-zero #6 — Privacy-policy lies (verified)

**Source:** Agents 8, 10 — convergent finding

The privacy policy makes verifiable claims that the code does not deliver:

1. **TLS pinning** — Privacy says "Mobile clients additionally pin the leaf certificate." Code: zero pinning wired anywhere; `client.dart:202-217` only documents the recipe in a doc-comment. (Marketing C2 / Mobile-sync C-MS-1) Also: "leaf certificate" is wrong — the doc-comment describes SPKI pinning. *And* the lie has metastasized: `scripts/build-og-image.cjs:86` tagline says "TLS pinning" so even fixing the policy text leaves the lie in social-share previews. (Marketing C5)
2. **OAuth revocation** — Privacy says "we delete OAuth tokens on the server when you remove the integration." Code: `revokeIntegration` only NULLs the local cache, never POSTs to Google's revoke endpoint. Mobile UI's "we revoke OAuth tokens on the server" microcopy is **materially false**. (Email scanner C4)
3. **Telemetry opt-out** — Privacy promises "Settings → Privacy → Telemetry" toggle. Mobile: no such screen exists. Crashlytics is unconditionally enabled in release. (Marketing C3 / Push P1)
4. **Data export** — Privacy promises "Settings → Data → Export." Mobile: no such screen. Only `/api/v1/items/export.csv` exists (items only, no warranties, no documents). GDPR Art. 20 violation. (Marketing C4)
5. **Sub-processor list omits OpenAI and DigitalOcean.** Every Premium-uploaded receipt photo and every email-scanner body goes to OpenAI Vision. Not in the policy. **GDPR Art. 28 violation.** Also missing DigitalOcean (the actual hosting platform), Loki/Grafana. (Marketing C2)
6. **Cookies page is fabricated.** `cookies.astro` claims Intercom, Cloudflare, Google Analytics, retargeting pixels, social-media cookies, a cookie-consent banner, "Cookie Settings" footer link — **none of these exist.** (Marketing C1)
7. **Receipts encrypted at rest** — Privacy says SSE on object storage. API code: `minioClient.putObject(...)` calls in `uploads.ts:128-137` and `documents.ts:222-232` have no `x-amz-server-side-encryption: AES256` header. Server-side encryption depends entirely on whether the shared MinIO is configured with KES — invisible from this repo. (Push J7 / Marketing v1 H2)
8. **Cancel emails honor unsubscribe** — Three transactional templates claim Gmail/Yahoo one-click List-Unsubscribe-Post compliance, but the URL is a logged-in `/settings/notifications` page. Gmail will treat unsubscribe attempts as failures → deliverability degradation. (Email/admin H1)

Pre-launch, fix the privacy policy OR the code. Privacy claims are contracts. Most of these are GDPR-grade exposures. The cookies page (C1) and TLS-pinning (C2/C5) are the worst because they're *fabricated*, not just out-of-date.

## Tier-zero #7 — Plaintext secrets in working tree

**Source:** v1 marketing C3 (re-confirmed)

`/.env.staging` (gitignored) carries Postgres password, JWT secret, refresh-token secret, Redis password, both MinIO keys, and **the full RSA private key** for the Firebase service account (`firebase-adminsdk-fbsvc@...`). The file IS gitignored (verified) so not in commits, but the working tree on every developer machine is itself a leak vector. **Treat as compromised. Rotate everything.** Especially the Firebase service-account key (revoke in GCP IAM; reissue).

## Tier-zero #8 — Marketing fabrications + tech-stack lies

**Source:** Agent 8 (marketing deep)

- **Cookies page is fabricated** (C1, listed above)
- **`licenses.astro` lists React Native + Expo as core deps. The app is Flutter.** The careers job description doubles down on "React Native, TypeScript, Node.js." (C6)
- **`github.com/havenkeep` and `twitter.com/havenkeep` social links are unverified — possibly squatted.** (C7)
- **No `.env.example` for `apps/marketing`.** New devs silent-fail contact + newsletter + verify-email-change. (C8)

These are not bugs in the code; they are bugs in the public-facing claims. They are equally embarrassing.

## Tier-zero #9 — Platinum partner tier perk is API-unfulfillable

**Source:** Agent 8 (marketing M8)

`partners.astro` Platinum tier promises **"2-year Premium gift."** `validators/partners.validator.ts` caps `premiumMonths.max(12)`. **Platinum's headline perk is physically unfulfillable by the API.** A Platinum partner pays $249, the homebuyer gets 12 months not 24. v1 money M-MP-8 caught the schema mismatch but didn't notice it's the marketing tier's headline feature.

---

# Part 2 — High-severity by theme

## Theme A — Audit chain integrity (4 distinct defeats)

| | What | Source |
|---|---|---|
| 1 | API role is table owner; can `DROP TRIGGER ... ; UPDATE; CREATE TRIGGER` (= tier-zero #2) | DB C4 |
| 2 | `current_user` not `session_user` — `SET ROLE audit_cleaner` bypasses | DB H1 |
| 3 | UUID PK + microsecond `created_at` → verifier false positives under load | DB v1-C19 |
| 4 | `verify_audit_chain()` skips `this_hash IS NULL` rows; v1's claim partially wrong but operational concern is worse — no cron, no alert | DB C1 |
| 5 | TZ-sensitive `created_at::text` in payload | DB v1-H13 |
| 6 | `cleanup_old_audit_logs()` 2027 time-bomb — first deletion breaks the chain | DB v1-M10 |
| 7 | Audit-chain break logs `logger.error` only, nothing else | Crons F-E-1 |

## Theme B — Idempotency / replay safety

- **Money C-MD-2** — Gift create has no idempotency middleware (= tier-zero #4)
- **Middleware F-08** — Idempotency middleware has no concurrent-request locking. Two simultaneous same-key requests both miss the SELECT, both run, second client gets divergent response.
- **Middleware F-22** — Idempotency body-hash uses non-deterministic `JSON.stringify` (key order matters). Same logical body hashes differently → idempotency miss → duplicate execution.
- **Auth H-7 / DB v1-H7** — `request_idempotency` cleanup uses unbounded `DELETE`. No chunking. Holds giant lock under DoS-style replay.
- **DB H7** — Idempotency middleware hashes only `req.body`, not URL/query. Reused key across `DELETE /items/A` and `DELETE /items/B` with same body → wrong response replayed. Authorization risk.
- **Money H-MP-3** — No retry/alert for `webhook_events.status='dead_letter'`. v1 finding, still unfixed.
- **Money H-MD-8** — `charge.refunded` and `charge.failed` don't call `isEventInOrder`. Out-of-order Stripe events can replay refunds incorrectly.
- **Crons F-H-1/2** — Webhook dead-letter cron does not exist. Dead-lettered events live forever (with `processed_at IS NULL` they survive the 7-day sweep) but nobody alerts/retries.

## Theme C — Mobile sync data loss (8 paths confirmed)

The original v1 cluster + v2 deepening:

- **C-MS-1** — TLS pinning documented, never wired (= tier-zero #6)
- **C-MS-2** — `refreshAccessToken` clears tokens on ANY non-200. v1 still unfixed.
- **C-DEEP-1** — `_withAutoRefresh` doesn't clear tokens on retried-401-after-refresh. Locks user in refresh-then-401 loop.
- **C-DEEP-7** — Bootstrap race: `clearTokens` before `setActiveDatabaseUser` opens previous user's queue/conflicts file. Different-user data leak.
- **C-DEEP-4** — Cold launch via push before keychain unlock → token wipe. iOS-specific.
- **L7→C** — Captive portal returning HTML → JSON parse fails → C-MS-2 fires → tokens wiped. Concrete real-world trigger.
- **C-MS-3** — 7-day stale eviction wipes FAILED queue entries.
- **C-MS-4** — SQLCipher DB in iCloud-backed dir, key in device-bound keychain → restore corrupts user.
- **C-MS-5** — `_parkUpdateConflict` loses local edit on preflight 404 / network error.
- **C-MS-6** — ~30 of 32 enum factories silently coerce. v2 says ~27.

The deepest one not in v1: **enum drift on `OfflineAction`**. An unknown action coerces to `create_item`. So a server-added `delete_archive` action arrives at an old mobile binary, gets replayed as a `create_item`, and the user's archive deletion **silently becomes a duplicate item creation**.

## Theme D — Email scanner cost / DKIM / Outlook

- **C1** — Outlook scans bypass OpenAI budget cap entirely (missing `userId` parameter)
- **C2** — Budget checked once per scan; single scan burns ~500 OpenAI calls
- **C3** — Microsoft refresh-token rotation dropped → Outlook integrations die in ~24h
- **C4** — Revoke doesn't call provider endpoint
- **DEEP-C1** — No anti-prompt-injection guard on scanner's OpenAI call (`receipts.ts` has one; scanner doesn't). Stacks with DKIM hole.
- **DEEP-H6** — DKIM signing-identity not cross-checked against `From:` domain. **Structural reason v1 C10 is security theater** even when the regex matches.
- **DEEP-H4** — No Gmail/Outlook pagination. Each retailer query silently caps at 50 messages; rest skipped.
- **DEEP-M2** — Revoked rows retain encrypted refresh token forever. Combined with DB H4 (no AAD), an attacker with DB write access can swap a revoked token onto an active row.

## Theme E — Push notifications + Crashlytics privacy

All from agent 10 (push deep):

- **A5** — Push tokens not deleted on logout. Signed-out user gets pushes for ~60 days.
- **A6** — Push tokens not deleted on soft-delete. User in cooling-off gets pushes for 30 days.
- **B6** — `messaging/invalid-argument` (overloaded for bad-token OR bad-payload) treated as dead-token signal. **Single payload-too-large bug → every user's push tokens deleted.**
- **P1** — No Crashlytics opt-out path; privacy-policy lie #4.
- **J7** — MinIO `putObject` has no SSE header; SSE depends entirely on bucket-level config in shared infra (privacy-policy lie #5).
- **B4** — iOS `aps-environment` may ship as `development` to TestFlight (push silently broken).
- **J4** — HEIC magic-byte validator accepts MP4/MOV. Image upload accepts videos.
- **M2** — CSV export doesn't escape Excel formula prefixes `=/+/-/@`. CSV injection.
- **G9 / H6** — Universal Links / App Links declared only for production `havenkeep.com`, not staging. Staging deep links don't work.
- **E1** — 7 notification types bypass preference gates entirely.

## Theme F — Crons + observability

All from agent 12 + cross-confirms from agent 9:

- **F-A-1** — `DIGEST_FLUSH_LOCK` and `PARTNER_COMMISSION_AUTO_APPROVE_LOCK` are both `93422878`. Auto-approve cron silently no-ops on any day digest is mid-flight at 09:00 UTC. (Confirms middleware F-15.)
- **F-A-2** — Boot at 09:00:00.001 UTC computes `next = 09:00 today`, then `<=` advances to tomorrow. **The entire daily cron is skipped for that day.** Pod restart at the wrong second = no notifications, no purge, no commission auto-approve, no audit-chain verify.
- **F-C-1** — Warranty-expiring cron dedups on 24h. Warranty 30 days from expiry triggers same notification daily for 30 days. "first_reminder_days" is a misnomer.
- **F-O-1** — Notification cron is N×serial, no batching. 10K reminders → throttled by FCM → some don't deliver.
- **F-P-3** — Orphan MinIO objects never reaped. Failed upload + DB rollback leaves the object forever.

The diagnosis: "**The mechanism of every cron is correct. The problem surface is observability + escalation — silent failures are invisible until users complain.**"

## Theme G — Auth surface deepening

- **C-AUTH-V2-3** — JWTs never set `iss` / `aud` claims. Token from one HavenKeep environment is reusable in another.
- **C-AUTH-V2-7** — `DELETE /me` no `WHERE deleted_at IS NULL` (= tier-zero #5)
- **C-AUTH-V2-8/-10** — Change-email stores `metadata->>'new_email'` un-normalized; existence check uses `LOWER(email)`. Mismatch → silent 409.
- **H-AUTH-V2-5** — No refresh-token-family revocation. Token-reuse just 401s, doesn't kill family or alert.
- **H-AUTH-V2-11** — `/login` rate limit is per-IP only. **Botnet credential stuffing is unbounded per account.** Compounds with Middleware F-03 (rate limiters fail-OPEN to in-memory; in multi-replica prod, budget multiplies by replica count).

## Theme H — Money paths deepening

- **C-MD-1..4** — Already in tier-zero #4
- **H-MD-1** — `PARTNER_TIER_PRICING` env override has no min validation. Operator typo `0.99` instead of `99` silently undercharges every gift forever.
- **H-MD-5** — Partner payouts-summary `paid_lifetime` doesn't subtract reversal rows. Partner sees $14.85 paid even after a $-14.85 sibling. **Two endpoints contradict each other** (analytics page nets correctly).
- **H-MD-7** — Reversal rows write `commission_rate=0`. Forward-incompatibility timebomb.
- **H-MD-11** — No defense against Caddy compressing webhook body. Stripe signature fails silently → dead-letter (compounds with H-MP-3 no-alert).
- **H-MD-12** — `STRIPE_DECLINE_MESSAGES` reads `error.code` first. `card_declined` masks specific `decline_code`. Users never see the actionable map (insufficient_funds, etc.).

## Theme I — Partner dashboard deepening

- **C2** — `SAFE_SEGMENT` regex accepts literal `..`. **Path-traversal bypass of the proxy.** v1 praised the proxy as "in good shape"; the regex right at the top accepts `..`.
- **C3** — Dashboard login flow doesn't handle MFA at all (= tier-zero #3)
- **H9** — `fetchFreshRole` swallows 5xx and falls back to unverified JWT for role decisions. Exactly what H-A8 was supposed to fix.
- **H10** — `serverApiClient` doesn't forward `Idempotency-Key`. Defeats Ch10-W021 single-flight discipline.
- **M17** — `payouts.openTaxDocs` opens `window.open(res.data.url)` with no URL validation. Server-controlled URL → open redirect.
- **M21** — Audit log table renders `metadata` JSON wholesale **with no PII sanitization** despite the dashboard already having a `sanitize` redactor. Admin watching audit logs can see passwords / tokens that landed in metadata.

## Theme J — Email service + admin

- **Admin hard-delete from UI is broken.** Dashboard sends DELETE with no body; API requires `{confirm: 'DELETE', reason: required}`. **400s every time.** The dashboard's typed-DELETE confirmation is theater.
- **Daily-signups / daily-items charts don't filter `deleted_at IS NULL`** while `/stats/full` does. **Leadership dashboard won't reconcile with headline totals.**
- **Newsletter confirmation tokens have no TTL.** Tokens from months ago remain valid.
- **Commission approve/pay/cancel writes no audit_logs entries despite firing Stripe transfers.** Money moves with no audit trail.
- **No persistent retry queue for SendGrid failures.** Gift activation emails are lost on transient outages. Partner has been charged $99-$249; homebuyer never gets the link.
- **No SendGrid event webhook.** Bounces / complaints / deliverability are blind to the DB.
- **No CAN-SPAM postal address in any email footer.**
- **Suspend burns refresh tokens but doesn't blacklist in-flight access tokens.** Suspended user keeps API access for up to 1h.

---

# Part 3 — V1 corrections

V2's deeper reading found multiple v1 findings that were **wrong**. These should be struck:

- **v1 mobile features M1** — Settings imports `haven_image.dart` but never uses HavenImage. **Wrong:** `HavenAvatar` is exported from there and used. (Mobile features v2 strikes.)
- **v1 mobile features L11** — `_error` never rendered in conflicts screen. **Wrong:** rendered at lines 218-227. (Mobile features v2 strikes.)
- **v1 money M-MP-5** — `requirePartner` doesn't gate on `status='active'`. **Wrong:** auth middleware ties `isPartner` to `partners.status='active'` via SQL at `auth.ts:105`. (Money v2 strikes.)
- **v1 email-scanner M3** — Race between scan + manual add. **Wrong:** `routes/items.ts:478` does take `FOR UPDATE` on users. Race window closed. (Email-scanner v2 strikes.)
- **v1 email-scanner H3** — Timer leak. **Wrong:** `.finally(clearTimeout)` works as advertised. (Email-scanner v2 strikes.)
- **v1 DB C3** — Verifier silently skips `this_hash IS NULL`. **Partially wrong:** mig 075's `IS DISTINCT FROM` does flag NULLs correctly. But the broader operational concern (no cron / no alert) is worse than v1 said.

Several **v1 verified-correct items turned out to be wrong** on closer reading:
- v1 said "trigger UPDATE-bypass via current_user" was Critical (C20). v2 confirms: but the deeper bug is `current_user` vs `session_user` — `SET ROLE audit_cleaner` in any tx bypasses BOTH UPDATE and DELETE. (DB H1.)
- v1 said the proxy was "in good shape." v2 found `SAFE_SEGMENT` accepts `..`. (Dashboard C2.)
- v1 said the money paths had no Criticals. v2 found 4. (Money C-MD-1..4.)

V1 was 30 minutes per surface. The takeaway: **a 30-minute pass on a 100K LOC codebase produces shallow findings and false positives.**

---

# Part 4 — Things v2 verified clean (with evidence)

Not all bad news. The deep pass confirmed many subsystems are well-built:

- **Three-phase gift create** with reverse-compensation refund on phase-3 failure (Money v1 verified, v2 re-verified)
- **`claimWebhookEvent`** race-safety with explicit `FOR UPDATE` row lock (Money v1)
- **Commission clawback ledger** preserves original earning row; CHECK constraints `chk_partner_commissions_reversal_shape` and `chk_partner_commissions_paid_has_transfer` enforce shape (Money v1)
- **30-day auto-approve cron** correctly excludes reversal-sibling rows + KYC-incomplete partners (Money v1)
- **Mig 097 immutable trigger CASCADE relaxation** (Money v1)
- **Stripe webhook signature verification** with raw-body BEFORE any DB work (Money v1)
- **RevenueCat webhook auth** via constant-time SHA-256 comparison (Money v1)
- **Refresh-token rotation atomicity** via DELETE...RETURNING (Auth v1)
- **Refresh-token storage uses keyed HMAC** (Auth v1)
- **bcrypt SHA-256 pre-hash** applies on register, login, change-password (Auth v1)
- **Apple Sign-In nonce store** correctly rejects replays (Auth v1)
- **Apple `aud` array verification** with `algorithms: ['RS256']` pinned (Auth v1)
- **TOTP comparison** is constant-time (otplib internals — Auth v1)
- **Backup codes** are single-use, atomically consumed (Auth v1)
- **Generic 401 consistency** for user-not-found / deleted_at / suspended (S-M1) (Auth v1)
- **Mig 087 `webhook_events.id INT4 → BIGINT`** correct (DB v1)
- **Mig 092 partners is_active/status invariant CHECK** is correct (DB v1)
- **Mig 030a/030b deliberate two-file split** for `ALTER TYPE` + reference (DB v1)
- **Schema-version tracking via SHA-256** with drift warnings (DB v1)
- **`oauth-encryption.ts` IV uniqueness + GCM auth correctness** (DB v1, with v2 caveat: no AAD)
- **Sealed switch in offline-sync replay** covers all 9 ApiException subtypes (Mobile sync v1)
- **Idempotency key minted at enqueue, not at retry** (Mobile sync v1)
- **Single-flight refresh deadlock-safe** (Mobile sync v1)
- **`_bytesToHex` zero-out** after PRAGMA key (Mobile sync v1)
- **`KeychainAccessibility.first_unlock_this_device`** on auth tokens AND DB key (with v2 caveat: auth_repository's duplicate uses wrong class — v1 H-MS-4)
- **F005 anchor** applied in quick_add, manual_entry, receipt_scan (Mobile features v1)
- **F124 `Money.parseToDouble`** applied in create_claim, manual_entry, quick_add, edit_item (Mobile features v1; only `add_warranty_purchase_screen.dart:213` is wrong)
- **`PopScope` consistently used** (Mobile features v1)
- **Premium screen reads live RevenueCat offering** with fallback (Mobile features v1)
- **Caddy CSP** at the edge (no unsafe-inline on script-src; frame-ancestors 'none'; HSTS+preload) — note: this is the LIVE Caddyfile; the checked-in copy is stale (Middleware F-21)
- **AASA + assetlinks + Caddy Content-Type override** for both well-known files (Marketing v1)
- **Magic-byte allowlist + zip-bomb pre-filter** for uploads (Push)
- **iOS `PrivacyInfo.xcprivacy` declares CrashData as `Linked: false`** (Push)
- **Push deep-link routes validated against `^[a-zA-Z0-9_-]{1,64}$`** allowlist (Push)
- **bcrypt cost 12** verified across all `bcrypt.hash` calls (Marketing v1)
- **No advertising SDKs** in pubspec.yaml (Marketing v1)
- **Honeypot + 15s timeout + `credentials: 'omit'`** on contact form (Marketing v1)
- **Free-tier limit (5)** consistent across marketing/api_client/api config (Marketing v1)

The codebase has clear evidence of careful thought in many places. The Criticals cluster around (1) flows that span multiple surfaces (deletion drift, MFA, OAuth bypasses) where no single owner verified end-to-end, (2) the audit chain where DB-level grants undermine SQL-level integrity, (3) money math where `dollarsToCents` exists but isn't used everywhere, (4) privacy-policy lies where copy outpaced code.

---

# Part 5 — Suggested fix order

This time, mapped to actual leverage:

**Week 0 — within 24h:**
1. Rotate `.env.staging` secrets, including the Firebase service-account key. (Tier-zero #7)
2. Delete or sync the stale `caddy/havenkeep.caddyfile` (per Rule 3) — pre-deploy hazard. (Middleware F-21)
3. Revert / nuke the `next.config.js` rewrites footgun. (v1 Dashboard C25 still unfixed)

**Week 1 — flow integrity (before any external user touches the system):**
4. Fix the deletion cluster end-to-end (Tier-zero #5). Single workstream covering 15 layers. Includes: DB partner CASCADE → SET NULL + denorm pattern, mobile recovery UI, OAuth provider revoke, push token cleanup, audit log on hard-delete, fix `DELETE /me` race, fix recovery window for password users, normalize all marketing copy + privacy policy + terms to 30 days.
5. Fix MFA end-to-end (Tier-zero #3). Auth challenge-token bypass; OAuth MFA skip; dashboard MFA UI; write `mfa.test.ts` (which doesn't exist) and remove the otplib mock that returns `{valid: true}`.
6. Fix `verify-email-change` (Tier-zero #1). One file, two SET clauses to delete.
7. Fix audit chain integrity (Tier-zero #2). `REVOKE` API role's table-DROP rights, switch trigger to `session_user`, add cron + alert + immutable-write tests.
8. Fix Money Criticals (Tier-zero #4). Phantom refunds, gift-create idempotency, prorate float-math, clawback cents-not-dollars.

**Week 2 — privacy policy + public claims (before staging-customer access):**
9. Fix all 8 privacy-policy lies (Tier-zero #6). Either implement (TLS pinning, OAuth revocation, opt-out screen, export screen, OpenAI in sub-processor list, cookies cleanup, MinIO SSE, SendGrid postal address) or remove the claim.
10. Fix Tier-zero #8 (cookies, licenses tech-stack, social handles, marketing .env.example).
11. Fix Tier-zero #9 (Platinum 24-month perk vs API 12-month cap).

**Week 3 — operational layer:**
12. Fix advisory lock collision (Theme F F-A-1) and add a central `advisory-locks.ts` registry.
13. Fix cron 09:00:00.001 boot race (Theme F F-A-2).
14. Add webhook dead-letter alert + retry cron (Theme B / Theme F).
15. Fix idempotency middleware (Theme B): concurrent-locking, deterministic body hash, include URL/query in hash key.
16. Fix CSV injection on export (Theme E M2).

**Beyond:** the ~110 highs, in agent-report priority. Each per-agent report has its own ranked list.

---

# Part 6 — Appendix: per-agent reports

Each contains full code excerpts, SQL pastes, and reproduction steps. Read these when planning fixes — this consolidated report intentionally elides the citations to stay readable.

| # | Surface | Path |
|---|---|---|
| 1 | Auth + accounts | [`docs/audit-runs-v2/01-auth-deep.md`](audit-runs-v2/01-auth-deep.md) |
| 2 | Money paths | [`docs/audit-runs-v2/02-money-deep.md`](audit-runs-v2/02-money-deep.md) |
| 3 | DB + crypto | [`docs/audit-runs-v2/03-db-crypto-deep.md`](audit-runs-v2/03-db-crypto-deep.md) |
| 4 | Mobile sync + storage | [`docs/audit-runs-v2/04-mobile-sync-deep.md`](audit-runs-v2/04-mobile-sync-deep.md) |
| 5 | Mobile features | [`docs/audit-runs-v2/05-mobile-features-deep.md`](audit-runs-v2/05-mobile-features-deep.md) |
| 6 | Partner dashboard | [`docs/audit-runs-v2/06-dashboard-deep.md`](audit-runs-v2/06-dashboard-deep.md) |
| 7 | Email scanner + OCR | [`docs/audit-runs-v2/07-email-scanner-deep.md`](audit-runs-v2/07-email-scanner-deep.md) |
| 8 | Marketing + privacy claims | [`docs/audit-runs-v2/08-marketing-deep.md`](audit-runs-v2/08-marketing-deep.md) |
| 9 | API middleware + Caddy + CORS | [`docs/audit-runs-v2/09-middleware-caddy-deep.md`](audit-runs-v2/09-middleware-caddy-deep.md) |
| 10 | Push + Crashlytics + uploads | [`docs/audit-runs-v2/10-push-crash-uploads.md`](audit-runs-v2/10-push-crash-uploads.md) |
| 11 | Email service + admin tooling | [`docs/audit-runs-v2/11-email-admin-deep.md`](audit-runs-v2/11-email-admin-deep.md) |
| 12 | Crons + account purge + barcode | [`docs/audit-runs-v2/12-crons-purge-barcode.md`](audit-runs-v2/12-crons-purge-barcode.md) |
