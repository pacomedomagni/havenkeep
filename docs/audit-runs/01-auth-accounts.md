# Audit — Auth + Accounts

**Scope:** `apps/api/src/routes/auth.ts`, `users.ts`, `mfa.ts`; `services/account-purge.service.ts`, `mfa.service.ts`; `middleware/auth.ts`; `utils/password.ts`, `utils/token-hash.ts`, `utils/token-blacklist.ts`; auth/user-related migrations 016/077/083/084/095; `routes/users.ts` /me/* endpoints; the email-change consume flow; Apple + Google OAuth server handlers; `__tests__/auth.test.ts` + `users.test.ts`.

**Out of scope (other agents):** Stripe, partner gifts, commissions, RevenueCat, mobile, dashboard, marketing, email scanner.

---

## Critical findings

### C1: MFA challenge token is also a valid access token (full MFA bypass)
**File:** `apps/api/src/middleware/auth.ts:77-80` + `apps/api/src/services/mfa.service.ts:92-100`
**What:** `mintMfaChallengeToken` signs a JWT with `config.jwt.secret`, algorithm `HS256`, and a body of `{ userId, purpose: 'mfa_challenge' }`. The `authenticate` middleware only validates the signature + algorithm and reads `userId` from the body — it never inspects the `purpose` claim. The MFA challenge token therefore satisfies `authenticate()` and authorizes any subsequent API call as the user.
**Why it matters:** Total MFA bypass. After `/auth/login` the attacker (who has the password) holds the challenge token, sends `Authorization: Bearer <mfa_token>` to any other route, and is in. The 5-min TTL is the only thing that bounds the window — long enough to call `/users/me`, `/me/change-email`, etc.
**Repro:**
1. Enroll TOTP, log in, capture the `mfa_token` from the 200 response.
2. `curl -H "Authorization: Bearer <mfa_token>" $API/api/v1/users/me` → 200 with full user payload, no TOTP needed.
**Suggested fix:** In `middleware/auth.ts` after `jwt.verify`, reject if `decoded.purpose === 'mfa_challenge'` (or, more defensively, reject any token with a `purpose` claim — only access tokens reach this middleware). Mirror the symmetric guard `verifyMfaChallengeToken` already does (mfa.service.ts:108) for the inverse direction.

### C2: OAuth login bypasses MFA entirely (Google + Apple)
**File:** `apps/api/src/routes/auth.ts:1282-1456` (Google), `1471-1748` (Apple)
**What:** `/auth/login` (line 521-542) checks `MfaService.getStatus(user.id)` and, when a verified factor exists, returns an MFA challenge instead of session tokens. `/auth/google` and `/auth/apple` go straight to `createAuthSession` and mint access + refresh tokens with no MFA gate.
**Why it matters:** A user with TOTP enrolled who *also* signed up with email/password is bypassable: an attacker who phishes / pulls a leaked Google account that shares the email completes Google sign-in (or, on Apple side, has an Apple ID in the same address book) and the API hands them session tokens without ever consulting the second factor. MFA is a marketing claim ("two-factor enabled") that doesn't hold for any user with a linked OAuth provider.
**Repro:**
1. Register with email A + password, enroll TOTP, verify.
2. Sign in via Google with the same email → 200 + tokens, MFA never asked.
**Suggested fix:** Hoist the MFA check out of `/auth/login` into a helper (`requireMfaOrIssueChallenge(userId, ...)`) and call it from `/auth/google` and `/auth/apple` immediately after the user-resolution branch finishes (auth.ts:1410 for google, auth.ts:1703 for apple — right before `createAuthSession`). For new-user creation paths there is no factor yet, so the helper short-circuits.

### C3: OAuth login issues tokens to soft-deleted and admin-suspended users
**File:** `apps/api/src/routes/auth.ts:1352-1416` (Google), `1562-1703` (Apple)
**What:** `/auth/login` audit-fix H-A1 (auth.ts:403-499) refuses to mint tokens for `deleted_at != NULL` or `plan = 'suspended'` users. Neither OAuth handler does the equivalent — `userResult` SELECTs do not include `deleted_at` / `plan` and the create-or-mint path `createAuthSession` runs unconditionally.
**Why it matters:** Two-fold harm:
1. **Audit-trail blindness:** A credential-stuffer who happens to also own a same-email Google/Apple ID can pop a fraud-suspended account, the API logs `auth.oauth_login success=true`, and the suspension oracle disappears from the audit log (the same hole H-A1 closed for /login).
2. **Confusing/broken UX for soft-deleted users:** the OAuth handler hands back an access token + refresh token, the mobile app stores them, the *next* request hits `authenticate()` which 401s on `deleted_at`. From the user's POV: "logged in successfully" then immediately "session expired" with no recovery prompt.
**Repro:**
1. Soft-delete a user (`UPDATE users SET deleted_at=NOW(), deletion_scheduled_for=NOW()+'30 days', plan='suspended' WHERE id=...`).
2. POST `/auth/google` with that user's verified Google ID token → 200 + tokens.
3. GET `/users/me` with the issued access token → 401.
**Suggested fix:** Add the same H-A1 guard to both `/auth/google` (after the `userResult` lookup at line 1352) and `/auth/apple` (line 1564 / line 1696). Specifically: when `user.deleted_at` is set and within grace, return the same `ACCOUNT_PENDING_DELETION` 403 as `/login`. When `plan === 'suspended'` (and not soft-delete-grace), return 403 `Account suspended`. When `deleted_at` is set and grace expired, return 401 `Account is closed`.

### C4: Password-account recovery is unreachable after access-token expiry
**File:** `apps/api/src/routes/auth.ts:470-499` (login state-deny) + `apps/api/src/middleware/auth.ts:138-146` (recover bypass) + `apps/api/src/routes/users.ts:703-748` (recover endpoint)
**What:** When a soft-deleted user signs in via password, `/auth/login` returns `403 ACCOUNT_PENDING_DELETION` *with no tokens*. `/me/recover` requires `authenticate` → a valid access token. The user has no way to obtain one because login refuses to mint tokens for soft-deleted accounts and the only middleware bypass is for `/me/recover` *with* a valid token. After the original (pre-delete) access token expires (1h default), the recovery path is permanently closed for password-only users — they can only recover by calling `/me/recover` within the 1h window between deleting and the access token expiring, which contradicts the 30-day promise.
**Why it matters:** The product promises a 30-day cooling-off window with recovery, the email confirmation says "log back in to recover," and the API copies that string in `users.ts:699`. In reality, password users have a *1-hour* recovery window after delete. After that, the only path to recover is admin support. The mobile UI also has no `ACCOUNT_PENDING_DELETION` handler (see C5), so even within the 1h window the recovery isn't surfaced.
**Repro:**
1. As password user, DELETE `/users/me` (with password).
2. Wait 1h+ for the access token to expire.
3. POST `/auth/login` with correct credentials → 403 ACCOUNT_PENDING_DELETION, no tokens.
4. POST `/users/me/recover` with no Bearer → 401.
5. POST `/users/me/recover` with the now-expired Bearer → 401 (token expired).
6. Account purges 30 days later — user never had a path to stop it.
**Suggested fix:** Two clean options:
- (a) Mint a *short-lived* recovery-only token (purpose `'account_recover'`, 15-min TTL) when login hits the `ACCOUNT_PENDING_DELETION` branch; the middleware bypass at `auth.ts:138-146` accepts that token type only for `/me/recover`. Mirror the MFA-challenge-token pattern (and apply C1's fix so the recovery token can't be used as an access token).
- (b) Issue full session tokens for soft-deleted users-within-grace and let the middleware whitelist `/me/recover` only (already half-built) — but explicitly close every other route. (a) is safer.

### C5: Mobile has no UI for `ACCOUNT_PENDING_DELETION` / account recovery
**File:** `apps/mobile/lib/features/settings/delete_account_screen.dart:1-410` (no recovery UX) + entire mobile codebase has zero references to `ACCOUNT_PENDING_DELETION`, `recoverAccount`, or `/me/recover`
**What:** API returns the `ACCOUNT_PENDING_DELETION` 403 code on login of a within-grace soft-deleted user (`auth.ts:488-494`), but no mobile code handles that code or surfaces a "Recover account" CTA. The `delete_account_screen.dart` itself tells the user "This action is permanent / cannot be undone" — directly contradicting the 30-day grace.
**Why it matters:** Combined with C4, this means the 30-day cooling-off is a phantom feature. The user sees "permanent" before delete, sees "scheduled in 30 days" in the toast after delete, and finds no recovery surface anywhere.
**Repro:** `grep -r "ACCOUNT_PENDING_DELETION\|recoverAccount\|recover.*account" apps/mobile/lib` returns no hits.
**Suggested fix:** In `mobile/lib/features/settings/delete_account_screen.dart`, change the "permanent" copy to mention the 30-day grace + recovery path. Add a sign-in error handler for the `ACCOUNT_PENDING_DELETION` code that routes to a `RecoverAccountScreen`. The recover screen calls `/users/me/recover` with the recovery token from C4's fix and on 200 routes back to the dashboard.

### C6: Marketing copy says 7-day grace; API does 30-day; mobile says permanent
**File:** `apps/marketing/src/pages/legal/delete-account.astro:24,57` + `apps/marketing/src/pages/legal/privacy.astro:108` + `apps/api/src/routes/users.ts:642-643,699` + `apps/mobile/lib/features/settings/delete_account_screen.dart:73-74,110-111`
**What:** Three-way drift on the cooling-off window:
- **Marketing privacy + delete-account pages:** "7-day grace period" / "After 7 days, your account and associated data are cryptographically erased."
- **API code:** `INSERT INTO users SET deletion_scheduled_for = NOW() + INTERVAL '30 days'` (`users.ts:643`); response message "Account scheduled for deletion in 30 days" (line 699).
- **Mobile UI:** "This action is permanent / cannot be undone" — no grace-period mention at all.
**Why it matters:** Privacy-policy / delete-account drift is a regulator-of-record issue. CCPA/GDPR claims must match what the system actually does. A user who reads the privacy policy expecting a 7-day window will, on day 8, be inside the API's 30-day window and find their data unrecoverable from the marketing site's perspective but still recoverable in fact. Conversely, the privacy policy is now technically false (the 7-day claim is not what the code does).
**Repro:**
1. Read `marketing/src/pages/legal/delete-account.astro:24` — "7-day grace period."
2. Read `apps/api/src/routes/users.ts:643` — `INTERVAL '30 days'`.
3. Read `apps/mobile/lib/features/settings/delete_account_screen.dart:73-74` — "permanent ... cannot be undone."
**Suggested fix:** Pick one number, propagate everywhere. Recommend 30 days (matches GDPR Art. 17 customary practice and is what the code does). Update `delete-account.astro:24` and `privacy.astro:108` to "30-day grace period." Update mobile delete screen to say "Your account will be scheduled for deletion in 30 days. You can recover it at any time during that period by signing in." Add the recover UX from C5.

---

## High findings

### H1: `account-purge.service.ts` writes no audit-log entry for the actual hard-delete
**File:** `apps/api/src/services/account-purge.service.ts:82-145`
**What:** The cron loops, harvests MinIO keys, populates `warranty_purchases.user_email_at_purchase` / `warranty_claims.user_email_at_claim`, then `DELETE FROM users WHERE id = $1`. The only trace is `logger.info({ userId, userEmail }, 'Soft-deleted user permanently purged...')` — pino → Loki. No `audit_logs` row is written.
**Why it matters:** The hash-chained `audit_logs` table is the immutable record. The soft-delete event is captured (`user.delete` from the route handler), but the actual data-erasure event — which is the GDPR-relevant "right to erasure was honored at T" timestamp — exists only in transient observability logs. Loki retention is shorter than legal retention. Plus, since `audit_logs.user_id` is `ON DELETE SET NULL` (mig 004:82), the original `user.delete` row's `user_id` column also goes NULL when the user is purged — only `user_email` survives. There's no record that the deletion was *executed* vs. just *scheduled*.
**Repro:** Run a soft-delete + manual `UPDATE users SET deletion_scheduled_for=NOW() WHERE...` to age it. Run the cron. Check `audit_logs WHERE action LIKE 'user%' AND created_at > NOW() - INTERVAL '1 minute'` — empty.
**Suggested fix:** After the COMMIT in `account-purge.service.ts:119`, call `AuditService.log({ action: 'admin.user_delete', userId, userEmail, severity: 'warning', description: '30-day cooling-off expired; account permanently purged', metadata: { deletion_scheduled_for: <captured_value> } })` outside the user's tx so the audit row survives the cascade. (The `admin.user_delete` enum value is already defined in mig 004:45.) Better: add a `user.purge` enum value and use that to distinguish admin force-deletes from cron-driven cooling-off purges.

### H2: OAuth account-delete requires no re-authentication server-side
**File:** `apps/api/src/routes/users.ts:592-700`
**What:** For OAuth users, the API accepts `confirmDelete: true` with no proof of OAuth-credential possession beyond a valid bearer token. The mobile UI does a re-auth dance in `delete_account_screen.dart:159-224` (forces a fresh Google/Apple sign-in and verifies the returned subject matches), but a stolen access token used directly against the API skips that step.
**Why it matters:** Bearer tokens get pasted into curl, leak in logs, etc. For password users we require the password as a fresh-credential proof. For OAuth users we currently rely on the *client* to enforce re-auth — server doesn't verify. A token-theft attacker can permanently delete an OAuth user's account with one HTTP call.
**Repro:**
1. Steal an OAuth user's access token (or extract from a compromised device).
2. `curl -X DELETE -H "Authorization: Bearer <token>" -H "Content-Type: application/json" -d '{"confirmDelete":true}' $API/api/v1/users/me` → 200, account soft-deleted.
**Suggested fix:** Require OAuth users to attach a fresh ID token in the delete request body. The route verifies it (same path the OAuth login uses) and confirms the verified `sub` matches the user's stored `apple_user_id` / OAuth integration row. Reject otherwise. Update the mobile flow to forward the re-auth ID token instead of just `confirmDelete: true`.

### H3: `/refresh` and `/logout-all` silently swallow blacklist failures; only `/logout` fails loud
**File:** `apps/api/src/routes/auth.ts:752-756` (refresh), `885-889` (logout-all), vs. `798-810` (logout — properly returns 503)
**What:** S-M4 hardened `/logout` to return 503 if `blacklistTokenAuto` fails so the client retries instead of believing logout succeeded while the token is still live. The same code pattern in `/refresh` and `/logout-all` keeps the swallow-and-continue behavior. After `/refresh`, the OLD access token is supposed to be revoked; if blacklist fails it remains valid for its full TTL (~1h). After `/logout-all`, every other device's refresh token is dropped but their access tokens stay alive for up to 1h.
**Why it matters:** Inconsistent contract. The /logout fix exists because Redis hiccups during logout left tokens alive; the same hiccup during refresh or logout-all leaves the same window open. For `/logout-all` specifically — the user explicitly asked "kick me off everywhere right now" — silently leaving tokens alive on a Redis flap is a betrayal of the operation's name.
**Repro:** Make Redis return errors on SET; call `/auth/refresh` with a valid refresh token → returns 200 + new tokens. The OLD access token is still valid; `isTokenBlacklisted` returns false (Redis errors counted toward circuit breaker, not "blacklisted").
**Suggested fix:** Mirror the `/logout` pattern: throw `AppError(503, 'UNHEALTHY')` when `blacklistTokenAuto` rejects on `/refresh` and `/logout-all`. The user retries, redis recovers, the operation completes properly. The token-stays-alive risk window is gone.

### H4: Concurrent-login race produces a 500 on duplicate refresh-token INSERT
**File:** `apps/api/src/routes/auth.ts:225-237` (createAuthSession), `308-320` (register), `545-547` (login)
**What:** Refresh tokens are signed with payload `{ userId }` and the default `iat` (second resolution). Two near-simultaneous logins from the same user (2 devices, 2 tabs, parallel test runs) produce JWTs with *identical bodies* whenever the calls land in the same second. Both go to `INSERT INTO refresh_tokens (user_id, token, expires_at)` where `token` is `UNIQUE`. The second INSERT throws Postgres `23505`, which surfaces as a 500 since the route doesn't `ON CONFLICT`.
**Why it matters:** Race not bound by load — a user with two active devices opening the app at the same second triggers it. The losing call returns 500 instead of a clean retry path. Not a security bug, but a real correctness bug that the auth.test.ts `reuse@test.com` test specifically dodges with a `setTimeout(1100)` (line 243) — the test is acknowledging the race exists.
**Repro:**
```js
await Promise.all([login(creds), login(creds)]);
// One returns 200, other returns 500 (23505).
```
**Suggested fix:** Add a `jti: crypto.randomUUID()` claim to refresh tokens at sign-time (and to access tokens for symmetry). The token bodies become unique even when issued in the same second, so the SHA-256 hash differs and the UNIQUE constraint never fires. Cleanest fix.

### H5: `change-password` and `verify-email-change` invalidate refresh tokens but not access tokens on other devices
**File:** `apps/api/src/routes/users.ts:530-587` (change-password), `apps/api/src/routes/auth.ts:1177-1273` (change-email consume)
**What:** Both endpoints `DELETE FROM refresh_tokens WHERE user_id = $1` to force re-login. Other-device access tokens still pass `authenticate()` for up to `JWT_EXPIRES_IN` (1h default) because:
- access-token blacklist requires the token itself; we don't have other devices' tokens
- `invalidateUserCache` only drops the cached user-row, doesn't reject the token
- `users.password_hash` isn't a field the auth middleware checks
**Why it matters:** The user just changed their password / email *because* of a security event ("forgot it / lost a device / suspect credential leak"). The `/me/password` audit comment claims "force re-login on other devices" but other devices retain a working access token for up to an hour. UX promise violated; security objective half-met.
**Repro:**
1. Log in on device A and device B, capture device-B's access token.
2. On A, PUT `/users/me/password` with valid old + new password.
3. On B, GET `/users/me` with the captured token → 200 (still authorized).
**Suggested fix:** Add a `users.tokens_invalidated_at` (TIMESTAMPTZ) column. `change-password` and `verify-email-change` set it to NOW(). The `authenticate` middleware compares `decoded.iat * 1000` to `userRow.tokens_invalidated_at` — reject if access token was issued before. This costs one column and one comparison per auth call. (Alternative: bump a version int; same idea.)

### H6: `/users/me/change-email` skips the `email_verified` precondition
**File:** `apps/api/src/routes/users.ts:395-527`
**What:** The change-email handler verifies the current password but doesn't require the *current* email to be verified. An attacker who registers `victim@x` (unverified, password-only), then changes email to `attacker@y` and verifies via the link, ends up with a verified account whose original email was never proven owned.
**Why it matters:** Combined with the `forgot-password` skip-unverified path (good), this leaves a window where: register victim's email (no verify) → change-email to attacker's address (verifies on the new side) → password-reset still works (now email_verified=TRUE). This collapses the "you must verify your registration email before account takeover paths open" defense.
**Repro:**
1. Register `victim@example.com` with password P (don't verify email — never click).
2. POST `/users/me/change-email` with `{newEmail: "attacker@evil.com", password: P}` → 200.
3. Click the link in attacker's inbox → users.email = attacker, email_verified=true.
4. Now an attacker-owned account exists tied to `attacker@evil.com`.
**Suggested fix:** In `users.ts:412-414` (right after the password-set check), add: `if (!user.email_verified) throw new AppError('Verify your current email before changing it.', 400, 'EMAIL_NOT_VERIFIED');`. The fetch at line 401 needs to include `email_verified` in the SELECT.

### H7: Apple Sign-In nonce comparison is non-constant-time
**File:** `apps/api/src/routes/auth.ts:1551`
**What:** `if (decoded.nonce !== nonceHash)` — string `!==`. Both inputs are sha256 hex (64 chars), and `decoded.nonce` comes from a jwt-verify-validated Apple token, so the realistic timing-attack surface is small. But this is a security-critical comparison in a security-sensitive code path; using `crypto.timingSafeEqual` is essentially free and removes the cosmetic concern.
**Why it matters:** In aggregate (paired with the rest of the audit-attention-to-detail in this file), constant-time comparison should be the default for any `===` between secrets/nonces.
**Suggested fix:** `if (!crypto.timingSafeEqual(Buffer.from(decoded.nonce, 'hex'), Buffer.from(nonceHash, 'hex'))) throw ...`. Wrap in try/catch (timingSafeEqual throws on length mismatch) and treat exception as mismatch.

---

## Medium findings

### M1: Soft-delete purge cron rate-limits to 100 users/day with no escalation
**File:** `apps/api/src/services/account-purge.service.ts:66` + `apps/api/src/index.ts:261-268`
**What:** `MAX_PER_RUN = 100` and the cron runs once daily (NOTIFICATION_HOUR_UTC + Promise.allSettled). On a busy day (post-launch / mass account-deletion event / fraud sweep) backlog accumulates at >100/day, never drains.
**Why it matters:** GDPR Art. 17 "without undue delay" has no fixed clock, but a backlog measured in months exposes the company to regulator complaints. There's also no operational alert if the candidates query is non-empty after the run — the error path only fires on per-user transaction failures, not on "we left 50 users in the queue."
**Suggested fix:** (a) Bump `MAX_PER_RUN` to a high cap (1000+) and add a metric/alert when `candidates - purged > 0` after a run. (b) Schedule the cron hourly during a backlog window (auto-scaled: if last run had backlog, run again in 1h). (c) Add a `/admin/system/purge-now` endpoint admins can use to drain manually.

### M2: TOTP code `isBackup` classification is fragile
**File:** `apps/api/src/services/mfa.service.ts:264`
**What:** `const isBackup = !/^\d{6}$/.test(trimmed);` — anything that isn't exactly 6 digits is treated as a backup code. A user fat-fingering a 7-digit TOTP code (or pasting "123456 ") gets a "backup code invalid" error rather than "invalid TOTP code" — misleading.
**Why it matters:** UX bug, not security. But it makes user-support tickets harder to triage ("user says backup code didn't work" actually means "TOTP fat-finger").
**Suggested fix:** Try TOTP first; if it fails AND the input matches the backup-code shape `^[0-9a-f-]+$` after normalization, try backup. Surface a single "Invalid verification code" error otherwise.

### M3: Refresh-token DELETE happens before the new tokens are persisted; transient failure mid-rotation logs the user out
**File:** `apps/api/src/routes/auth.ts:707-721,748-762`
**What:** `/refresh` does `DELETE … RETURNING user_id` first, then SELECT user, then blacklist old access token, then `createAuthSession`. The DELETE commits before the INSERT (different `query` calls, no shared transaction). If `createAuthSession` (or anything between DELETE and the response) fails — DB blip, network reset on the response, OOM in cap-tokens advisory lock — the user has now lost their refresh token and must re-login.
**Why it matters:** Common scenario: mobile sends `/refresh`, network drops the response, mobile retries. First attempt's DELETE landed (user lost token), retry's DELETE finds nothing (401), user sees "session expired." Mobile's single-flight reduces but doesn't eliminate this — server-side network drop kills the token regardless of client behavior.
**Suggested fix:** Wrap DELETE + INSERT in one tx via a single `getClient()`. If the INSERT fails, rollback restores the old refresh-token row, the client retries, succeeds. Mirrors the soft-delete tx pattern at `users.ts:622-659`.

### M4: `/refresh` doesn't invalidate the user cache, so a recently-suspended user can refresh once during the 10s window
**File:** `apps/api/src/routes/auth.ts:728-745`
**What:** `/refresh` re-reads users from DB *directly* (line 727), so its `user.deleted_at`/`plan === 'suspended'` check is fresh. Good. But it doesn't invalidate the user cache after issuing the new tokens. The next call (within 10s) hits the cached `is_admin = true` row even if an admin demotion happened concurrently — the user-cache is the well-known 10s-stale layer; refresh doesn't bust it.
**Why it matters:** Marginal. The cache TTL is 10s; admin demotion via the admin route invalidates the cache (admin.ts:327, 402). Direct SQL changes (rare ops path) wouldn't. Worth the line of code.
**Suggested fix:** `await invalidateUserCache(trustedUserId)` after `createAuthSession` in `/refresh`.

### M5: `/users/me/change-email` issues a verification email but the response shape doesn't reveal silent rate-limit suppressions
**File:** `apps/api/src/routes/users.ts:447-477`
**What:** When the per-recipient 24h dedupe fires, OR when the new email already exists in users, the route logs a warning and returns the same generic success message ("Verification email sent..."). The user sees "we mailed it" but no email arrives. There's no client-side hint that something dropped; user retries, gets the same response, gives up.
**Why it matters:** UX trade-off: returning a distinct response leaks enumeration info (S-H2 fix is intentional). But the user has no path to debug. Two real cases hit this in practice: (a) network glitch caused first SendGrid call to drop and the dedupe key holds for 24h; (b) the user accidentally typed an existing user's email — they think the change went through.
**Suggested fix:** Keep the response shape identical, but include a Retry-After-style hint in the success body when rate-limited, with a small jitter so it's not a perfect signal. Alternatively, surface a one-time email to the *current* address ("we suppressed a change-email request because the new address is in use") so legitimate users can self-diagnose without leaking to attackers.

### M6: `/me/recover` works while `plan = 'suspended'` was set by an admin (not by soft-delete)
**File:** `apps/api/src/routes/users.ts:703-748`
**What:** The recover handler only checks `if (!user.deleted_at)` to gate. It does NOT verify `plan_before_delete IS NOT NULL` or that the suspended-state was caused by self-soft-delete vs. admin-suspend. If an admin manually set `deleted_at + plan='suspended'` (atypical but possible during a fraud incident), the user can self-recover and undo the admin action.
**Why it matters:** Conflict between the "user-initiated soft-delete with cooling-off" feature and admin-driven suspensions. Today there's only one `deleted_at` column for both intents. An admin-driven hold should not be self-reversible.
**Suggested fix:** Add a `users.deletion_initiator` column (`'self'` | `'admin'`) populated by the soft-delete route. `/me/recover` only proceeds when initiator is `'self'`. Admin-initiated holds require admin-driven recovery.

### M7: Refresh-token cap (`capRefreshTokens`) per-user advisory lock can deadlock under SELECT-FOR-UPDATE patterns elsewhere
**File:** `apps/api/src/routes/auth.ts:176-204`
**What:** `pg_advisory_xact_lock(hashtext($1))` keys on the userId hash. If any other code path takes a row-level lock on `users.id = $1` while holding *no* advisory lock, then on the next refresh-token cap call there's a lock-acquisition order inversion potential. Today nothing else uses `pg_advisory_xact_lock` keyed on hashtext(userId), so it's safe — but documenting it makes the constraint visible.
**Why it matters:** Future-proofing. If someone adds a `pg_advisory_xact_lock(hashtext(userId))` somewhere else, deadlock becomes possible.
**Suggested fix:** Either (a) document the convention "advisory locks keyed on `hashtext(user.id)` belong to `capRefreshTokens` only," or (b) namespace the lock as `pg_advisory_xact_lock(99001, hashtext(userId))` so the namespace is explicit.

### M8: `verify-email` route enforces token-type check on DELETE but `/me/change-email` request handler doesn't audit the OLD email
**File:** `apps/api/src/routes/users.ts:514-519`
**What:** The audit log entry for `user.email_change_requested` only carries `metadata.new_email`. The user's CURRENT email (which is what `users.email` was at request time) isn't in the log entry. After the change consume, you can correlate via timestamps + user_id, but if the user makes 3 changes back-to-back, the audit log doesn't capture each "from → to" pair.
**Why it matters:** Forensics. "User claims they didn't request change X" — the audit log shows "user requested change to X" but no record of the from-address at that point in time.
**Suggested fix:** Add `old_email: user.email` to the metadata in `users.ts:518`.

### M9: `users.ts:401-403` loads `password_hash` to verify password but the SELECT is not `FOR UPDATE`
**File:** `apps/api/src/routes/users.ts:400-403,530-537`
**What:** Change-password and change-email both SELECT password_hash, then bcrypt.compare, then UPDATE. Between SELECT and UPDATE, another concurrent change-password could land — the second UPDATE wins last-write. Not a security issue (both are authenticated by the same user; the order is just whoever's UPDATE landed second), but the SELECT-then-UPDATE without locking is a small staleness window.
**Why it matters:** Edge case. A user submits two parallel change-password from two devices: both validate the old password, both UPDATE. Second wins, first user thinks their change took. Not exploitable; mostly a user-confusion possibility.
**Suggested fix:** Use `FOR UPDATE` on the SELECT inside a tx, or use a `WHERE password_hash = $current_hash` predicate on the UPDATE so the second concurrent attempt fails cleanly with rowCount=0.

---

## Low findings

### L1: PASSWORD_PATTERN restricts the special-char set to `@$!%*?&` — rejects perfectly common passwords
**File:** `apps/api/src/validators/auth.validator.ts:15`
**What:** `[A-Za-z\d@$!%*?&]+`. No `-`, `_`, `+`, `(`, `)`, `'`, `"`, `,`, `.`, `<`, `>`, `/`, `\`, `|`, `:`, `;`, `[`, `]`, `{`, `}`, `~`, `` ` ``, `^`, space. A user trying `"My-Strong#Password!"` is rejected at registration.
**Why it matters:** UX. Cosmetic at this scale. Modern password guidance (NIST SP 800-63B) says don't enforce composition rules at all and allow any printable ASCII.
**Suggested fix:** Either drop the pattern entirely (length + bcrypt-pre-hash is sufficient) or expand to `[\x20-\x7e]+` (printable ASCII).

### L2: `/auth/register` returns "Email already registered" — known enumeration oracle
**File:** `apps/api/src/routes/auth.ts:267-269,287-289`
**What:** Distinct error message + status (409) on registration with an in-use email. This is a deliberate UX choice (users need to know to use login instead).
**Why it matters:** Combined with the rest of the surface (`/forgot-password` is generic, `/login` returns generic 401 on missing user), this is the only consistent enumeration oracle. Acceptable for product reasons but worth noting.
**Suggested fix:** Optional. Some products gate behind a CAPTCHA + send a "you tried to register with an email already in use; sign in instead" email to the existing address. Probably out of scope.

### L3: JWT secret rotation has no graceful path
**File:** `apps/api/src/middleware/auth.ts:77-80`
**What:** Single `config.jwt.secret`. Rotating it kicks every active session out. No multi-secret support (try new, fall back to old).
**Why it matters:** Operational. Without it you can't rotate the JWT secret without a forced-logout window for all users. Not a security issue, just an operability gap.
**Suggested fix:** Support `JWT_SECRETS` env var (comma-separated) — sign with first, verify against any. Drop entries from the list during a planned rotation.

### L4: Apple Sign-In `auth.ts:1654` synthesizes an email like `apple-{sub}@privaterelay.apple.local`
**File:** `apps/api/src/routes/auth.ts:1653-1655`
**What:** When Apple suppresses email on a subsequent sign-in and the apple_user_id lookup also missed (genuine first sign-in but client lost the email field), the route mints a placeholder local-domain email and stores it in `users.email`. The placeholder is non-routable.
**Why it matters:** Edge-case correctness. The user never sees the placeholder in normal flow, but if they later want to recover their account / reset password / change email, the placeholder is what `/users/me` reports until they update it. The mobile UI may render the placeholder in Settings.
**Suggested fix:** Either (a) flip a `users.requires_email_setup = TRUE` flag and surface a "set your email" prompt next time the user opens the app, or (b) accept the appleFullName from the request and emit a friendlier placeholder. This is a minor UX issue.

### L5: `auth.ts:436` runs bcrypt on `'$2a$12$...HOFglqi'` for unknown users — depends on this exact hash being a valid bcrypt blob
**File:** `apps/api/src/routes/auth.ts:425,433`
**What:** The decoy hash hardcoded in two places. If a future bcryptjs upgrade rejects malformed `$2a$12$...` blobs (it currently doesn't), the constant-time guard breaks and we revert to the timing oracle. The hash isn't checked for validity at module load.
**Why it matters:** Defensive. Not currently a problem.
**Suggested fix:** Generate the decoy at module load: `const DECOY = bcrypt.hashSync('decoy-' + crypto.randomBytes(8).toString('hex'), 12);`. Survives any future bcrypt-format change.

### L6: `parseExpiryToMs` accepts `0d` / `0s` → returns 0
**File:** `apps/api/src/routes/auth.ts:62-75`
**What:** `0d` / `0h` etc. parses cleanly to 0 ms. The DB row would be set to `Date.now() + 0` and `expires_at > NOW()` immediately fails on the next refresh. Misconfiguration produces a confusing failure mode (logins succeed but every refresh 401s).
**Why it matters:** Operability. Tracks back to a config validator gap.
**Suggested fix:** Reject `value === 0` in `parseExpiryToMs` with a clear error: "refresh token expiry must be > 0".

### L7: `users.ts:191-225` recover test in `users.test.ts` skips silently when delete didn't take
**File:** `apps/api/src/__tests__/users.test.ts:204-211`
**What:** `expect([200, 400, 401]).toContain(del.status)` followed by `if (!row.rows[0].deleted_at) return;` — the test skips its assertions when the delete-account call didn't actually delete. Test passes either way. False sense of coverage.
**Why it matters:** Test reliability. The test is supposed to prove plan-restoration on recover; if delete didn't take, the test silently does nothing.
**Suggested fix:** Make the test deterministic — either set up a known-good delete fixture (DB-side) or fail loudly when delete doesn't take. The `[200, 400, 401]` ambiguity is a sign the helper isn't reliably setting up password-auth users.

---

## Things I verified are CORRECT (worth keeping in the audit so it's not all bad news)

- **Refresh-token rotation is atomic.** `DELETE...RETURNING` (auth.ts:709-712) guarantees only one of N concurrent /refresh calls succeeds. The trusted user_id is read from the deleted row, never the JWT body — closes Ch01-F020.
- **Refresh-token storage uses keyed HMAC** (`utils/token-hash.ts:16`) with the refresh-token JWT secret, so a DB-only leak doesn't enable offline rainbow lookup.
- **No plaintext refresh tokens stored.** Every INSERT goes through `hashRefreshToken` (auth.ts:236, 319; token-hash.ts:16-22). Verified by grep.
- **The `capRefreshTokens` race** is properly serialized via `pg_advisory_xact_lock(hashtext(userId))` (auth.ts:186). Two concurrent logins can't double-delete the keep-set.
- **Soft-delete and recover preserve the prior plan** via `plan_before_delete` (mig 034) — the audit's Ch12-R003 fix, validated by the users.test.ts:191-223 test.
- **Account-purge anonymization** correctly populates `warranty_purchases.user_email_at_purchase` and `warranty_claims.user_email_at_claim` BEFORE the cascade DELETE (account-purge.service.ts:97-108). The FK SET NULL (mig 083) preserves the financial trail.
- **bcrypt SHA-256 pre-hash applies on register, login, and change-password** (auth.ts:275, 425/436, users.ts:548/554/560/612 — every bcrypt call goes through `preHashForBcrypt`). No path silently truncates a >72-byte password.
- **Password-reset tokens are single-use** via `WHERE used = FALSE` + `SET used = TRUE` atomic UPDATE (auth.ts:1066-1069). 1h TTL. Per-IP + per-recipient rate-limits.
- **Email-verification tokens are atomic-consume** via `DELETE...RETURNING` (auth.ts:1122-1129). Type discrimination via `metadata->>'type'` correctly separates register from change-email tokens (auth.ts:1126, 1199).
- **Apple Sign-In nonce store correctly rejects replays** — Redis SET NX EX with DB fallback via UNIQUE PRIMARY KEY (auth.ts:128-161 + mig 077). Cleanup cron sweeps expired (index.ts:393-402).
- **Apple `aud` array verification** uses `jsonwebtoken`'s built-in array audience matching with `algorithms: ['RS256']` pinned (auth.ts:1521-1524). The `alg: none` rejection is tested (auth.test.ts:480-493).
- **Google `aud` array verification** uses `google-auth-library`'s `verifyIdToken` with the array, plus `email_verified` enforcement (auth.ts:1325-1342). Both fail-closed on verification errors (S3-C tested).
- **TOTP comparison is constant-time** — otplib's `verifySync` uses `constantTimeEqual` internally (verified by reading `@otplib/core/dist/index.js`).
- **Backup codes are single-use, atomically consumed** via `UPDATE...RETURNING WHERE used_at IS NULL` (mfa.service.ts:269-275).
- **TOTP enrollment is two-step** (verify-flag at `verified_at` flip — mfa.service.ts:249-252) so an attacker who has the password can't enroll-and-pass-MFA in one motion.
- **`disableTotp` requires a current TOTP/backup code** (mfa.service.ts:321) — no naked-password path to remove the second factor.
- **`/me` endpoints are correctly scoped to `req.user!.id`** — no path-param IDORs (verified by grepping all `req.user`/`req.params` usages in users.ts).
- **`/me/recover` is the only middleware bypass for soft-deleted users**, scoped via path + grace-window check (middleware/auth.ts:138-146). Other authenticated routes correctly reject deleted users.
- **`invalidateUserCache` is called on every auth-state-mutating route** in users.ts: PUT /me, /verify-premium, /me delete, /me/recover, /me/providers DELETE; in auth.ts: /logout, /verify-email, /verify-email-change.
- **Password-reset on success drops every refresh token + every other unused reset token + every pending email-verification token** (auth.ts:1086-1092) — verified Ch01-F018 fix is intact.
- **`/auth/forgot-password` is a constant-time, content-identical response** for unknown / OAuth-only / unverified-email accounts (auth.ts:929-1045 + tests at auth.test.ts:333-401).
- **The Apple H-A6 cross-account-takeover guard** (different `apple_sub` for same email) is in place at auth.ts:1618-1643 with proper audit-log capture.
- **Logout requires authentication** (Ch01-F014) and returns 503 on blacklist failure (S-M4) — both verified.
- **`generic 401` consistency across the auth middleware** for user_not_found / deleted_at / suspended states (S-M1 — middleware/auth.ts:111-168) — all three branches return the same `Authentication failed` body, with the actual reason logged server-side.

---

## Out-of-scope items I noticed (other agents will own these)

- **Mobile `delete_account_screen.dart` re-auth flow** is correct (`_reauthenticateOAuth` verifies the returned user.id matches), but the API doesn't enforce that re-auth — see H2.
- **Marketing `/legal/delete-account.astro` and `/legal/privacy.astro`** carry the wrong grace-period number (7 days vs. 30) — see C6.
- **Mobile auth_provider has zero `ACCOUNT_PENDING_DELETION` handling** — see C5.
- **`token-blacklist.ts:tokenKey` uses plain SHA-256, not keyed HMAC.** Lower priority because the JWT itself is a bearer (the blacklist key comes from the JWT input), but inconsistent with token-hash.ts. Could be hardened.
- **MFA enforcement on dashboard/admin login paths** — out of scope for this audit (dashboard agent owns).
- **Dashboard middleware reads `is_admin` from JWT body for routing** — H-A8 introduced `/auth/role-check`, but verifying the dashboard actually uses it is the dashboard agent's territory.
- **Email-change flow's marketing-site verify-email-change.astro** at `apps/marketing/src/pages/verify-email-change.astro` is correct end-to-end (POSTs to API, surfaces success/error states), but is marketing-agent territory.
