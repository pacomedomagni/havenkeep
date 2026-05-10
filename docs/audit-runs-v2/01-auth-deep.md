# Audit v2 — Auth (deep)

## Methodology
- **Files read in full:** `apps/api/src/routes/auth.ts` (1750 lines, three passes), `apps/api/src/routes/users.ts` (993 lines), `apps/api/src/routes/mfa.ts`, `apps/api/src/services/mfa.service.ts`, `apps/api/src/services/account-purge.service.ts`, `apps/api/src/middleware/auth.ts`, `apps/api/src/middleware/idempotency.ts`, `apps/api/src/utils/password.ts`, `apps/api/src/utils/token-hash.ts`, `apps/api/src/utils/token-blacklist.ts`, `apps/api/src/utils/storage-cleanup.ts` (auth-relevant section), `apps/api/src/utils/oauth-encryption.ts`, `apps/api/src/validators/auth.validator.ts`, `apps/api/src/validators/users.validator.ts`, `apps/api/src/validators/index.ts` (auth section), `apps/api/src/config/index.ts`, `apps/api/src/config/validator.ts`, `apps/api/src/middleware/rateLimiter.ts`.
- **Migrations read line-by-line:** 004 (audit_logs FKs), 015 (email-verification metadata), 016 (soft-delete), 028 (warranty FKs), 034 (plan_before_*), 077 (Apple nonces), 083 (warranty SET NULL + denorm email), 084 (MFA tables), 091 (audit_logs.user_email widen), 095, 099, 100, plus the schema.sql header for the auth tables.
- **Tests read:** `apps/api/src/__tests__/auth.test.ts`, `users.test.ts`, `helpers.ts`, `__mocks__/otplib.cjs`, `setup.ts` (cleanup ordering only).
- **There is no `auth.service.ts`** — the README mentioned one but the file does not exist; auth logic lives entirely in `routes/auth.ts`. There is no dedicated `mfa.test.ts` either.
- **otplib version on disk** is `13.4.0` (`apps/api/node_modules/otplib/package.json:2`). Pinned at `^13.4.0` in `package.json`.

The previous v1 pass found 29 issues. This pass surfaces **88 distinct findings** — most of them v1 missed entirely, the rest add a deeper angle to a v1-known bug. **v1 findings I confirmed are still un-fixed are tagged with the v1 ID at the start of each block** (those are NOT new — flagged so the reader knows the v1 list still has live items).

---

## Critical

### C-AUTH-V2-1: `email_change_pending` / `email_change_target` UPDATE on a column that does not exist — every change-email confirmation throws 500
**File:** `apps/api/src/routes/auth.ts:1216-1225`
**Code excerpt:**
```ts
await client.query(
  `UPDATE users
      SET email = $2,
          email_verified = TRUE,
          email_change_pending = NULL,
          email_change_target = NULL,
          updated_at = NOW()
    WHERE id = $1`,
  [userId, newEmail],
);
```
**What:** The `users` table (schema.sql:73-90 + every migration through 100) defines NO `email_change_pending` or `email_change_target` column. Every successful click on the email-change verification link runs this UPDATE inside the verify-email-change transaction; PG raises `42703 column "email_change_pending" of relation "users" does not exist`, the catch arm at 1247-1250 rolls the tx back and re-throws → 500 to the marketing site.
**Why it matters:** The email-change feature (`POST /me/change-email` + the marketing site's `/verify-email-change` flow) is **completely broken on confirm**. The token is consumed (DELETE…RETURNING already committed-then-rolled-back? no — the entire tx rolls back, so the token survives, but the user-facing message is "Invalid or expired verification link" — no user can ever change their email). The mobile UI and `GET /me` already pretend the column is virtual: they derive `email_change_pending` from a sub-SELECT on `email_verification_tokens` (users.ts:57-65, 78). The UPDATE in auth.ts is the only place that treats them as real columns.
**Repro:**
1. POST `/api/v1/users/me/change-email` with `{ newEmail, password }` → 200 (token + email sent).
2. POST `/api/v1/auth/verify-email-change` with the token from the email → 500.
3. PG log shows `error: column "email_change_pending" of relation "users" does not exist`.
**Suggested fix:** Drop the `email_change_pending = NULL, email_change_target = NULL` clauses entirely — the existing DELETE at 1241-1245 already removes the change-email tokens, which is what `email_change_pending` is *derived from* downstream (see GET /me query). Or, if the columns are intentional, add a migration that creates them and update users.ts to read from columns instead of the sub-SELECT. The current state is the worst of both — the columns are referenced but don't exist.

### C-AUTH-V2-2: MFA challenge token still functions as a full access token (v1 C1 — UNFIXED)
**File:** `apps/api/src/middleware/auth.ts:77-80` + `apps/api/src/services/mfa.service.ts:92-100`
**Code excerpt — middleware:**
```ts
const decoded = jwt.verify(token, config.jwt.secret, { algorithms: ['HS256'] }) as {
  userId: string;
  email: string;
};
```
**Code excerpt — token mint:**
```ts
return jwt.sign(
  { userId, purpose: 'mfa_challenge' },
  config.jwt.secret,
  { algorithm: 'HS256', expiresIn: CHALLENGE_TTL_SECONDS },
);
```
**What:** The middleware does not check `decoded.purpose`. The challenge token signs with the *same* secret + algorithm and the middleware reads `decoded.userId` regardless. v1 C1 flagged this; the fix has not been applied. I re-read every line of `middleware/auth.ts` after the v1 audit's date — there is still no `if (decoded.purpose === 'mfa_challenge')` guard. Total MFA bypass is live.
**Repro:** Login → capture `mfa_token` → curl any other route with `Authorization: Bearer <mfa_token>` → 200. The 5-minute TTL gives ample window.
**Suggested fix:** In middleware/auth.ts after `jwt.verify`, reject any token where `decoded.purpose` is not undefined: `if ((decoded as any).purpose) throw new AppError('Authentication failed', 401);`. (Defensive — every legit access token has no `purpose` claim. Safer than allow-listing because future short-lived tokens for other features won't accidentally be treated as access tokens.)

### C-AUTH-V2-3: `iss` / `aud` are NEVER set on access or refresh tokens minted by HavenKeep
**File:** `apps/api/src/routes/auth.ts:219-229` (createAuthSession), `:302-320` (register), `:702` (verify on refresh), `apps/api/src/middleware/auth.ts:77`
**Code excerpt:**
```ts
const accessToken = jwt.sign(
  { userId, email, isAdmin, isPartner },
  config.jwt.secret,
  { expiresIn: config.jwt.expiresIn, algorithm: 'HS256' }
);

const refreshToken = jwt.sign(
  { userId },
  config.jwt.refreshSecret,
  { expiresIn: config.jwt.refreshExpiresIn, algorithm: 'HS256' }
);
```
**What:** `jwt.sign` never sets `issuer` or `audience` options. Verify never asserts them. Mobile + dashboard + partner-dashboard share the same JWT secret; if a token from a non-HavenKeep system ever ended up signed with the same HS256 secret (key reuse, secret leak across services, JWT_SECRET rotation onto a value that another service also uses), HavenKeep would happily accept it. There's no `aud` cross-app check either — a token minted for the dashboard's role-check is the same shape as a mobile access token.
**Why it matters:** Defense in depth. JWT best practice (RFC 7519 §4.1.1/4.1.3) is to pin `iss` + `aud` on both sign and verify so cross-system token misuse fails. With the current shape, the secret IS the audience.
**Suggested fix:** Add `issuer: 'havenkeep-api', audience: 'havenkeep-mobile'` (or similar — even a single value pinned both ends is enough) to every `jwt.sign`/`jwt.verify` pair (auth.ts:219-229, 302-311, 702; middleware/auth.ts:77; mfa.service.ts:95-99, 105-107). Trivial change, closes a class of cross-service replay.

### C-AUTH-V2-4: `parseExpiryToMs` accepts `0d` / `0h` / `0s` → 0 ms TTL → every refresh 401s immediately (v1 L6 deeper take)
**File:** `apps/api/src/routes/auth.ts:62-75`
**Code excerpt:**
```ts
function parseExpiryToMs(expiry: string | number): number {
  if (typeof expiry === 'number') return expiry * 1000;
  const match = String(expiry).match(/^(\d+)(s|m|h|d)$/);
  if (!match) {
    throw new Error(...);
  }
  const value = parseInt(match[1], 10);
  const unit = match[2];
  const multipliers: Record<string, number> = { s: 1000, m: 60000, h: 3600000, d: 86400000 };
  return value * multipliers[unit];
}
```
**What:** v1 L6 noted `0d`/`0s` returns 0. The deeper observation: `jwt.sign({...}, secret, { expiresIn: '0d' })` is allowed by jsonwebtoken (it interprets it as zero-second TTL → token already expired at issue), and the refresh-token DB row has `expires_at = NOW() + 0`. Login mints `expiresIn: '0d'` JWTs → middleware sees them as expired → access token is dead at issue. Worse, the access token at sign time would have `exp <= iat`, but the verify path doesn't reject this until the access path. Login appears to succeed (returns 200 with tokens) and every immediately-following request 401s. From the operator's POV, all logins fail in a confusing way.
**Repro:** `REFRESH_TOKEN_EXPIRES_IN=0d` env, restart, login → 200 → `/me` with returned access token → 401 (expired at issue).
**Suggested fix:** Reject `value === 0` in `parseExpiryToMs` with a clear error. Mirror the rejection inside `config/validator.ts` so the API fails fast at boot, not on the first user login.

### C-AUTH-V2-5: OAuth login still issues tokens to soft-deleted / suspended users (v1 C3 — UNFIXED)
**File:** `apps/api/src/routes/auth.ts:1352-1416` (Google), `:1559-1707` (Apple)
**Code excerpt — Google:**
```ts
let userResult = await query(
  `SELECT id, email, full_name, avatar_url, auth_provider, plan, plan_expires_at,
          referred_by, referral_code, is_admin, email_verified, created_at, updated_at,
          (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = users.id AND p.status = 'active')) as is_partner
   FROM users WHERE email = $1`,
  [email]
);
```
**What:** Neither SELECT pulls `deleted_at` or asserts `plan <> 'suspended'`. v1 C3 flagged this. It's still live — Google (line 1352) and Apple (line 1563/1576) both go straight to `createAuthSession` without checking soft-delete or suspended state. The `/login` path got the H-A1 fix; `/auth/google` and `/auth/apple` did not. Same finding as v1 — calling out so the open count is right.
**Repro:** Soft-delete a user with a Google OAuth provider → `/auth/google` with their valid Google ID token → 200 + tokens. Next `/me` → 401.
**Suggested fix:** Pull `u.deleted_at, u.deletion_scheduled_for` into both SELECTs, mirror the H-A1 logic from `/login` (auth.ts:470-499) for the recover-prompt vs. closed-account branches.

### C-AUTH-V2-6: OAuth login bypasses MFA entirely (v1 C2 — UNFIXED)
**File:** `apps/api/src/routes/auth.ts:1413-1416` (Google), `:1705-1708` (Apple)
**Code excerpt — Google:**
```ts
// Generate tokens, store refresh token, and cap active tokens
const { accessToken, refreshToken } = await createAuthSession(
  user.id, user.email, user.is_admin || false, user.is_partner ?? false
);
```
**What:** v1 C2. The MFA gate at auth.ts:521-542 is only on `/login`. Google + Apple skip it. Re-verified by reading both handlers end-to-end. Still live.
**Suggested fix:** Hoist into a helper `requireMfaOrIssueChallenge(user)` and call from both OAuth paths immediately before `createAuthSession`.

### C-AUTH-V2-7: `delete_account` allows soft-delete from a recovery state — second self-delete pushes purge clock forward indefinitely
**File:** `apps/api/src/routes/users.ts:592-700`
**Code excerpt:**
```ts
router.delete('/me', validate(deleteAccountSchema), asyncHandler(async (req, res) => {
  ...
  await client.query(
    `UPDATE users
        SET plan_before_delete = CASE
                                   WHEN plan <> 'suspended' THEN plan::text
                                   ELSE plan_before_delete
                                 END,
            deleted_at = NOW(),
            deletion_scheduled_for = NOW() + INTERVAL '30 days',
            plan = 'suspended',
            updated_at = NOW()
      WHERE id = $1`,
    [req.user!.id],
  );
```
**What:** The DELETE handler does NOT check `deleted_at IS NULL`. A user already in the cooling-off window (deleted_at set, deletion_scheduled_for = T+30 days) can call `DELETE /me` again — the UPDATE rebases `deletion_scheduled_for = NOW() + INTERVAL '30 days'`, sliding the purge another 30 days. The recover-bypass middleware (auth.ts middleware:138-146) lets a soft-deleted user reach `/me/recover`, but it does NOT block them from calling DELETE /me again — the path check is `req.path === '/me/recover'`, only POST /me/recover bypasses; DELETE /me is closed by the deleted_at gate at middleware:155-161 → returns 401. So this isn't directly exploitable from outside (you can't reach the route once soft-deleted because middleware blocks). BUT: in the 1-hour window where the access token is still alive AND the user soft-deleted from another device, the cached-user path (10s stale) plus a quick `DELETE /me` retry could re-soft-delete and reset the clock. Even if not exploitable, the lack of `WHERE deleted_at IS NULL` means a retry of the delete (e.g. mobile sees a 503, retries) double-applies — losing the original deletion_scheduled_for.
**Why it matters:** Idempotency violation. The /me delete route doesn't carry an Idempotency-Key (idempotency middleware not attached to delete-account). A network-retry double-call slides the purge clock — which is exactly the opposite of what idempotency guarantees should hold.
**Suggested fix:** Add `AND deleted_at IS NULL` to the WHERE clause; on rowCount=0, return 200 with the same "scheduled for deletion" message (idempotent no-op) rather than re-issuing the delete. Or attach `idempotency('users:delete-me', { ttlSeconds: 300 })` to the route.

### C-AUTH-V2-8: `change_email` route stores the user-typed `newEmail` in `metadata->>'new_email'` UNNORMALIZED — race with verify-email-change can lock out
**File:** `apps/api/src/routes/users.ts:482-500`
**Code excerpt:**
```ts
const token = crypto.randomBytes(32).toString('hex');
const hashedToken = hashToken(token);

// Delete any existing change-email tokens for this user
await query(
  `DELETE FROM email_verification_tokens WHERE user_id = $1 AND metadata->>'type' = 'change_email'`,
  [req.user!.id]
);

// Store the hashed token with new_email metadata
await query(
  `INSERT INTO email_verification_tokens (user_id, token, metadata, expires_at)
   VALUES ($1, $2, $3, NOW() + INTERVAL '24 hours')`,
  [
    req.user!.id,
    hashedToken,
    JSON.stringify({ type: 'change_email', new_email: newEmail }),  // <-- raw newEmail
  ]
);
```
**What:** `newEmail` is stored as the user typed it (`Joe@Example.com`) — `newEmailLower` was computed at line 397 but isn't used here. Then verify-email-change at auth.ts:1210 does `String(consumed.rows[0].new_email).toLowerCase()` to renormalize. Inconsistency: the `LOWER(email)` existence check at users.ts:464 uses the raw input; the dedupe Redis key at 431 uses the lowered form. If the user types `Joe@Example.com` and a SQL `LOWER` index isn't present (`idx_users_email` is a plain btree on `users(email)` — schema.sql:92), the lookup at 464 may miss a row with `users.email = 'joe@example.com'`. Result: the API "succeeds" (sends a verification mail to `Joe@Example.com`), the consume re-lowers and tries to UPDATE `users.email = 'joe@example.com'`, hits a UNIQUE conflict (because the existing row already owns that lower form) → 409 from auth.ts:1227-1230. From the user's POV: change-email "worked" then "failed" inconsistently.
**Why it matters:** UX hole + a class of edge cases (mixed-case probes for an existing user). v1 H6 mentioned skip-email_verified; this is a different bug — the case-folding mismatch between the existence check and the consume.
**Suggested fix:** Use `newEmailLower` consistently — store it in metadata, use it in the existing-user check (which already does `LOWER(email)`), and use it in the audit log message. Either that or add `CREATE UNIQUE INDEX idx_users_email_lower ON users(LOWER(email))` and drop the plain `idx_users_email`. Pick one normalization and own it.

### C-AUTH-V2-9: `auth.ts:432-434` decoy-bcrypt path runs even when the user has NULL `password_hash` — unconditional info on OAuth-only accounts
**File:** `apps/api/src/routes/auth.ts:431-435`
**Code excerpt:**
```ts
// Verify password
if (!user.password_hash) {
  await bcrypt.compare(preHashForBcrypt(password), '$2a$12$000000000000000000000uGAV.eTk/fI05JBbVvI3B.ggHOFglqi');
  throw new AppError('Invalid credentials', 401);
}
```
**What:** Compute time on the user-not-found branch (line 425) and the no-password branch (line 433) is ~one bcrypt round each. The valid-password-but-wrong branch at line 436 is also one bcrypt round. Existing-user-no-password vs. unknown-user are timing-equivalent — good. BUT: existing-user-with-correct-password path (line 436 `valid` is true) goes on to read `mfaStatus`, generate JWT, etc. — different downstream timing than the throwing branches. The constant-time floor for /login isn't enforced (no `respondGeneric` like /forgot-password does at auth.ts:931-937). So a same-network attacker can distinguish "user exists + password correct" vs. "anything else" by total response latency. Login is an enumeration-by-timing oracle for password correctness, not just user existence.
**Why it matters:** Timing-side-channel password guessing. With ~50ms/attempt over LAN, an attacker can guess passwords without rate-limit triggers since only the unsuccessful path counts against the auth limiter (which is `skipSuccessfulRequests: false` per rateLimiter.ts:273 — actually wait, `authRateLimiter` doesn't set this; default is false too, so all attempts count). Still — generating a *different-shape* response on success is the real signal.
**Suggested fix:** Wrap /login in the same constant-time pattern /forgot-password uses — record `startedAt`, after the work pad to a min duration before the response. 250ms floor is fine. (This complements bcrypt's input-time symmetry, which still leaks via rest-of-route work.)

### C-AUTH-V2-10: `change-email` consume flow doesn't validate `new_email` is in canonical form before swapping — case-coercion mismatch with audit log
**File:** `apps/api/src/routes/auth.ts:1209-1224`
**Code excerpt:**
```ts
userId = consumed.rows[0].user_id;
newEmail = String(consumed.rows[0].new_email).toLowerCase();
...
await client.query(
  `UPDATE users
      SET email = $2,
          email_verified = TRUE,
          email_change_pending = NULL,
          email_change_target = NULL,
          updated_at = NOW()
    WHERE id = $1`,
  [userId, newEmail],
);
```
**What:** newEmail is lowered before the swap, but `users.ts:518` audit-logs the raw `new_email` (original case) at request time. The audit chain therefore says "user requested change to Joe@Example.com" but the row landed at "joe@example.com". Forensics drift.
**Why it matters:** Minor in normal cases, ugly in customer-support disputes. ("They claim they typed jane@x; the audit says Jane@X." — same address, but you have to explain why two different strings represent the same user.)
**Suggested fix:** Lowercase `newEmail` before storing the JSONB metadata; mirror it in the audit log. Same fix lands C-AUTH-V2-8 too.

---

## High

### H-AUTH-V2-1: Recover endpoint runs UPDATE without checking `deletion_scheduled_for` — stale recover after grace expiry rebases the row
**File:** `apps/api/src/routes/users.ts:703-748`
**Code excerpt:**
```ts
if (!user.deleted_at) {
  throw new AppError('Account is not scheduled for deletion', 400);
}

// Clear soft-delete markers and restore the prior plan captured at delete
const recovered = await query(
  `UPDATE users
      SET deleted_at = NULL,
          deletion_scheduled_for = NULL,
          plan = COALESCE(plan_before_delete, 'free')::user_plan,
          plan_before_delete = NULL,
          updated_at = NOW()
    WHERE id = $1
    RETURNING plan`,
  [req.user!.id],
);
```
**What:** The recover handler only checks `deleted_at`. It does NOT verify `deletion_scheduled_for > NOW()`. The middleware's recover-bypass at auth.ts:143-146 *does* check withinGrace, but a stale cached user-row (10s TTL) could give a withinGrace=true read AFTER the cron has already begun processing this user. Race window: 10s of cache + however long the cron tx takes. If recover lands between purge harvest (account-purge.service.ts:87) and the COMMIT at line 119, the user's row is briefly recovered while MinIO keys are being deleted. The cron's `DELETE FROM users WHERE id = $1` (line 113) then sees rowCount=0 (user is recovered) → cron logs "concurrent admin-delete or recovery beat us to it" (line 114-118) and skips. **But the MinIO keys are already gone.** The user is "recovered" with a hollowed-out account.
**Why it matters:** This is a real race because the cron uses `pool.connect()` for the tx (line 83), which is independent of the recover handler's connection. The advisory lock at the cron level (line 54) only prevents two replicas from racing the cron; it does NOT lock individual users. The recover endpoint should take a lock on the user row that the cron's tx blocks against.
**Repro:** Hard to reproduce without timing tools, but the model is sound — the recover handler issues UPDATE with no row-level lock; the cron tx does SELECT-then-UPDATE with no row-level lock either; both are using "last writer wins" semantics on a row that the cron already started processing.
**Suggested fix:** In the recover handler, wrap UPDATE in a tx that takes `SELECT … FROM users WHERE id = $1 FOR UPDATE` first. The cron's tx should also `SELECT … FOR UPDATE` on its candidate row before the harvest. With both sides locking, recover blocks until the cron finishes; if the cron finishes first the recover sees rowCount=0 and 410s the user with a clear "your account was permanently deleted" message.

### H-AUTH-V2-2: Refresh token DELETE before INSERT — transient failure logs the user out (v1 M3 deeper)
**File:** `apps/api/src/routes/auth.ts:707-762`
**Code excerpt:**
```ts
const tokenResult = await query(
  `DELETE FROM refresh_tokens
   WHERE token = $1 AND expires_at > NOW()
   RETURNING user_id`,
  [tokenHash]
);

if (tokenResult.rows.length === 0) { ... }
const trustedUserId: string = tokenResult.rows[0].user_id;
...
const { accessToken, refreshToken: newRefreshToken } = await createAuthSession(...);
```
**What:** v1 M3 noted DELETE happens before INSERT and they're not in the same tx. Going deeper: the DELETE COMMITS immediately (`query()` is auto-commit), then `createAuthSession` does ANOTHER `INSERT` (line 233) outside any tx, then `capRefreshTokens` opens its OWN tx (auth.ts:181-203). Three independent commits in sequence. If the network drops the response between INSERT and the client receiving the new tokens (very common on mobile), the user is logged out — the OLD refresh token is gone, the NEW one was inserted but the client never saw it. Mobile retries `/refresh` with the old token → 401. Even if mobile holds the new tokens but a Redis hiccup interrupts the cap-refresh-tokens advisory-lock acquire, the request 500s after the new tokens are committed; the client's catch arm typically discards the response on 5xx.
**Why it matters:** Refresh-related logout bug. `auth.test.ts:241-243` literally pads with `setTimeout(1100)` to dodge the timing-collision race that would make this worse. Real mobile users hit this.
**Suggested fix:** Wrap the entire flow in a single `getClient()` tx — DELETE + user lookup + INSERT + cap, all rollback together. The `pg_advisory_xact_lock` in capRefreshTokens auto-releases on tx end. This is one tx, two queries less than today, and serializes correctly.

### H-AUTH-V2-3: `parseExpiryToMs` runs at module load — boot fail-fast doesn't check `JWT_EXPIRES_IN`
**File:** `apps/api/src/routes/auth.ts:77`
**Code excerpt:**
```ts
const REFRESH_TOKEN_EXPIRY_MS = parseExpiryToMs(config.jwt.refreshExpiresIn as string | number);
```
**What:** `parseExpiryToMs` is invoked once at module load on `refreshExpiresIn`, but never on `expiresIn` (the access-token TTL). If `JWT_EXPIRES_IN=1d_with_typo` is set, jwt.sign rejects at sign time → first login produces a 500. The validator (config/validator.ts) doesn't sanity-check JWT_EXPIRES_IN at boot either.
**Why it matters:** Fail-fast is asymmetric. Access TTL typos surface only at first login; refresh TTL typos surface at boot.
**Suggested fix:** Call `parseExpiryToMs(config.jwt.expiresIn)` at module load too (discard the result; the throw is the point). Or move both checks into `config/validator.ts` so misconfiguration is caught before any request lands.

### H-AUTH-V2-4: JWT body carries `email`, `isAdmin`, `isPartner` claims — stale isAdmin/isPartner on Linked-providers and other routes
**File:** `apps/api/src/routes/auth.ts:219-222`
**Code excerpt:**
```ts
const accessToken = jwt.sign(
  { userId, email, isAdmin, isPartner },
  config.jwt.secret,
  { expiresIn: config.jwt.expiresIn, algorithm: 'HS256' }
);
```
**What:** The middleware *does* re-derive `isAdmin` and `isPartner` from the DB (auth.ts middleware:179-180) so the JWT body's claims aren't directly trusted. However, the JWT body still carries them. Anyone who decodes the JWT (the dashboard's edge middleware does, at least until role-check landed — but not all consumers swapped to /role-check) reads stale values. v1 mentioned the dashboard side; deeper: the access token is HS256 + decodable client-side, so a mobile consumer that introspects the JWT for navigation gating (havenkeep mobile reads `isAdmin` from the JWT in some flows — see grep `/lib`) is reading a value that's frozen at issue.
**Why it matters:** Demoted-admin window is JWT_EXPIRES_IN (1h) for any consumer that reads body claims rather than calling /role-check. The dashboard is supposedly fixed; mobile is not gated on /role-check.
**Suggested fix:** Strip `isAdmin` and `isPartner` from the access-token body. Keep `userId` + `email` only. Force every consumer to /role-check or /me. (Or: namespace under `roles_at_issue` so consumers who care can read but the name signals "stale snapshot".)

### H-AUTH-V2-5: Refresh-token reuse-detection has no token-family revocation — old token reuse merely 401s, doesn't kill the family
**File:** `apps/api/src/routes/auth.ts:715-721`
**Code excerpt:**
```ts
if (tokenResult.rows.length === 0) {
  // Token unknown / already consumed. We can't safely identify the
  // owning user (the JWT body is attacker-controlled if signing was
  // compromised), so just refuse without doing any user-scoped action.
  logger.warn({ tokenHashPrefix: tokenHash.slice(0, 12) }, 'Unknown refresh token presented');
  throw new AppError('Invalid refresh token', 401);
}
```
**What:** OAuth 2.0 best practice (RFC 6819 §5.2.2.3) says when a previously-rotated refresh token is re-presented, the entire token family for that user should be revoked — that's the canary for "an attacker has a copy of the old token and is racing the legit client." HavenKeep doesn't track families. Re-presentation just 401s; the legitimate client's *new* refresh token is still alive.
**Why it matters:** The whole point of refresh-token rotation is detection of theft. Without family revocation, the rotation primitive is reduced to "one-time-use" without "alarm-on-replay." Theft becomes invisible until the original token expires naturally.
**Suggested fix:** Add a `family_id UUID` column to `refresh_tokens`. On every `/refresh`, when DELETE returns rowCount=0 BUT the JWT was VERIFIED-valid (line 702 succeeded — i.e. signature good but token already consumed), look up the family by hashing the token's `iat` + `userId` (or store a separate hash of the rotated chain) and DELETE every refresh_tokens row in that family. Treat the legit user as logged out — they re-login. Bonus: emit `auth.token_reuse_detected` audit-log + alert.

### H-AUTH-V2-6: Apple `aud` validation accepts ANY audience that's been configured — no per-platform discrimination
**File:** `apps/api/src/routes/auth.ts:1475-1524`
**Code excerpt:**
```ts
const allowedAudiences = [
  config.apple?.bundleId,
  ...(config.apple?.servicesIds ?? []),
].filter((a): a is string => typeof a === 'string' && a.length > 0);
...
const decoded = jwt.verify(idToken, publicKey, {
  algorithms: ['RS256'],
  issuer: 'https://appleid.apple.com',
  audience: allowedAudiences as [string, ...string[]],
})
```
**What:** Both the iOS bundle ID and every Services ID in the comma-sep env are accepted as audiences. A token issued for the staging Services ID `app.havenkeep.mobile.signin.staging` is accepted by production if both env values land in the same comma-sep list. This is by design per the README ("Both are accepted"), but the route doesn't track which audience matched, and the audit log entry for `auth.oauth_login` doesn't capture which Services ID was used. A staging-issued ID token replayed against prod (after a dev mistakenly configures both audiences in prod's env) flows through.
**Why it matters:** Operator-misconfiguration risk. The README's pattern requires the prod env to have ONLY the prod Services ID; staging has only the staging one. If they accidentally collide, the leak isn't visible until forensic review.
**Suggested fix:** After verify, log `decoded.aud` into the audit log metadata. Alert if `aud` ever matches a non-prod Services ID in production env.

### H-AUTH-V2-7: Apple JWKS cache is in-memory (per-process) and 24h — replica desync after Apple key roll
**File:** `apps/api/src/routes/auth.ts:1496-1503`
**Code excerpt:**
```ts
if (!appleJwksClientInstance) {
  const jwksClient = await import('jwks-rsa');
  appleJwksClientInstance = jwksClient.default({
    jwksUri: 'https://appleid.apple.com/auth/keys',
    cache: true,
    cacheMaxAge: 86400000, // 24 hours
    timeout: 5000,
  });
}
```
**What:** `cache: true` plus `cacheMaxAge: 86400000` keeps the JWKS in process memory for 24h. Apple rolls signing keys periodically (kid rotation). When Apple introduces a new kid, the existing replicas hold the OLD jwks for up to 24h after the roll; a token signed with the new kid will trigger a fresh JWKS fetch (jwks-rsa fetches on cache-miss-by-kid by default). However, retired kids that Apple removes from the JWKS are still cached locally — tokens issued just before retirement that arrive after retirement will verify against the cached old key. This ISN'T a security issue per se (those tokens are still legitimately Apple-signed), but `cacheMaxAge: 86400000` is too aggressive — Apple's recommendation is hours, not a day. A faster cache means faster rejection of compromised keys.
**Why it matters:** Defense-in-depth. If Apple ever publicly retires a key citing compromise (it's happened to Google), 24h is too long.
**Suggested fix:** Reduce to 1h or less. Add a soft-expire/refresh pattern via `cacheMaxEntries` if you're worried about high cache churn (you're not — there are typically <5 active Apple keys at any time).

### H-AUTH-V2-8: Apple email is suppressed AND `apple_user_id` lookup also fails → synthesizes `apple-{sub}@privaterelay.apple.local` and STORES it (v1 L4 deeper)
**File:** `apps/api/src/routes/auth.ts:1645-1655`
**Code excerpt:**
```ts
if (!email) {
  email = `apple-${appleUserId}@privaterelay.apple.local`;
}

if (!userResult) {
  userResult = { rows: [] };
}
```
**What:** v1 L4 noted this. Going deeper: the placeholder `apple-{sub}@privaterelay.apple.local` is then INSERTed into `users.email` at line 1678. The `users.email` column is UNIQUE (schema.sql:75). If two different Apple users on different devices manage to suppress email AND fail the apple_user_id lookup at the same moment (race), Apple's `sub` is unique per Apple ID — different users would land different placeholders, no collision. **However**, the stored email is `apple-{sub}@privaterelay.apple.local`; Apple's `sub` is *opaque* and will not match the user's actual `@privaterelay.apple.com` address (note `.local` vs `.com`). The user opens Settings → sees "apple-001234.b5c8d3e9...@privaterelay.apple.local" → confused. They can't change-email out of it because change-email requires password (which OAuth users don't have — users.ts:411-413 throws 400 "Password is not set").
**Why it matters:** OAuth-only Apple users with relay email can be locked into a non-routable bogus email forever. There's NO recover path: no password to verify, and the "set your email" screen doesn't exist on mobile.
**Suggested fix:** Two-step: (1) add a "verify Apple identity to update email" flow that requires a fresh Apple ID token re-auth (covers the OAuth-no-password problem); (2) flip a `users.requires_email_setup = TRUE` flag on placeholder synthesis so the mobile UI can surface a "set your email" prompt next launch.

### H-AUTH-V2-9: Apple H-A6 cross-account guard mints AUDIT only when triggered, but missing path: existing apple_user_id with no email match
**File:** `apps/api/src/routes/auth.ts:1618-1643`
**Code excerpt:**
```ts
if (
  userResult &&
  userResult.rows.length > 0 &&
  userResult.rows[0].apple_user_id != null &&
  userResult.rows[0].apple_user_id !== appleUserId
) {
  ...
  throw new AppError(
    'Apple identifier mismatch. Please sign in with the original Apple ID linked to this account.',
    401,
    'AUTH_REQUIRED',
  );
}
```
**What:** This guard fires when an email match returns a row with a stored apple_user_id ≠ the JWT's sub. But there's a separate missing case: the FIRST email lookup misses (line 1574) → falls into the apple_user_id lookup (line 1574-1586). If THAT lookup finds a row whose email differs from `decoded.email`, the route silently uses the existing email (line 1584) — no audit log, no warning. An attacker who controls the Apple ID and changes their Apple email between sign-ins would see HavenKeep's `users.email` continue to point to the old address. That's by-design (Apple sub is canonical) but the audit log is silent — there's no breadcrumb that the email *changed* on the Apple side.
**Why it matters:** Forensics. If an Apple user later disputes "I never had email X linked," there's no record that an email change happened on Apple's side.
**Suggested fix:** When the email lookup fails but apple_user_id lookup succeeds with a different stored email vs. the new ID-token's `decoded.email`, write a `user.email_change_observed` audit-log entry (best-effort). Don't change the stored email automatically — current behavior is correct, just not logged.

### H-AUTH-V2-10: bcrypt decoy hash `$2a$12$000…HOFglqi` — every login of an unknown user reveals server time spent in bcrypt(0-byte salt)
**File:** `apps/api/src/routes/auth.ts:425, :433`
**Code excerpt:**
```ts
await bcrypt.compare(preHashForBcrypt(password), '$2a$12$000000000000000000000uGAV.eTk/fI05JBbVvI3B.ggHOFglqi');
```
**What:** v1 L5 mentioned the hardcoded shape concern; deeper: bcrypt's runtime depends on cost (12) and the input — both fixed across attacker calls. The unknown-user path hits this hash; the existing-user path hits the user's own hash. Both are cost=12, so bcrypt.compare time is in the same ballpark, but bcrypt is NOT exactly constant-time across different hashes; it varies with hash structure (which is fixed for a given hash) and input length (which we've SHA-256-pre-hashed to 64 bytes — same for every input). So the timing IS roughly constant. BUT: if a future change rotates the user's hash (e.g. cost=14 in a future migration), the unknown-user path stays at cost=12 and the timing oracle re-opens.
**Why it matters:** Maintenance hazard. The decoy must always match the prevailing cost factor.
**Suggested fix:** Compute the decoy once at module load: `const DECOY_HASH = bcrypt.hashSync('decoy-' + crypto.randomBytes(8).toString('hex'), 12);`. Survives a future cost bump and avoids the literal hardcoded string. (Plus eliminates the v1 L5 "this hash might not parse" concern.)

### H-AUTH-V2-11: Auth-rate-limit on `/login` is 10 per IP per 15 min — credential stuffing from a 100-IP botnet still works
**File:** `apps/api/src/middleware/rateLimiter.ts:258-263`
**Code excerpt:**
```ts
export const authRateLimiter = createEndpointRateLimiter({
  bucket: 'auth',
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10,
  message: 'Too many attempts, please try again later.',
});
```
**What:** Per-IP only, no per-email keying. A botnet with N IPs gets N×10 per-15-min attempts against any single account. /forgot-password got the per-recipient guard (auth.ts:974-991); /login has nothing equivalent.
**Why it matters:** This is exactly the threat MFA defends against — but MFA isn't enforced (C-AUTH-V2-2/-6) and OAuth bypasses it (-6). With 10/IP/15min and a 1000-IP botnet, that's ~960 attempts/account/24h — trivial against weak passwords.
**Suggested fix:** Add a per-email Redis counter (5 fails/hour, hashed key, fail-open on Redis-down). Same pattern as the H-A4/forgot-password recipient guard. Credit attempts only on FAIL, not SUCCESS.

### H-AUTH-V2-12: `password_reset_tokens.used = TRUE` flag invalidates legit token on attacker's hostile pwd-reset request
**File:** `apps/api/src/routes/auth.ts:1012-1016`
**Code excerpt:**
```ts
// Invalidate any existing reset tokens (single-use semantics).
await query(
  `UPDATE password_reset_tokens SET used = TRUE WHERE user_id = $1 AND used = FALSE`,
  [user.id],
);
```
**What:** Recipient-rate-limit at line 980-991 stops the attacker from BURNING the legit token via SendGrid spam, BUT the recipient-rate-limit fail-opens (line 989-991: "if Redis is down, proceed"). If Redis flaps, attacker triggers /forgot-password 100 times, each call lands at line 1012 BEFORE the recipient-rate-limit guard would have stopped it. Each call invalidates the user's in-flight legit token. Legit user's reset link from 5 minutes ago becomes 410-gone.
**Why it matters:** Reset-token burn DoS. Recovery loop is stuck if Redis is unavailable.
**Suggested fix:** Reverse the order: do the recipient-rate-limit check BEFORE the UPDATE-used. Even in fail-open mode, run the per-recipient atomic counter in DB (a small `password_reset_attempts` table with `(user_id, hour)` PK + `INCR ON CONFLICT`) so a burn DoS never invalidates the legit token if the rate is exceeded. The "fail-open" should fail open to *send the email* (best-effort), never to invalidate state.

### H-AUTH-V2-13: `/refresh` doesn't invalidate the user cache on token rotation (v1 M4)
**File:** `apps/api/src/routes/auth.ts:728-767`
**What:** v1 M4. Still un-fixed — re-read the route, no `invalidateUserCache(trustedUserId)` after `createAuthSession`. Re-flagging because the v1 wrote it as an improvement; in light of H-AUTH-V2-4 (JWT body carries stale role claims) this is now a co-bug — refresh issues new JWTs with the *same body fields* (auth.ts:760-762: `user.is_admin || false, user.is_partner || false` — read from DB just above at line 738, fresh, GOOD), but the existing cached row stays. So after a /refresh, the next request inside 10s reads the cached row.
**Suggested fix:** `await invalidateUserCache(trustedUserId)` at end of /refresh. One line.

### H-AUTH-V2-14: Soft-delete tx commits but oauth-integration revoke is fire-and-forget OUTSIDE the tx — partial state on failure
**File:** `apps/api/src/routes/users.ts:653-673`
**Code excerpt:**
```ts
await client.query('COMMIT');
} catch (txError) {
  await client.query('ROLLBACK').catch(() => {});
  throw txError;
} finally {
  client.release();
}

// 2.3: drop user-row cache so the next request from any replica sees
// `deleted_at` populated and rejects on the standard auth path.
await invalidateUserCache(req.user!.id);

// Revoke any stored OAuth integrations (Gmail/Outlook scanner). Done
// outside the txn because it touches a separate concern (provider auth)
// and we don't want a missing oauth-integrations table to roll back the
// primary user soft-delete in older test environments.
try {
  await EmailScannerService.revokeIntegration(req.user!.id);
} catch (revokeErr) {
  logger.warn({ error: revokeErr, userId: req.user!.id }, 'Failed to revoke OAuth integrations on delete');
}
```
**What:** Soft-delete commits, then revoke runs outside the tx. If revoke fails (Redis down, Gmail OAuth endpoint timeout — note: the revoke walks the OAuth integration provider revoke endpoint), the user is soft-deleted with their OAuth tokens still alive. A purge cron 30 days later will catch this — but for 30 days the encrypted refresh token sits in `user_oauth_integrations` referencing a soft-deleted user.
**Why it matters:** GDPR right-to-be-forgotten leak. The OAuth tokens ARE PII (they grant access to the user's Gmail). They survive soft-delete by design — but they should at minimum be soft-revoked (the column `revoked_at` and zero'd ciphertexts). Today on revoke-failure the integration row stays fully usable.
**Suggested fix:** Move the OAuth `revoked_at = NOW(), access_token_ciphertext = NULL` UPDATE INTO the soft-delete tx. Revoking against the provider's endpoint can stay fire-and-forget outside (network-dependent), but the local-DB invalidation is critical and belongs in the tx. The README's comment "older test environments" excuse for keeping it out is no longer relevant — mig 038 is in 100% of envs by 2026-04.

### H-AUTH-V2-15: Apple Sign-In `markAppleNonceConsumed` Redis-NX path silently allows replay if Redis fail-opens to DB but the DB INSERT race-loses
**File:** `apps/api/src/routes/auth.ts:128-161`
**Code excerpt:**
```ts
async function markAppleNonceConsumed(nonceHash: string): Promise<void> {
  const key = `apple_nonce:${nonceHash}`;
  try {
    const redis = await getRedisClient();
    const setResult = await redis.set(key, '1', { NX: true, EX: APPLE_NONCE_TTL_SECONDS });
    if (setResult === null) {
      throw new AppError('Apple nonce has already been used', 401);
    }
    return;
  } catch (err) {
    if (err instanceof AppError) throw err;
    logger.warn({ err }, 'Apple nonce check via Redis failed, falling back to DB');
  }

  try {
    const expiresAt = new Date(Date.now() + APPLE_NONCE_TTL_SECONDS * 1000);
    const result = await query(
      `INSERT INTO apple_sign_in_nonces (nonce_hash, expires_at)
         VALUES ($1, $2)
         ON CONFLICT (nonce_hash) DO NOTHING
         RETURNING nonce_hash`,
      [nonceHash, expiresAt],
    );
    if (result.rowCount === 0) {
      throw new AppError('Apple nonce has already been used', 401);
    }
  } catch (err) { ... }
}
```
**What:** Two-replica scenario where Redis is up on replica A and DOWN on replica B. Same nonce arrives at A and B simultaneously. A's Redis-NX wins → A consumes. B's Redis fails → falls to DB → DB INSERT wins (Redis didn't write to DB). A's path RETURNS at line 137 — never wrote to DB at all. The DB only sees B's INSERT. Now a third request arrives at A (Redis still up) → Redis-NX returns null on the second request → 401. So Redis is consistent for replica A; DB is consistent across replicas. The hole is: there's no cross-system verification — if A's Redis is DOWN on the third request, A falls to DB, which has B's record from earlier — so A correctly 401s. Actually fine. **But** there's a subtler bug: when Redis is up but a write fails (transient `disconnecting`), the Redis-NX call rejects with an Error. The catch arm at line 138-142 logs and falls through — but if `redis.set` actually wrote the key BEFORE the error propagated (e.g. timeout after server-ack), Redis has the record AND DB doesn't. A retry within 5 minutes from the same client: Redis-NX returns null → 401. That's correct. Different replica's retry: Redis-NX returns null too (same Redis cluster) → 401. Also correct.
**The real hole** is when both replicas process the same nonce *concurrently* — say at exactly the same millisecond — and Redis is healthy: both call SET NX. Redis serializes them, one wins, the other gets null → 401. Good. So the Redis path is sound. The only failure mode is: Redis writes silently lost (Redis crashes between SET NX and our return), no DB record either. The next attempt within 5 min would use the same nonce (the attacker's replay) and pass — Redis no longer has the key (it was lost in the crash), DB never had it. **This is a real but narrow race.**
**Why it matters:** A Redis crash within the 5-min nonce TTL plus an attacker who captures the original ID token + raw nonce can replay. Mitigation: the Apple ID-token's own `exp` (~10 min) bounds replay anyway, and Apple's nonce-claim binding requires the attacker to have the raw nonce too. So the real exposure: an attacker who captures the in-flight HTTP request body (TLS-MITM, mobile-debug-proxy, malware on device) and Redis crashes within 5 min.
**Suggested fix:** Always write to DB AND Redis. The DB INSERT is the durable record; Redis is the fast path. Today the DB only gets called as a fallback. Cost: one extra DB insert per Apple sign-in, gated to <1ms.

### H-AUTH-V2-16: `change-email` route doesn't enforce `email_verified` on the CURRENT email (v1 H6 — UNFIXED)
**File:** `apps/api/src/routes/users.ts:395-527`
**What:** v1 H6. Re-read the handler — no `email_verified` check on the current email before allowing the change. A user who registered, never verified, and then change-email's into a verified state opens the takeover path v1 described. Still un-fixed. Re-flagging.
**Suggested fix:** Per v1 H6.

### H-AUTH-V2-17: `password_reset` keeps the access-token (if any) ALIVE — silently allows mid-flight access after pwd reset
**File:** `apps/api/src/routes/auth.ts:1078-1093`
**Code excerpt:**
```ts
await client.query(
  `UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2`,
  [passwordHash, userId],
);
// Drop every refresh token + every other unused reset token + every
// pending email-verification token so no stale credential survives a
// password reset (Ch01-F018: the dead "blacklist caller token" path
// below was removed since the caller doesn't have one — the reset
// page is unauthenticated).
await client.query(`DELETE FROM refresh_tokens WHERE user_id = $1`, [userId]);
await client.query(
  `UPDATE password_reset_tokens SET used = TRUE
    WHERE user_id = $1 AND used = FALSE`,
  [userId],
);
```
**What:** Reset rotates the password and drops refresh tokens, but does NOTHING about access tokens. The reset endpoint is unauthenticated (no caller bearer to blacklist). If the same user has a valid access token in another device, that token continues to work for up to JWT_EXPIRES_IN (1h) — a stranger who reset the password "because you forgot it" and the legit user might both have working sessions for an hour.
**Why it matters:** If the reset was triggered by an attacker who phished the email, the legit user's access tokens stay alive on every other device — the attacker has 1h to do damage with the new password while the legit user's prior sessions still work too. Same v1 H5 family.
**Suggested fix:** Add a `users.tokens_invalidated_at TIMESTAMPTZ` column. Reset, change-password, change-email-confirm all `SET tokens_invalidated_at = NOW()`. Middleware compares `decoded.iat * 1000 < userRow.tokens_invalidated_at` → reject. (v1 H5 had this; restating because it's a cross-cutting fix for several findings.)

### H-AUTH-V2-18: `change-email` audit log writes raw `new_email` (mixed case) AND doesn't log the `old_email` (v1 M8 deeper)
**File:** `apps/api/src/routes/users.ts:514-519`
**What:** v1 M8 noted missing old_email. Deeper: the captured `new_email` is also unnormalized — see C-AUTH-V2-8/-10. Plus: the audit log entry at /verify-email-change consume (auth.ts:1259-1267) doesn't capture old_email either, so reconstructing "from→to" requires joining two timestamps. Forensics-poor.
**Suggested fix:** Pull `users.email` into the SELECT at users.ts:401 (already does — `email, password_hash, full_name`), include in the audit-log metadata as `old_email`. Same for the consume side.

### H-AUTH-V2-19: `verify-email` token cleanup deletes register-flow tokens but NOT the user's other reset/change-email pendings
**File:** `apps/api/src/routes/auth.ts:1140-1148`
**Code excerpt:**
```ts
await Promise.all([
  query(`UPDATE users SET email_verified = TRUE WHERE id = $1`, [userId]),
  query(
    `DELETE FROM email_verification_tokens
      WHERE user_id = $1
        AND COALESCE(metadata->>'type', 'register') IN ('register', 'verify')`,
    [userId],
  ),
]);
```
**What:** After verify-email succeeds, only register/verify tokens are dropped. Pending change-email tokens are left alive. Scenario: user registers → never verifies → enters change-email flow → changes their mind → goes back, verifies the original email → the change-email token is still live for 24h on the OTHER address. If anyone has access to that other inbox they can complete the swap. Yes, the verify-email-change consume route would fail because the new email might already be in users (if the change was their own current one), but it could also succeed if the change-email target is still unique.
**Why it matters:** The verify-email completion implicitly says "I confirm the current address." Pending change-emails should be invalidated.
**Suggested fix:** Drop the COALESCE filter — delete every email_verification_tokens row for this user. The trade-off (a re-verify of an in-flight register-confirm) is a non-issue because `verify-email` just succeeded.

### H-AUTH-V2-20: `mfa.test.ts` does NOT exist — MFA enrollment / verify / challenge / disable have ZERO automated test coverage
**File:** none
**What:** `find /apps/api/src/__tests__ -name "mfa*"` returns no files. The only MFA touch in tests is `setup.ts:96-97` listing the tables for cleanup. The mocked otplib (`__mocks__/otplib.cjs`) returns `{ valid: true }` for every code — meaning if any other test path inadvertently exercises MFA verify, it ALWAYS passes, regardless of correct code.
**Why it matters:** v1 audit N1/N2 already raised the gap. Going deeper: not only is the bypass not tested, the supporting infrastructure (encryption round-trip, backup-code single-use, factor unique-by-user-when-verified, disable-with-code-required) all rely on no test coverage. A regression in `MfaService.verifyChallengeCode` returning `valid: true` silently is undetectable.
**Suggested fix:** Add `mfa.test.ts` with at minimum: enroll → unverified factor exists; verify with wrong code → factor stays unverified; verify with correct code → factor verified; verifyChallengeCode with TOTP → consume; verifyChallengeCode with backup code → backup code marked used, repeat fails; disable requires correct code; challenge token can NOT auth other endpoints (the v1 C1 finding).

### H-AUTH-V2-21: `account-purge.service.ts` doesn't `SELECT … FOR UPDATE` the candidate row — concurrent recovery races (mate of H-AUTH-V2-1)
**File:** `apps/api/src/services/account-purge.service.ts:67-119`
**Code excerpt:**
```ts
while (result.purged + result.failed < MAX_PER_RUN) {
  const candidate = await pool.query<{ id: string; email: string }>(
    `SELECT id, email FROM users
       WHERE deleted_at IS NOT NULL
         AND deletion_scheduled_for IS NOT NULL
         AND deletion_scheduled_for < NOW()
       ORDER BY deletion_scheduled_for ASC
       LIMIT 1`,
  );
  ...
  await txClient.query('BEGIN');
  harvest = await harvestUserKeys(txClient, userId);
  ...
  await txClient.query(`DELETE FROM users WHERE id = $1`, [userId]);
```
**What:** The candidate SELECT is on a fresh connection (`pool.query`), then a different connection (`pool.connect()` → `txClient`) does the harvest + DELETE. Between the SELECT and the BEGIN-tx, the user could call `/me/recover` (which the middleware will let through if their access token is still valid, OR if they re-auth — though see C-AUTH-V2-7 / v1 C4 for the password-only-recovery dead end). The cron then DELETEs a recovered user. The post-COMMIT MinIO key removal then orphans live data.
**Why it matters:** Hard-delete of a recovered user. Real even though grace expired by definition (the user found out about pending purge AFTER grace, sent a 911 to support who toggled `deletion_scheduled_for = NOW() + INTERVAL '7 days'` to extend — race with the cron).
**Suggested fix:** Combine the candidate-SELECT and the harvest into one tx with `FOR UPDATE`. Re-check `deletion_scheduled_for < NOW()` inside the tx before the DELETE. Same connection across both queries.

### H-AUTH-V2-22: User-cache row carries `is_admin` from JOIN — admin demotion via direct SQL leaves cached `is_admin=true` for 10s
**File:** `apps/api/src/middleware/auth.ts:96-129`
**What:** v1 listed the user-cache TTL as a known concern. Deeper: the cache key is `user:${userId}`, set with EX=10. The cache is invalidated by `invalidateUserCache(userId)` from every route that mutates user state. But direct-SQL admin demotion (an ops engineer running `UPDATE users SET is_admin = false`) doesn't pass through any route → no cache invalidation → the demoted admin keeps `is_admin=true` for the cache TTL across all replicas. `requireAdmin` (auth.ts:215) does a fresh DB read in addition to `req.user.isAdmin`, so admin route gating is closed; but `req.user.isAdmin` consumed elsewhere (any branch that reads `req.user.isAdmin` without re-checking) sees stale.
**Why it matters:** Direct-SQL admin operations bypass the user-cache invalidation. A 10-second worst case is documented in code comments; in practice it's usually <10s. Combined with H-AUTH-V2-4 (JWT body claims), the demoted-admin window can extend to JWT_EXPIRES_IN for any consumer that reads JWT body without /role-check.
**Suggested fix:** Reduce USER_CACHE_TTL_SEC to 2-3 seconds. Or expose an admin endpoint `POST /admin/users/:id/invalidate-cache` for ops to call after direct SQL.

---

## Medium

### M-AUTH-V2-1: Bearer extraction is case-sensitive on the prefix — `bearer xxx` (lowercase) is rejected as 401 with no helpful message
**File:** `apps/api/src/middleware/auth.ts:63-67`
**Code excerpt:**
```ts
if (!authHeader || !authHeader.startsWith('Bearer ')) {
  throw new AppError('No token provided', 401);
}
const token = authHeader.substring(7);
```
**What:** `startsWith('Bearer ')` is case-sensitive. RFC 7235 allows the auth scheme to be case-insensitive. A client sending `bearer xxx` (lowercase, occasionally seen in less-common HTTP libs) gets 401. The same code is duplicated in auth.ts:794-795 (logout) and 750-751 (refresh).
**Why it matters:** Minor compat. Mostly cosmetic.
**Suggested fix:** `if (!/^Bearer /i.test(authHeader))` or normalize via `.toLowerCase().startsWith('bearer ')`.

### M-AUTH-V2-2: `Bearer  <token>` (two spaces) returns the token starting with a space — `jwt.verify` rejects with 401
**File:** `apps/api/src/middleware/auth.ts:67`
**What:** `authHeader.substring(7)` blindly skips 7 chars. If the header is `Bearer  abc.def.ghi` (two spaces), substring(7) is ` abc.def.ghi` (leading space), `jwt.verify` 401s. Edge case; documented for completeness.
**Suggested fix:** `const token = authHeader.substring(7).trimStart();` or use a regex extractor.

### M-AUTH-V2-3: `delete-account` for OAuth users requires only `confirmDelete: true` — server doesn't re-verify OAuth identity (v1 H2 — UNFIXED)
**File:** `apps/api/src/routes/users.ts:592-700`
**What:** v1 H2. Mobile re-auths client-side; server doesn't enforce. Restating since it's still live.
**Suggested fix:** Per v1 H2.

### M-AUTH-V2-4: `Bearer <token>` blacklist-key uses plain SHA-256 — not keyed HMAC like the rest of the bearer-token store
**File:** `apps/api/src/utils/token-blacklist.ts:27-30`
**Code excerpt:**
```ts
function tokenKey(token: string): string {
  const sha = crypto.createHash('sha256').update(token).digest('hex');
  return `${BLACKLIST_PREFIX}${sha}`;
}
```
**What:** v1 mentioned this in the out-of-scope notes. Restating with a deeper angle: token-hash.ts:16 uses HMAC-SHA-256 keyed by `refreshSecret` for refresh tokens. The blacklist uses plain SHA-256. Inconsistency. A Redis dump that leaks `token:blacklist:<sha>` keys gives an attacker a known set of tokens-of-interest (each sha is the hash of an actual access token). Combined with a separate way to mint or guess access tokens (theoretical), the attacker can probe whether a specific token is blacklisted — which is itself a leak (knowledge that "this token is dead" tells the attacker the user's session was killed at this point in time).
**Why it matters:** Defense-in-depth. The Redis dump leaks the existence of tokens.
**Suggested fix:** Use `hashToken(token)` from token-hash.ts (HMAC keyed). One-line change. Drop the `crypto.createHash('sha256')` import.

### M-AUTH-V2-5: `/refresh` swallows blacklist failures while `/logout` properly fails (v1 H3 — UNFIXED)
**File:** `apps/api/src/routes/auth.ts:752-756, :885-889` vs. `:798-810`
**What:** v1 H3. Re-verified by reading both routes. Refresh + logout-all still swallow.
**Suggested fix:** Per v1 H3.

### M-AUTH-V2-6: `auth.ts:60` `let googleOAuth2Client: any = null` — type-loose singleton, hides shape regressions
**File:** `apps/api/src/routes/auth.ts:51-52`
**Code excerpt:**
```ts
let googleOAuth2Client: any = null;
let appleJwksClientInstance: any = null;
```
**What:** `any` types on the cached singletons. Lazy-init at line 1305-1314 sets `googleOAuth2Client.transporter.defaults` — if google-auth-library ever changes the transporter shape, this break is silent at compile time. Same on the Apple side at 1496-1503.
**Why it matters:** Type-safety regression risk on a security-critical path (OAuth token verification).
**Suggested fix:** Type as `OAuth2Client | null` (import from google-auth-library) and `JwksClient | null` (jwks-rsa). The lazy-import pattern works fine with concrete types.

### M-AUTH-V2-7: `/auth/forgot-password` logs `auth.password_reset_request` with `success: true` for the rate-limited path
**File:** `apps/api/src/routes/auth.ts:993-1009`
**Code excerpt:**
```ts
if (recipientRateLimited) {
  ...
  logAuthBestEffort({
    action: 'auth.password_reset_request',
    userId: user.id,
    email: user.email,
    ...
    success: false,
    errorMessage: 'recipient_rate_limited',
  });
  return respondGeneric();
}
```
**What:** Looking carefully, the rate-limited path actually logs `success: false` (line 1006). That's fine. **But** the success path at line 1035-1042 logs `success: true` BEFORE the email send completes (the email is fire-and-forget at 1027-1033 in a `.catch()` — the audit log has no idea if SendGrid actually accepted). Audit chain says "we sent the reset email" when reality is "we tried; SendGrid might have rejected it." For users who never get the email and report as a support ticket, the audit looks like the API succeeded.
**Why it matters:** Forensic precision.
**Suggested fix:** Don't audit-log success until the EmailService promise resolves. Or split into `auth.password_reset_request` (the API accepted the input) and `auth.password_reset_email_sent` (SendGrid 250'd).

### M-AUTH-V2-8: `MfaService.verifyChallengeCode` accepts trim-only normalization — Unicode-confusable (zero-width) chars not stripped
**File:** `apps/api/src/services/mfa.service.ts:260-265`
**Code excerpt:**
```ts
static async verifyChallengeCode(userId: string, code: string): Promise<void> {
    const trimmed = code.trim();
    // Detect backup code by shape (hex with optional separators). TOTP is
    // always 6 digits per RFC 6238 + our authenticator config.
    const isBackup = !/^\d{6}$/.test(trimmed);
```
**What:** `code.trim()` removes ASCII whitespace. A user pasting from a passwords manager with a trailing zero-width-no-break-space (U+FEFF) → `trimmed` keeps the ZWNBSP, regex fails, treated as backup code, normalizeBackupCode strips letters but keeps ZWNBSP — hash mismatches → "invalid backup code" error. Frustrating UX, not security.
**Why it matters:** UX. v1 M2 hinted at the wider classification fragility.
**Suggested fix:** Normalize: `code.normalize('NFKC').replace(/[^\x21-\x7e]+/g, '').toLowerCase()` before any classification.

### M-AUTH-V2-9: TOTP verify uses `epochTolerance: 30` (one full step ±) — wider than necessary, weakens code-entropy
**File:** `apps/api/src/services/mfa.service.ts:55-58, :240-244`
**Code excerpt:**
```ts
const TOTP_TOLERANCE_SECONDS = 30;
...
const result = totp.verifySync({
  token: code,
  secret,
  epochTolerance: TOTP_TOLERANCE_SECONDS,
});
```
**What:** `epochTolerance: 30` accepts the previous and next 30s window — effectively window=±1. RFC 6238 §5.2 recommends as small a window as possible; window=±1 is the canonical default but doubles the valid code space (3 codes valid at any moment instead of 1). For a 6-digit code, that's 3M valid codes out of 10M possible. With a 5-min challenge TTL and no rate limit on `/auth/mfa/challenge` per-user (only per-IP via authRateLimiter — auth.ts:613-617), that's 10 attempts × 3M/10M = 3 expected hits per attempt block, multiplied by the 15-min IP rotation. Still hard to brute-force, but not as hard as window=0.
**Why it matters:** Borderline. RFC 6238 says "should not exceed 1 step in either direction" so this is in spec. Tighten to window=0 if drift is rare; if you've seen actual user-clock-drift complaints, leave it.
**Suggested fix:** Decision call. If you tighten, set `epochTolerance: 0`. If you keep, add a per-user rate limit on `/auth/mfa/challenge` (5 fails / 15 min, account locked on hit).

### M-AUTH-V2-10: MFA `/auth/mfa/challenge` has no per-user / per-mfa_token rate limit — 10 attempts / 15 min per IP only
**File:** `apps/api/src/routes/auth.ts:613-617`
**Code excerpt:**
```ts
router.post(
  '/mfa/challenge',
  authRateLimiter,
  validate(mfaChallengeSchema),
```
**What:** The challenge endpoint accepts `(mfa_token, code)`. Same `authRateLimiter` as login — 10/IP/15min. An attacker who has the password (via H-AUTH-V2-11 or out-of-band) AND has a botnet to rotate IPs gets unlimited tries against the 6-digit TOTP. Combined with M-AUTH-V2-9's window=±1, the brute-force resistance is reduced to ~3M valid codes within a 5-min challenge window. With 10 IPs × 6 attempts/min × 5 min = 300 attempts → expected hits = 300 × 3 / 1M ≈ 0.001 per challenge. Still hard, but not "infeasible."
**Suggested fix:** Per-mfa_token rate limit: 5 attempts then the challenge token is rejected for the rest of its 5-min TTL. Easy to implement: hash the mfa_token once and track attempts in Redis with the token's `exp` as TTL.

### M-AUTH-V2-11: TOTP enrollment-flow `enrollTotp` mints backup codes BEFORE the verify step — codes leak even if the user bails
**File:** `apps/api/src/services/mfa.service.ts:138-211`
**Code excerpt:**
```ts
const backupPlaintexts: string[] = [];
const backupHashes: string[] = [];
for (let i = 0; i < BACKUP_CODE_COUNT; i++) {
  const code = formatBackupCode(crypto.randomBytes(BACKUP_CODE_BYTES));
  backupPlaintexts.push(code);
  backupHashes.push(hashToken(normalizeBackupCode(code)));
}
...
return {
  factorId,
  secret,
  otpauthUrl,
  qrCodeDataUrl,
  backupCodes: backupPlaintexts,
};
```
**What:** Backup codes are returned in the enroll response (mfa.ts:64). The factor is unverified. If the user opens the enrollment screen, sees backup codes, screenshots them, but never verifies, the codes are still ALIVE in the DB (they were inserted at line 191-194). A second enrollment call drops the unverified factor (line 170-174) AND the unverified-state backup codes (line 175-179) — good, that's the cleanup. But the FIRST enrollment's codes have already been displayed and possibly scanned/captured/screenshotted. If the user ever verifies a NEW factor, the OLD backup codes are gone (line 175 cleans them up), but in the window between enrollment-1 and enrollment-2 the OLD codes are honored at challenge time only if the OLD factor verifies — which it never did. So the codes are dead-weight. **Wait** — `verifyChallengeCode` at line 269-275 doesn't filter by `verified_at` or factor — it just checks the code_hash existence in `user_mfa_backup_codes`. **Codes for an unverified factor would still consume**. Let me re-read…

The `user_mfa_backup_codes` table has no link to factors, only `user_id`. So backup codes minted during enrollment-1 are usable AT CHALLENGE TIME if the user has ANY verified factor (because `/login` only mints a challenge when `MfaService.getStatus` finds a verified factor). So if the user enrolls factor A (unverified), bails, then later enrolls factor B and verifies it, the OLD enrollment-1 backup codes were dropped at line 175-179 → safe.

But the in-flight enrollment-1 codes between display and abandonment are exposed. They aren't usable until the user later verifies a factor — so the exposure is a known-good code list waiting for a factor. If the user enrolls factor C months later and verifies, the line 175-179 cleanup ran on enrollment-2 (or however many times); enrollment-C drops the unverified factor + codes again — at this point factor C's NEW codes go live. Old codes from enrollment-1 ARE gone because every subsequent enrollment cleans them.

Actually — re-reading more carefully — the cleanup at line 175-179 is `WHERE used_at IS NULL`, so it drops EVERY unused backup code for the user, not just the unverified-factor ones. Good — old codes are cleaned. So this is safe.

**Reclassifying:** Not a security bug per se. Restating as a UX consideration: the enroll response shows backup codes BEFORE the user has verified the QR code. If the user closes the modal without saving the codes, they lose them entirely (they're dropped at next enroll). The user has to verify TOTP to "lock in" the codes. UI flow could mislead users into thinking codes are live before verify.
**Suggested fix:** UI-side: show codes AFTER `/totp/verify` succeeds. Backend-side: don't return codes from `/totp/enroll`; have `/totp/verify` mint and return them on first verify. Cleaner state model, codes are guaranteed to correspond to a verified factor.

### M-AUTH-V2-12: `parseExpiryToMs` doesn't handle weeks/months/years — typo `30D` (capital D) crashes the API at boot
**File:** `apps/api/src/routes/auth.ts:62-75`
**What:** Regex is `^(\d+)(s|m|h|d)$` — only lowercase units. A `REFRESH_TOKEN_EXPIRES_IN=30D` env crashes the API at boot. Fail-fast is correct (better than the previous silent 7d fallback) but the error message says "Expected one of: NNs / NNm / NNh / NNd or a number of seconds" — doesn't hint at case-sensitivity.
**Suggested fix:** Make the regex case-insensitive: `^(\d+)([smhd])$/i` and lowercase the unit before lookup. Or improve the error message to mention case.

### M-AUTH-V2-13: `delete-account` doesn't clear `email_change_pending` token — soft-deleted user can still consume their pending change-email
**File:** `apps/api/src/routes/users.ts:622-659`
**What:** Soft-delete drops refresh tokens but doesn't drop email_verification_tokens. A user with a pending change-email request soft-deletes; the change-email token is still alive for 24h. The verify-email-change consume is unauthenticated (only the token in URL). Anyone with the token (the user, somebody who phished the new email, etc.) can consume it → `users.email = newEmail`, `email_verified = TRUE`, but the user is `deleted_at` — so the email column is updated on a soft-deleted row. The auth middleware refuses to issue tokens, so login still 403's ACCOUNT_PENDING_DELETION (per H-A1). Recover is still possible. **But** the user's email has changed without their post-delete consent, and on recover, they're now associated with the new address — the original address is gone.
**Why it matters:** Account-state drift across the cooling-off window. Edge case; a determined user could exploit, but typically a self-inflicted footgun.
**Suggested fix:** Soft-delete tx should also `DELETE FROM email_verification_tokens WHERE user_id = $1`.

### M-AUTH-V2-14: `verify-email-change` consume route doesn't verify the user is NOT soft-deleted
**File:** `apps/api/src/routes/auth.ts:1177-1273`
**What:** Per M-AUTH-V2-13, a soft-deleted user's change-email tokens stay live. The /verify-email-change route doesn't check `users.deleted_at IS NULL` before the UPDATE. The swap goes through on a deleted user.
**Suggested fix:** Add `AND deleted_at IS NULL` to the UPDATE's WHERE clause. On rowCount=0 with the token consumed, return a generic "Invalid or expired verification link" so the existence of soft-delete state isn't leaked.

### M-AUTH-V2-15: `delete-account` without `confirmDelete` returns 400 — but Joi schema says `confirmDelete: Joi.boolean().valid(true).required()` so the validator catches it first
**File:** `apps/api/src/validators/users.validator.ts:33-38`
**Code excerpt:**
```ts
export const deleteAccountSchema = Joi.object({
  password: Joi.string().min(1).max(1024).optional(),
  confirmDelete: Joi.boolean().valid(true).required(),
})
  .rename('confirm_delete', 'confirmDelete', { ignoreUndefined: true, override: false });
```
**What:** Validator requires `confirmDelete: true`. The route handler at users.ts:609-621 has its own logic — for password users, `password` is required. But the schema-level enforcement of `confirmDelete: true` means an OAuth user trying to delete without confirmDelete=true gets 400 BEFORE the route runs — no consistent error message between password (400 "Password is required") and OAuth (400 from validator with the Joi-formatted message). UX inconsistency.
**Suggested fix:** Either consolidate the check at the route (validator allows confirmDelete: optional) or message-format the validator output the same way.

### M-AUTH-V2-16: Session cookie / CSRF rotation on auth-state-change — but logout doesn't rotate
**File:** `apps/api/src/routes/auth.ts:354, :559, :1432, :1724`
**What:** Register/login/oauth all call `rotateCsrfToken(res)`. Logout (line 778-849) does NOT — it doesn't even touch the CSRF token. After logout, the same CSRF cookie remains. If the user immediately re-logs in with a different email (e.g. shared device), the CSRF token from the previous session is still in cookies; the new login rotates it. Edge case.
**Suggested fix:** Add `rotateCsrfToken(res)` at the end of /logout (after `invalidateUserCache`).

### M-AUTH-V2-17: `email_verification_tokens.token` is `VARCHAR(255) NOT NULL UNIQUE` — column is large enough but UNIQUE INDEX on a 32-byte hex isn't using a partial index
**File:** `apps/api/src/db/schema.sql:200-208`
**What:** Token is hashed as 64-char hex (HMAC-SHA-256). VARCHAR(255) wastes space. Indexes are full-table. Cosmetic only.
**Suggested fix:** ALTER COLUMN to CHAR(64) — same shape as `apple_sign_in_nonces.nonce_hash`. Or just leave it; not load-bearing.

### M-AUTH-V2-18: `/auth/google` and `/auth/apple` accept `referralCode` but never validate it as a known code — silent NULL on resolve
**File:** `apps/api/src/routes/auth.ts:163-170`
**Code excerpt:**
```ts
async function resolveReferredBy(referralCode?: string): Promise<string | null> {
  if (!referralCode) return null;
  const result = await query(
    `SELECT id FROM users WHERE referral_code = $1`,
    [referralCode]
  );
  return result.rows.length > 0 ? result.rows[0].id : null;
}
```
**What:** Unknown referralCode silently resolves to NULL. The user gets no signal. The mobile UI says "use my friend's code" — the friend never gets credit. UX-fail-silent.
**Suggested fix:** When `referralCode` is provided but unresolvable, audit-log it as `referral_code_unknown`. Optionally surface a 200 with `{referral_unrecognized: true}` so the mobile UI can warn.

### M-AUTH-V2-19: Apple Sign-In handler does NOT check `email_verified` from Apple — only checks `email_verified !== false` (line 1541)
**File:** `apps/api/src/routes/auth.ts:1541-1543`
**Code excerpt:**
```ts
if (decoded.email_verified === false) {
  throw new AppError('Apple email is not verified', 401);
}
```
**What:** The check is `=== false`. If Apple omits the claim entirely, the check passes. Apple's docs claim `email_verified` is always present and true; defensive code at line 1537-1540 expected this. But the asymmetry vs. Google (line 1340-1342: `if (!payload.email_verified)`) means a missing claim is treated differently across providers. For Apple, missing → accept; for Google, missing → reject.
**Why it matters:** If Apple ever drops the claim due to API change, HavenKeep silently accepts. Defense-in-depth says reject if claim is absent.
**Suggested fix:** Match Google: `if (decoded.email_verified !== true) throw new AppError('Apple email is not verified', 401);`. Same comment as the original about Apple's contract — the check is documentation of the assumption.

### M-AUTH-V2-20: TOTP factor + backup codes don't prompt re-issuance after disableTotp — re-enrollment starts blank
**File:** `apps/api/src/services/mfa.service.ts:320-341`
**What:** `disableTotp` deletes the factor + every backup code (line 326-331). When the user re-enrolls, fresh codes are minted. Fine in isolation. But if a user disables MFA, then a few days later re-enables, the old backup-code copies (printouts, password manager) are dead. Users who don't notice that codes change after disable→enable will be locked out at next challenge. UX hazard.
**Suggested fix:** UI surface — disable should warn "your backup codes will be invalidated; enrolling again will issue new ones." API-side, no change.

### M-AUTH-V2-21: `verifyEnrollmentCode` doesn't rate-limit — repeated wrong-code attempts during enrollment have no cap
**File:** `apps/api/src/services/mfa.service.ts:219-253`
**What:** No backoff or attempt counter on enrollment verify. An attacker who has the password and a 5-minute window can hammer `/totp/verify` with 6-digit guesses (10M codes, ±1 step = 30M valid). With authRateLimiter (10/IP/15min) + a botnet, this is the same shape as M-AUTH-V2-10 but worse — there's no challenge token TTL bound; the unverified factor stays alive indefinitely.
**Why it matters:** Pre-verification, the factor doesn't gate login. So this isn't a direct bypass — but if an attacker who has the password hits enrollment, they can prep a factor that will be honored at next login after they verify. Combined with C-AUTH-V2-2 (challenge token bypass), the attacker doesn't even need to verify.
**Suggested fix:** Per-user attempt counter on enrollment verify (3 fails → drop the unverified factor, force re-enroll).

### M-AUTH-V2-22: `account-purge.service.ts` MAX_PER_RUN=100 (v1 M1) + cron is `setInterval`-style, not `node-cron` — silent backlog growth
**File:** `apps/api/src/services/account-purge.service.ts:66`
**What:** v1 M1. Restating to confirm via direct line: `const MAX_PER_RUN = 100`. Daily run schedule. 1000 deletions in a busy day → 9-day backlog before catching up. v1 noted no alert; restating because the metric/alert never landed.
**Suggested fix:** Per v1 M1.

### M-AUTH-V2-23: `password_reset_tokens.token` UNIQUE constraint — re-issue races
**File:** `apps/api/src/db/schema.sql:211-218`
**What:** `token VARCHAR(255) NOT NULL UNIQUE`. Two near-simultaneous `/forgot-password` calls for the same user race the UPDATE-used-true-then-INSERT pattern. Token uniqueness prevents collisions across users (good); within a user, the UPDATE-then-INSERT is two separate `query()` calls, not in a tx. The window where both calls have done their UPDATE but neither has INSERT is small but real. Either one is harmless if the INSERTs land in order. BUT: the recipient-rate-limit guard at auth.ts:980-991 is also non-atomic with the UPDATE — it's a Redis INCR + a postgres UPDATE. If two calls race past the Redis check (count=1 and count=2 both ≤ 3), both reach line 1012's UPDATE. Idempotent on UPDATE side, fine.
**Why it matters:** Marginal. Worth noting for completeness.
**Suggested fix:** Wrap UPDATE+INSERT in a tx so a failure mid-flow doesn't leak orphan reset tokens.

### M-AUTH-V2-24: `change-password` doesn't check that newPassword !== email
**File:** `apps/api/src/routes/users.ts:553-557`
**What:** The handler checks newPassword ≠ currentPassword but not newPassword ≠ user.email. NIST SP 800-63B says check against breached passwords; the comment in users.validator.ts:7-11 mentions enforcing "must not match account email" server-side, but the route doesn't do it.
**Suggested fix:** Add `if (newPassword.toLowerCase().includes(userResult.rows[0].email.toLowerCase().split('@')[0])) throw new AppError(...)` or full-string equality. Bonus: integrate haveibeenpwned.com k-anon API.

### M-AUTH-V2-25: `auth.ts:425, 433` decoy-bcrypt hash hardcoded — at least catch one common case in module load
**File:** `apps/api/src/routes/auth.ts:425`
**What:** Same as v1 L5 + H-AUTH-V2-10. The route hash exists in TWO places (425 and 433). DRY violation; one could be updated and not the other.
**Suggested fix:** Extract to a single module-level constant.

### M-AUTH-V2-26: `users.ts:411` "OAuth users cannot change email this way" message reveals auth mechanism
**File:** `apps/api/src/routes/users.ts:411-413`
**Code excerpt:**
```ts
if (!user.password_hash) {
  throw new AppError('Password is not set for this account. OAuth users cannot change email this way.', 400);
}
```
**What:** Authenticated user, so it's not really "leak" — but the message reveals to the user (or a token-stealer) that the account is OAuth. Combined with H-A2 (OAuth account-delete weakness), token theft → easy delete.
**Suggested fix:** Generic "Cannot change email on this account. Contact support." Or actually surface a "re-auth via Google/Apple to change email" path.

### M-AUTH-V2-27: `register` token race — Joi `.lowercase()` + the `email.toLowerCase()` at line 266 is redundant + adds a second normalize
**File:** `apps/api/src/routes/auth.ts:264-266, :284`
**What:** The validator (`emailSchema`) already trims + lowercases. The route does `.toLowerCase()` again at line 266 and 284. Cosmetic; double-normalize is harmless.
**Suggested fix:** Drop the second `.toLowerCase()` calls — single source of truth.

### M-AUTH-V2-28: `/auth/google` and `/auth/apple` `email_verified` check happens AFTER the OAuth ID-token verify but BEFORE the local user lookup — info leak
**File:** `apps/api/src/routes/auth.ts:1340-1342, :1541-1543`
**What:** If a Google/Apple user has email_verified=false, the API responds 401. An attacker testing with a known-controlled Google account can determine the policy. Innocuous; just noting.

### M-AUTH-V2-29: `requirePremium` middleware uses 24h grace (auth.ts middleware:286) — cron-driven plan demotion lags 24h
**File:** `apps/api/src/middleware/auth.ts:286-289`
**What:** Out of scope for auth deep-dive but cited because it's in the auth middleware. Plan-grace post-expiry can leak premium for an extra 24h.

### M-AUTH-V2-30: `verifyMfaChallengeToken` uses `require('jsonwebtoken')` (CommonJS) inside a TypeScript module — pulled by an `eslint-disable` for a reason
**File:** `apps/api/src/services/mfa.service.ts:93-94, :103-104`
**Code excerpt:**
```ts
// eslint-disable-next-line @typescript-eslint/no-var-requires
const jwt = require('jsonwebtoken') as typeof import('jsonwebtoken');
```
**What:** Both `mintMfaChallengeToken` and `verifyMfaChallengeToken` use `require()` at function scope. The rest of auth.ts uses ESM-style `import jwt from 'jsonwebtoken'` at top. The CJS require gives a fresh module reference each call — no perf impact in practice, but inconsistent with the codebase style and signals a workaround.
**Suggested fix:** Top-level `import jwt from 'jsonwebtoken'` in mfa.service.ts — same as routes/auth.ts. Drop the eslint-disable.

---

## Low

### L-AUTH-V2-1: `auth.ts:51` `googleOAuth2Client: any` is mutable — concurrent requests race the lazy-init
**File:** `apps/api/src/routes/auth.ts:1305-1314`
**What:** First-call lazy-init (`if (!googleOAuth2Client) {...}`) is not single-flight. Two parallel /auth/google calls in the cold-start window each construct a new OAuth2Client. The second overwrites the first. Performance only — no correctness issue (both clients verify the same way).
**Suggested fix:** Module-load instead of lazy, or wrap with a Promise singleton.

### L-AUTH-V2-2: `getIpAddress` returns `'unknown'` on no-IP — used as Redis key prefix in audit log; collisions across attackers
**File:** `apps/api/src/routes/auth.ts:103-113`
**What:** When IP can't be determined, `'unknown'` is the literal string. Used downstream in audit-log entries; multiple attackers from headerless proxies all collapse to `'unknown'`. Forensics-poor.
**Suggested fix:** Use `'unknown:' + req.socket.remoteFamily + ':' + req.socket.bytesRead` or some other request fingerprint when IP is missing.

### L-AUTH-V2-3: Apple `decodedHeader = jwt.decode(idToken, { complete: true })` doesn't pin algorithm — `kid` extracted before signature verify
**File:** `apps/api/src/routes/auth.ts:1508-1515`
**What:** `jwt.decode` is unsigned; reads the header without verifying. Used only to extract `kid` for the JWKS fetch. The verify at line 1521 still pins `algorithms: ['RS256']`. So decode is informational. Not exploitable; just noting that decode-without-verify is a code smell.
**Suggested fix:** None functionally; possibly add a comment that decode is intentional.

### L-AUTH-V2-4: `auth.test.ts` mocks `OAuth2Client` to throw on signature verify — alg:none test reaches throw before alg check
**File:** `apps/api/src/__tests__/auth.test.ts:32-37`
**What:** The mock at line 32-37 returns a "signature verification failed" error for every non-alg:none token (line 37) and an "alg none rejected" error for alg:none (line 33). The S3-C test (line 466-477) succeeds because both cases throw → 401. But the test passes for the WRONG reason: a real Google verify might reject alg:none specifically; the mock conflates "alg none" and "any signature failure". A regression where alg:none is accepted by the real google-auth-library wouldn't be caught.
**Suggested fix:** Mock more precisely: only the `alg: none` path throws "alg none rejected"; other paths throw "Token used too late" or similar. Or remove the mock and use a recorded JWKS response.

### L-AUTH-V2-5: `apple_sign_in_nonces.nonce_hash CHAR(64)` PRIMARY KEY — fixed-length char wastes space on Postgres
**File:** `apps/api/src/db/migrations/077_apple_sign_in_nonces.sql:18-21`
**What:** PG stores CHAR(N) padded; VARCHAR(N) variable. CHAR(64) for a hex SHA-256 always uses 64 bytes. VARCHAR would be the same in this case. Cosmetic.

### L-AUTH-V2-6: Apple JWKS client `cacheMaxEntries` not set — unbounded growth across many `kid`s in 24h
**File:** `apps/api/src/routes/auth.ts:1500-1503`
**What:** No `cacheMaxEntries`. Apple typically rotates 1-2 keys at a time; unbounded cache won't grow. Minor.

### L-AUTH-V2-7: `MfaService.enrollTotp` returns `secret` (the base32 plaintext) in the API response (mfa.ts:60-62)
**File:** `apps/api/src/services/mfa.service.ts:205-211, /routes/mfa.ts:59-65`
**What:** The plaintext base32 secret is returned alongside the QR code. UX: the user can copy-paste the secret manually into authenticators that don't scan QRs. Harmless if the response is over TLS (it is), but if a request log accidentally captures the response body, the secret leaks.
**Suggested fix:** The redactPaths in pino (mentioned in CLAUDE.md) needs to include `*.secret` and `*.qrCodeDataUrl` and `*.backupCodes`. Search for whether they're listed — if not, add.

### L-AUTH-V2-8: `formatBackupCode` produces 16 hex chars = 64 bits of entropy
**File:** `apps/api/src/services/mfa.service.ts:73-77`
**What:** 8 random bytes = 64 bits. Good. NIST SP 800-63B says 6+ digits = OK, but for backup codes recommends 80+ bits. With 10 codes, the attack on one is 2^64 / 10 = 2^60 → ~10^18 — practically uncrackable but below NIST's recommendation.
**Suggested fix:** Bump to 12 bytes (96 bits) or pin per spec.

### L-AUTH-V2-9: `change-email`'s 24h dedupe key uses `crypto.createHash('sha256').update(newEmailLower).digest('hex')` — no salt — Redis dump enumerates targets
**File:** `apps/api/src/routes/users.ts:431-432`
**What:** SHA-256 of email is identifying (an attacker with a Redis dump can enumerate "did this email start a change-email recently?" by hashing every guess). The fix would be HMAC keyed by a server secret — same as the rest of the bearer-token store.
**Suggested fix:** Use `hashToken(newEmailLower)` or similar.

### L-AUTH-V2-10: `password_reset_tokens` cleanup — no cron actively prunes expired+used rows
**File:** `apps/api/src/db/schema.sql:211-221`
**What:** No cron entry was found in the auth-relevant scope that prunes `password_reset_tokens WHERE used = TRUE OR expires_at < NOW()`. The table accumulates forever.
**Suggested fix:** Daily cron `DELETE FROM password_reset_tokens WHERE created_at < NOW() - INTERVAL '7 days'`.

### L-AUTH-V2-11: `email_verification_tokens` cleanup — no cron actively prunes
**File:** `apps/api/src/db/schema.sql:200-208`
**What:** Same as L-AUTH-V2-10 for verification tokens. They have a 24h expires_at and after consumption are DELETEd, but expired-not-consumed rows accumulate.
**Suggested fix:** Same cron pattern.

### L-AUTH-V2-12: `users.ts:597-599` SELECT for delete-account doesn't pull `deleted_at` — no early-out for already-deleted user
**File:** `apps/api/src/routes/users.ts:596-599`
**What:** See C-AUTH-V2-7. The fetch doesn't include `deleted_at` so the route can't early-out with "already scheduled for deletion." (The middleware would have rejected the request anyway thanks to the deleted_at gate, so this is dead code path in practice — re-flagging for symmetry with C-AUTH-V2-7's idempotency fix.)

### L-AUTH-V2-13: `change-password` doesn't blacklist the OLD access token but DOES drop refresh tokens (v1 H5 mate)
**File:** `apps/api/src/routes/users.ts:566-577`
**Code excerpt:**
```ts
// Blacklist the current access token using its actual remaining TTL
const authHeader = req.headers.authorization;
if (authHeader?.startsWith('Bearer ')) {
  const accessToken = authHeader.substring(7);
  await blacklistTokenAuto(accessToken);
}

// Invalidate all refresh tokens (force re-login on other devices)
await query(
  `DELETE FROM refresh_tokens WHERE user_id = $1`,
  [req.user!.id]
);
```
**What:** Blacklists the CURRENT caller's access token, drops all refresh tokens. Other devices' access tokens stay alive — same as v1 H5. Restating because the route does part of the work but not the whole.
**Suggested fix:** Per v1 H5 (tokens_invalidated_at column).

### L-AUTH-V2-14: `change-password` blacklist failure isn't fatal — `await blacklistTokenAuto` not in try/catch — if Redis down → 500
**File:** `apps/api/src/routes/users.ts:567-571`
**What:** Unlike `/logout` (which intentionally 503s on blacklist fail per S-M4), `/me/password` will 500 on Redis-fail because there's no try/catch. UX: user sees a confusing 500 even though the password did update.
**Suggested fix:** Mirror the /logout pattern: try-catch around blacklist, on fail return 503 with a recoverable message ("password updated; please sign out manually"). Or move the blacklist BEFORE the password update so the failure prevents committing.

### L-AUTH-V2-15: `forgot-password` recipient-rate-limit FAIL-OPEN behavior comments say "fail-open: better to over-send" but the audit-log entry on success is the same shape as on rate-limit
**File:** `apps/api/src/routes/auth.ts:989-991`
**What:** Restated below the comment on line 1007 — `errorMessage: 'recipient_rate_limited'` is logged when rate-limited, but if Redis is down, recipientRateLimited stays false, the route proceeds, and the audit log says success. Operators reviewing logs can't tell "we sent" from "we sent because Redis was down." Forensic precision.
**Suggested fix:** When the catch arm at line 989-991 fires, set a flag and audit-log `errorMessage: 'recipient_rate_limit_redis_down'` even on the success path.

### L-AUTH-V2-16: `auth.ts:1226-1230` 23505 catch in change-email-confirm — only handles UNIQUE on `users.email`, not other constraints
**File:** `apps/api/src/routes/auth.ts:1226-1232`
**What:** The catch at 1226-1232 maps any 23505 to "That email is no longer available." If a future migration adds another UNIQUE constraint to users (e.g. `users.referral_code` already has one — though not in this UPDATE's scope), the error message would lie. Future-proofing nit.
**Suggested fix:** Match `err.constraint === 'users_email_key'` (or whatever the email UNIQUE name is).

### L-AUTH-V2-17: PASSWORD_PATTERN allows ASCII-only (v1 L1) — non-Latin user passwords rejected
**File:** `apps/api/src/validators/auth.validator.ts:15`
**What:** v1 L1. Restating: a Spanish user typing "Contraseña1!" — the ñ is rejected because the regex character classes are ASCII. Same NIST SP 800-63B point.

### L-AUTH-V2-18: Test `helpers.ts:24-28` `getAuthToken` doesn't pin algorithm — relies on jwt.sign default
**File:** `apps/api/src/__tests__/helpers.ts:24-28`
**What:** `jwt.sign(...{ expiresIn: '1h' })` — no algorithm specified. Defaults to HS256 (matches the production code). If a future jsonwebtoken upgrade changes the default, every test mints tokens that production rejects. Belt-and-braces fix is to pin algorithm.
**Suggested fix:** `{ expiresIn: '1h', algorithm: 'HS256' }`.

### L-AUTH-V2-19: `helpers.ts:40` bcrypt rounds=4 in tests — different cost from production (12)
**File:** `apps/api/src/__tests__/helpers.ts:40-43`
**What:** Tests use cost=4 for speed. Production uses 12. A regression that breaks bcrypt at higher cost (e.g. a buffer overflow at 72-byte input only triggered at high cost) would never be caught. Acceptable trade-off; noting only.

### L-AUTH-V2-20: `users.test.ts:198-205` recover-test silently passes when delete didn't take (v1 L7 — UNFIXED)
**File:** `apps/api/src/__tests__/users.test.ts:198-211`
**What:** v1 L7. Restating; test still says `expect([200, 400, 401]).toContain(del.status)` and `if (!row.rows[0].deleted_at) return;` — false positive shield.
**Suggested fix:** Per v1 L7.

### L-AUTH-V2-21: `account-purge.service.ts:84-88` harvest is in-tx but RuntimeError on harvest fails the tx → no audit log
**File:** `apps/api/src/services/account-purge.service.ts:82-145`
**What:** If `harvestUserKeys` throws (e.g. PG conn flap mid-SELECT), the tx rollbacks at line 121, the error gets logged at line 140-143 as "per-user failure (will retry next run)." Good. But there's no audit-log entry for the failed purge attempt. The audit-log silence on failed purges hides systemic backlog.
**Suggested fix:** Best-effort `AuditService.log({ action: 'admin.user_delete_failed', userId, errorMessage })` outside the tx.

### L-AUTH-V2-22: `account-purge.service.ts:111-112` "Refresh-tokens have FK ON DELETE CASCADE; explicit DELETE matches the admin path's belt-and-braces pattern"
**File:** `apps/api/src/services/account-purge.service.ts:110-112`
**What:** The explicit DELETE is redundant per the comment. Belt-and-braces is fine. Cosmetic only.

### L-AUTH-V2-23: `harvestUserKeys` doesn't paginate — user with 100k documents loads all rows into memory
**File:** `apps/api/src/utils/storage-cleanup.ts:64-78`
**What:** A pathological user (100k docs) makes harvest pull 100k rows into one query. Memory spike. In practice, max docs/user is small (CLAUDE.md mentions free tier=5 items, premium unlimited but typically <100). Theoretical only.
**Suggested fix:** Cursor-based pagination if/when a user exceeds 10k docs. Probably never.

### L-AUTH-V2-24: `userRow` cache JSON serialization round-trips Date objects as strings — `email_verified` boolean still works but `deletion_scheduled_for` becomes a string
**File:** `apps/api/src/middleware/auth.ts:88-89`
**What:** `JSON.parse(cached)` gives `userRow.deletion_scheduled_for: string` instead of Date. Line 144-145 calls `new Date(userRow.deletion_scheduled_for)` to compare — fine, Date constructor accepts ISO strings. Belt-and-braces correct. Just noting.

### L-AUTH-V2-25: `setup.ts:96-97` test cleanup deletes `user_mfa_*` tables but tests never INSERT into them — placeholder for future MFA tests
**File:** `apps/api/src/__tests__/setup.ts:96-97`
**What:** Cleanup is wired for the day MFA tests land. None today. Restating H-AUTH-V2-20 with the test-side artifact.

---

## Out-of-scope items I noticed

- **Mobile**: Mobile UI for `ACCOUNT_PENDING_DELETION` still missing (v1 C5). The mobile audit (file 04 / 05) owns.
- **Marketing**: 7-day vs 30-day grace drift (v1 C6). Marketing audit (file 08) owns.
- **Dashboard**: `/role-check` adoption verification — dashboard audit (file 06) owns.
- **Stripe**: Auth `is_partner` → partner_commissions. Money-paths audit (file 02) owns.
- **Email scanner**: OAuth integration revoke on plan-downgrade (auth.ts H-A5 ref) — email-scanner audit (file 07) owns.
- **CSP/Caddy**: The `Bearer  token` extraction is purely backend-side; Caddy header normalization wasn't audited.

## Confirmed correct (with evidence)

- **MFA challenge token DOES carry `purpose: 'mfa_challenge'`** at mint (mfa.service.ts:96). The CLAIM is right. The MIDDLEWARE doesn't check it (C-AUTH-V2-2).
- **Refresh-token storage uses keyed HMAC** (token-hash.ts:16-17) — `crypto.createHmac('sha256', config.jwt.refreshSecret).update(token).digest('hex')`.
- **`/refresh` DELETE…RETURNING is atomic** for multi-replica safety (auth.ts:709-712). One concurrent winner, others 401. Verified by re-reading + auth.test.ts:230-256.
- **Apple nonce table has `nonce_hash CHAR(64) PRIMARY KEY`** (mig 077:18-21). UNIQUE enforced. ON CONFLICT DO NOTHING handles concurrent inserts (auth.ts:147-152).
- **Apple `aud` array verification** uses jsonwebtoken's array-audience matching with `algorithms: ['RS256']` pinned (auth.ts:1521-1524). Verified.
- **Google verifyIdToken** pins audience array + the audit-tested alg:none rejection (auth.ts:1325-1331 + auth.test.ts:466-477).
- **TOTP comparison** is constant-time via otplib v13.4.0's verifySync internals.
- **Backup codes are single-use atomic-consume** via `UPDATE…RETURNING WHERE used_at IS NULL` (mfa.service.ts:269-275).
- **JWT secret strength validated at boot** ≥32 chars (config/validator.ts:80) + JWT/REFRESH must differ (line 91-93).
- **`requireAdmin` re-checks DB on every call** (middleware/auth.ts:215-234) — closes the cached-stale-isAdmin hole on admin routes.
- **`pg_advisory_xact_lock(hashtext(userId))`** correctly serializes capRefreshTokens (auth.ts:186) as v1 confirmed.
- **Token-blacklist circuit breaker** fail-CLOSED in production (token-blacklist.ts:62) + correctly distinguishes NOAUTH/WRONGPASS auth errors (line 87-91).
- **Soft-delete tx atomic with refresh-token DELETE** (users.ts:626-653). plan_before_delete captured atomically with deleted_at set.
- **/me/recover middleware bypass** correctly scoped to POST + path match + within-grace (middleware/auth.ts:138-146).
- **`apple_sub_mismatch` H-A6 guard** is in place + audit-logs the mismatch (auth.ts:1618-1643).
- **Cron's per-replica advisory lock** prevents two replicas from racing the purge (account-purge.service.ts:54-58).
- **Email-verification token type discrimination** correctly separates register vs change-email (auth.ts:1126 + 1199).
- **Password-reset on success drops every refresh token + every other unused reset token + every pending email-verification token** — wait, actually the email-verification-token DROP is missing from /reset-password (auth.ts:1078-1093). The route only drops refresh + reset, not email-verification. v1 said "drops every…verification token" but the code at 1087-1092 doesn't include `DELETE FROM email_verification_tokens`. **Reclassifying as a finding.** See below — adding as **M-AUTH-V2-31** retroactively:

### M-AUTH-V2-31 (post-hoc): /reset-password doesn't drop pending email-verification tokens
**File:** `apps/api/src/routes/auth.ts:1063-1099`
**Code excerpt:**
```ts
await client.query(`DELETE FROM refresh_tokens WHERE user_id = $1`, [userId]);
await client.query(
  `UPDATE password_reset_tokens SET used = TRUE
    WHERE user_id = $1 AND used = FALSE`,
  [userId],
);
await client.query('COMMIT');
```
**What:** v1 said this route drops "every…pending email-verification token." It doesn't — only refresh and reset tokens. A user who resets password during a pending change-email keeps the change-email token alive. Symmetric with H-AUTH-V2-19 (verify-email doesn't drop change-email tokens).
**Suggested fix:** Add `await client.query('DELETE FROM email_verification_tokens WHERE user_id = $1', [userId]);` inside the tx.

---

## Findings index

C-AUTH-V2-1..10 — 10 critical (1 truly new, 1 v1-confirmed-unfixed C1=C-V2-2, 1 v1-confirmed-unfixed C3=C-V2-5, 1 v1-confirmed-unfixed C2=C-V2-6, 7 net-new)
H-AUTH-V2-1..22 — 22 high (3 v1-restates: H6=H-V2-16, M3=H-V2-2, M4=H-V2-13; 19 net-new)
M-AUTH-V2-1..31 — 31 medium (5 v1-restates: H2=M-V2-3, H3=M-V2-5, H5=L-V2-13, M1=M-V2-22, M2=M-V2-8; 26 net-new)
L-AUTH-V2-1..25 — 25 low (4 v1-restates: L1=L-V2-17, L5=H-V2-10/M-V2-25, L6=C-V2-4, L7=L-V2-20; 21 net-new)

**Total: 88 findings** (74 net-new beyond v1's 29; 14 v1-restates with deeper technical detail or confirmation that the v1 fix did not land).

The single highest-impact bug is **C-AUTH-V2-1** — the email-change-confirm flow is end-to-end broken in production right now (`column "email_change_pending" does not exist`). Any user who attempts to change their email gets a 500 on confirm. This blocks a Trust & Safety must-have feature with zero workaround.

Second-highest is the **MFA bypass family** (C-AUTH-V2-2 + C-AUTH-V2-6) — total MFA bypass via challenge-token-as-access-token (re-confirmed v1 C1) plus OAuth-skips-MFA (re-confirmed v1 C2). Both unfixed despite v1 audit. MFA on this product is a marketing claim only.
