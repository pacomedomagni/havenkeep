# 09 — Middleware Chain, CORS, Helmet, Rate Limiting, Caddy: Deep Audit

Run date: 2026-05-10
Scope: `apps/api/src/app.ts`, `apps/api/src/index.ts`, `apps/api/src/middleware/*.ts`, `apps/api/src/utils/{redis,token-blacklist,logger,errors,ip-address,lifecycle,async-handler}.ts`, `apps/api/src/config/{index,validator,minio}.ts`, `apps/api/src/routes/{health,csrf,uploads,documents,receipts}.ts` (multer surfaces), `apps/api/Dockerfile`, `apps/api/package.json`, `caddy/havenkeep.caddyfile`. Cross-cutting checks against every `routes/*.ts` for middleware application.

Format: A–N sections per the brief, then a numbered findings list (F-01 onward).

---

## A. Express bootstrap (apps/api/src/app.ts)

### A1. Middleware chain order
Order in `createApp()`:

1. `app.set('trust proxy', N)` — `TRUST_PROXY_HOPS` env, default `1` (app.ts:48-49)
2. `helmet({...})` — security headers (app.ts:54-97)
3. `cors({ origin: <function>, credentials: true, ... })` (app.ts:104-116)
4. `express.raw({ type: 'application/json', limit: '1mb' })` mounted under `/api/v1/webhooks/stripe` + `stripeWebhookRouter` (app.ts:136-140)
5. `express.json({ limit: '1mb', strict: true })` (app.ts:146)
6. `express.urlencoded({ extended: true, limit: '1mb' })` (app.ts:147)
7. `compression()` (app.ts:154)
8. `revenueCatWebhookRouter` mounted under `/api/v1/webhooks/revenuecat` (app.ts:157)
9. `cookieParser()` (app.ts:160)
10. `requestLogger` (app.ts:164)
11. `options.rateLimiter` (the global IP limiter from `initializeRateLimiter()`) (app.ts:168-170)
12. `setCsrfToken` + `validateCsrfToken` (app.ts:174-175)
13. `healthRoutes` mounted at `/` (app.ts:179)
14. `apiV1` router mounted at `/api/v1` (app.ts:207)
15. 404 handler (app.ts:210-215)
16. `errorHandler` (app.ts:218)

### A2. Helmet — CSP

```ts
contentSecurityPolicy: {
  directives: {
    defaultSrc: ["'self'"],
    styleSrc: ["'self'", "'unsafe-inline'"],
    scriptSrc: ["'self'"],
    imgSrc: [
      "'self'",
      'data:',
      'https://lh3.googleusercontent.com',
      'https://lh4.googleusercontent.com',
      'https://lh5.googleusercontent.com',
      'https://lh6.googleusercontent.com',
    ],
    connectSrc: [
      "'self'",
      'https://api.stripe.com',
      'https://api.revenuecat.com',
    ],
    frameAncestors: ["'none'"],
    objectSrc: ["'none'"],
    baseUri: ["'self'"],
    formAction: ["'self'"],
  },
}
```
- `script-src 'self'` only — no `'unsafe-inline'`/`'unsafe-eval'`. Good.
- `connect-src` covers Stripe + RevenueCat.
- `frame-ancestors 'none'`.
- `object-src 'none'`.
- `style-src 'unsafe-inline'` is included. The API does not render HTML, so this is moot for browsers, but the directive is still emitted on every API response.

HSTS:
```ts
hsts: { maxAge: 31536000, includeSubDomains: true, preload: true }
```
Plus COOP=`same-origin`, COEP=`require-corp`, CORP=`same-origin`, Referrer-Policy=`strict-origin-when-cross-origin`.

### A3. CORS

```ts
cors({
  origin: (origin, cb) => {
    if (!origin) return cb(null, true);                 // server-to-server, curl, mobile
    if (config.cors.origins.includes(origin)) return cb(null, true);
    return cb(new Error(`CORS: origin not allowed (${origin})`));
  },
  credentials: true,
  methods: ['GET','POST','PUT','DELETE','PATCH'],
  allowedHeaders: ['Content-Type','Authorization','x-csrf-token','x-request-id','idempotency-key'],
  exposedHeaders: ['x-request-id'],
})
```
- Function form (rejects unknown origins with an Error, which Express then surfaces).
- `credentials: true`.
- `origins` come from `CORS_ORIGINS` env, comma-split (config/index.ts:240-244).
- No `maxAge` — preflight cache uses the browser default (usually 5s for Chrome, 600s for Firefox). This means each new path triggers an OPTIONS round-trip frequently.
- `OPTIONS` is **not** in `methods`. The `cors` package handles preflight separately so this is fine, but worth flagging that custom OPTIONS handlers won't see it.
- No `HEAD` — clients that call `HEAD /api/v1/...` get rejected at preflight.
- Empty-origin requests (mobile, curl) bypass the allowlist via `if (!origin) return cb(null, true)`. That's the intended behavior, but it means `Origin: null` (sandboxed iframe, file://) is also accepted.

### A4. Body parsing

- Stripe webhook (`/api/v1/webhooks/stripe`): `express.raw({ type: 'application/json', limit: '1mb' })` mounted **before** `express.json` (app.ts:136-140). Mounting the raw + router as a unit at the exact path means `express.json` can never accidentally pre-parse this path even on a future re-order. Documented inline.
- RevenueCat webhook (`/api/v1/webhooks/revenuecat`): mounted **after** `express.json` so it gets the parsed body. RC sends a JSON body with HMAC over the raw bytes — verify in section L below.
- `express.json({ limit: '1mb', strict: true })`.
- `express.urlencoded({ extended: true, limit: '1mb' })`.
- `multer` is per-route (uploads.ts, documents.ts, receipts.ts). See section H.

### A5. Trust proxy
`app.set('trust proxy', N)` where `N = TRUST_PROXY_HOPS || 1` (app.ts:48-49). Behind a single Caddy this is correct. **However**, `getIpAddress` in `utils/ip-address.ts` reads `TRUST_PROXY_HOPS` independently and walks XFF from the right by `N`. If a future deploy bumps `TRUST_PROXY_HOPS` to `2` for a 2-hop chain, both Express and `getIpAddress` agree. **But** `getIpAddress` casts to `Number(... ?? '1')` (no `parseInt`) and clamps to `>=0`; `app.ts` uses `parseInt(... || '1', 10)`. Both reach `1` for a missing var, but for `TRUST_PROXY_HOPS=true` they diverge: `app.ts` → NaN → `Number.isFinite` → fallback `1`; `getIpAddress` → `NaN` → `Math.max(0, NaN)` = NaN → idx = NaN → falls through to socket. Inconsistent, low-impact.

### A6. Compression
Mounted **after** `express.json`. Order is `body-parse → compression → routes`. The Stripe raw mount is **before** `express.json`, and the compression middleware decompresses request bodies (Content-Encoding) — so a Stripe request with `Content-Encoding: gzip` would (a) be raw-parsed first into a Buffer of compressed bytes, and (b) signature would fail because Stripe signs the encoded payload. In practice Stripe never sends gzip-encoded webhooks, so this is theoretical. Outbound responses (Stripe is a webhook source, not a target) aren't affected.

### A7. Cookie parser
`cookie-parser` is mounted **after** `compression()` (app.ts:160). Required for CSRF middleware which reads `req.cookies?.[CSRF_COOKIE]`. Order is fine.

### A8. Pino-http logger
**Not used.** A custom `requestLogger` middleware (middleware/requestLogger.ts) is mounted instead. It does NOT call `pino-http`; it generates a request id and emits one log line on `res.on('finish')`. Redaction lives in `utils/logger.ts` which configures pino with `REDACT_PATHS`. See section F.

### A9. Error handler
Registered **last** at app.ts:218. Operational `AppError` → status + JSON; JWT errors → 401; PG errors mapped via `pgErrorToApp`; everything else → generic 500 (with stack only in dev/test). See section G.

### A10. 404 handler
```ts
app.use((req, res) => res.status(404).json({ error: 'Not found', suggestion: 'Check API documentation for available endpoints' }));
```
Mounted before `errorHandler`. Note: this uses a different envelope (`{ error, suggestion }`) than the rest of the API (which uses `{ success: false, error, code, statusCode, requestId }` from errorHandler). Inconsistent shape — finding F-01.

### A11. /health
`routes/health.ts:27`: pings `pool.query('SELECT 1')`, returns `status: ok` + uptime + env on success, `503 status: degraded + safeMessage(err)` on failure. `safeMessage` redacts password=, token=, secret=, postgres://, redis:// patterns from the error.

### A12. /health/detailed
`routes/health.ts:47`: gated `authenticate, requireAdmin`. Reports per-component status for DB, Redis (via shared client + ping), MinIO (`bucketExists`). Uses `safeMessage` for any leaked error. No queue depth, no replication lag, no TLS info — clean.

`/ready` (routes/health.ts:97): respects `isShuttingDown()` to flip 503 immediately on SIGTERM (drain pattern). `/live` (line 120): trivial 200.

---

## B. Rate limiting

### B1. Global limiter (`initializeRateLimiter`)
- In production / staging: `RedisStore` (sliding window via Lua: `ZREMRANGEBYSCORE` + `ZADD` + `ZCARD` + `EXPIRE`, atomic). 
- In dev/test: in-memory with `max * 10`.
- Window: 15 min, max 100/IP (config/index.ts:246-249).
- 429 handler returns `{ error, message, retryAfter }` and logs at `warn` with `ip, path, userAgent`.
- Skip list: `/api/v1/webhooks/*` and exact paths `/health`, `/live`, `/ready` (PROBE_PATHS Set, line 10).
- Production fail-fast on Redis unavailability — `logger.fatal` then `throw` (line 134-136). No silent memory fallback.

### B2. Redis client
Shared client from `utils/redis.ts`. 30s TCP ping interval, exponential backoff reconnect capped at 10 retries / 15s max delay. The rate limiter calls `getSharedRedisClient()` (rateLimiter.ts:16-18). Module-level `sharedRedisClient` is set in `initializeEndpointRedis()` which is awaited from `start()` AFTER `waitForDatabase` (index.ts:525).

### B3. Per-route limits

| Limiter | Bucket | Window | Max | Key | Used by |
|---|---|---|---|---|---|
| `authRateLimiter` | `auth` | 15 min | 10 | IP | register, login, refresh, logout (refresh), reset-password, verify-email, change-email body, google, apple, mfa enroll/verify/disable |
| `refreshRateLimiter` | `refresh` | 15 min | 10 | IP | logout |
| `uploadRateLimiter` | `upload` | 1 min | 10 | IP | uploads/avatar, uploads/item-image, documents/upload |
| `passwordResetRateLimiter` | `pwReset` | 1 hr | 3 | IP | forgot-password |
| `activationCodeRateLimiter` | `activation` | 15 min | 10 | IP | partners/gifts/verify-code |
| `verifyPremiumRateLimiter` | `verifyPremium` | 15 min | 5 | IP | users/me/verify-premium |
| `passwordChangeRateLimiter` | `pwChange` | 1 hr | 5 | IP | users/me/password |
| `writeRateLimiter` | `write` | 15 min | 30 | IP | wide use across CRUD |
| `giftResendRateLimiter` | `giftResend` | 1 hr | 3 | IP | partner gift email resend |
| `receiptScanRateLimiter` | `receiptScan` | 1 min | 10 | IP | receipts |
| `itemsListRateLimiter` | `itemsList` | 1 min | 60 | IP | items list |
| `csvExportRateLimiter` | `csvExport` | 1 hr | 5 | IP | items CSV export |
| `newsletterRateLimiter` | `newsletter` | 1 hr | 5 | IP | newsletter subscribe/unsubscribe |
| `contactRateLimiter` | `contact` | 1 hr | 3 | IP | contact form |
| `readRateLimiter` | `read` | 1 min | 120 | IP | warranty-claims GET, audit/logs GET, contact admin list |
| `changeEmailRateLimiter` | `changeEmail` | 1 hr | 3 | **userId or IP** | change-email |
| `emailScannerScanRateLimiter` | `emailScannerScan` | 1 hr | 5 | **userId or IP** | email-scanner/scan |
| `emailScannerWriteRateLimiter` | `emailScannerWrite` | 15 min | 30 | **userId or IP** | email-scanner mutation actions |

### B4. Per-IP vs per-user
Most limiters are per-IP. The three with `keyGenerator: (req) => req.user?.id ?? req.ip ?? 'unknown'` correctly fall back to IP for anonymous (which shouldn't happen on `authenticate`-gated routes).

### B5. Login throttle
`authRateLimiter` — 10 / 15 min per IP. **Not per-email.** Two real impacts:
- Behind a NAT'd corporate proxy, 10 employees attempting password reset/login from the same egress IP exhaust the budget very quickly.
- An attacker controlling many IPs (botnet, residential proxies) defeats it.
The mobile/dashboard auth UX accepts this — but spreading email-resolution attempts across IPs is the obvious bypass. F-02.

### B6. Forgot-password
`passwordResetRateLimiter` — 3 / hour per IP. Same bucket regardless of whether the email exists, so no enumeration via different limits. The handler always returns the same response shape (auth.ts has the constant-200 pattern).

### B7. OAuth code-exchange
`router.post('/google', authRateLimiter, ...)` and `router.post('/apple', authRateLimiter, ...)` — share the auth bucket. Reasonable.

### B8. Redis-down behavior (rate limiter)
At boot in production: `initializeRateLimiter()` throws → process exits. After boot: each per-endpoint limiter is constructed lazily on first request via `createEndpointRateLimiter`. If the shared Redis client is null when an endpoint limiter is built (because `initializeEndpointRedis()` failed silently — line 243-244 logs error but does NOT throw), it falls back to in-memory store. **This is per-instance, not distributed.** Production with N replicas effectively gets N×max throughput. F-03.

### B9. Retry-After
The custom 429 handler returns `retryAfter: <seconds>` in the body (rateLimiter.ts:111). It does NOT set the HTTP `Retry-After` header — `standardHeaders: true` lets express-rate-limit emit `RateLimit-Reset` instead. Browsers/SDKs that honor `Retry-After` won't read the JSON body. F-04.

### B10. Skip-on-success / skip-on-failure
Default for all per-endpoint limiters: count every request including 4xx/5xx. `refreshRateLimiter` explicitly sets `skipSuccessfulRequests: false` for clarity. No limiter sets `skipFailedRequests`. So a 401 on `/auth/login` still consumes a token — that's the correct anti-brute-force behavior.

### B11. Burst vs sustained
Sliding window over `windowMs`. No separate burst bucket. The Lua script is atomic (sliding-window over Redis ZSET); no token-bucket layered on top. For most routes this is fine; for `readRateLimiter` (120/min) a 60-burst followed by 60 spread will pass once and 429 the next.

### B12. X-RateLimit-* headers
`standardHeaders: true` (RFC 6585 / IETF draft) — emits `RateLimit-Policy`, `RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset`. `legacyHeaders: false` — no `X-RateLimit-*`. The custom 429 handler in the GLOBAL limiter (rateLimiter.ts:101-113) doesn't add these headers manually; express-rate-limit emits them before the handler runs, so they survive. **However**, the global limiter overrides via `handler:` does NOT pass `RateLimit-Reset` through explicitly, but `standardHeaders` populates them on the response object before `handler` writes JSON, so they survive — verified by reading express-rate-limit v7 source behavior in code.

### B13. Trust-proxy + req.ip
`req.ip` is used directly in `rateLimiter.ts:103` for the 429 log. Express resolves `req.ip` from XFF when `trust proxy` is set. With `trust proxy=1`, behind a single Caddy adding `X-Forwarded-For: <client>`, `req.ip` is the client. If a request arrives without going through Caddy (i.e. directly hitting port 3000 inside the cluster), `req.ip` is the sender's socket address. The XFF spoof scenario is in section L.

---

## C. Auth middleware (cross-cutting role)

### C1. authenticate vs optionalAuth
- `authenticate` is exported. **`optionalAuth` does not exist** — there is no optional-auth path. Routes that need to behave differently for anonymous vs logged-in users do per-route handling (e.g. partners.ts public endpoints sit OUTSIDE `router.use(authenticate)` — they're declared before line 232).
- Routers that mount `authenticate` globally:
  - admin.ts:30, audit.ts:12, barcode.ts:13 (+ requirePremium), homes.ts:13, categories.ts:14, documents.ts:20, email-scanner.ts:19 (+ requirePremium), mfa.ts:26, stats.ts:13, items.ts:31, maintenance.ts:20, warranty-purchases.ts:22, receipts.ts:17, notifications.ts:20, uploads.ts:22, warranty-claims.ts:19, partners.ts:232 (only for routes declared after that line — public partner gift routes precede it), users.ts:36.
- `auth.ts`, `webhooks.ts`, `health.ts`, `csrf.ts`, `newsletter.ts`, `contact.ts` do NOT mount `authenticate` globally.

### C2. Bypass list
- The "soft-deleted user can still POST /me/recover during grace" carve-out is enforced inside `authenticate` itself (auth.ts:138-146). The `recoverBypass` flag short-circuits BOTH `deleted_at` and `plan === 'suspended'` checks.
- Any route calling `authenticate` requires a JWT. There is no "anonymous-when-no-Authorization" branch — missing/invalid header → 401.

### C3. requireAdmin / requirePartner / requireAdminOrPartner
- `requireAdmin` (auth.ts:215-234): re-reads `users.is_admin` from DB on every call (no cache). Falls through to next on confirmed `is_admin=true`. Documented anti-stale-cache.
- `requirePartner` is **not exported from middleware/auth.ts**. There is a `requirePartner` defined locally in `routes/partners.ts:70` that simply checks `req.user?.isPartner`. No fresh DB re-check — relies on the 10s Redis user-cache staleness. F-05.
- `requireAdminOrPartner` (auth.ts:264-269): cache-only check (`req.user.isAdmin || req.user.isPartner`). No fresh DB re-check.
- `requirePremium` (auth.ts:271-292): cache-only `plan === 'premium'`, with 24h grace past `plan_expires_at`. NULL `plan_expires_at` is honored as non-expiring lifetime entitlement.
- `verifyAdminFresh(userId)` exported but only used by routes/audit.ts (lines 42, 112) for branch-on-admin (not gate). Returns `false` on lookup failure — fail-closed.

### C4. User cache key + TTL
- Key: `user:<id>` (Redis).
- TTL: 10 seconds (`USER_CACHE_TTL_SEC`, auth.ts:12).
- Stored fields: `id, email, plan, is_admin, plan_expires_at, email_verified, deleted_at, deletion_scheduled_for, is_partner` (the EXISTS partner check). Comments call out that any UPDATE to these columns must `invalidateUserCache(userId)` to prevent up-to-10s staleness on other replicas.

### C5. Cache-bust call sites
22 call sites of `invalidateUserCache`:
- auth.ts:838 (logout), 1152 (verify-email), 1257 (verify-email-change)
- users.ts:133, 316, 663, 739, 941 (PUT /me, password change, email-change confirm, deletion paths, etc.)
- admin.ts:327, 402, 588, 647 (admin actions on users / partner approvals)
- webhooks.ts:788, 961, 1341, 1406, 1456, 1519, 1540 (Stripe / RC events that flip plan or partner state)

Audit-trace looked clean — every place that mutates plan/admin/email_verified/deleted_at flips the cache. **However**, the gift-activation flow (partners.ts gift activation) only calls `invalidateUserCache` from inside the webhook handler (not the immediate POST that flips `is_partner`). There's at least one path I could not confirm hits invalidateUserCache: `POST /partners/register` (line 280-290) calls `PartnersService.registerPartner` which inserts into `partners` — but the user's `is_partner` is JOIN-derived, so the next /me read after the cache TTL (10s) refreshes naturally. **Not** broken, but the comment at auth.ts:39-45 says "Call from any event that mutates fields the cache stores" and partner-register fits that description. F-06.

---

## D. Idempotency middleware

### D1. middleware/idempotency.ts (full review)
- Opt-in per route via `idempotency('routeKey')` factory.
- Reads `Idempotency-Key` header; if absent, passes through.
- Looks up `request_idempotency` row by `(user_id, route_key, idempotency_key)` with `expires_at > NOW()`.
- **Hit + same body hash** → replays cached `response_status`, `response_json`. Short-circuits before route handler. (idempotency.ts:79)
- **Hit + different body hash** → 409 `AppError`.
- **Miss** → wraps `res.json` so the first 2xx response is persisted via `INSERT ... ON CONFLICT DO NOTHING`.
- Body cap: 32 KB (`MAX_RESPONSE_BYTES`). Larger responses log a warning and skip persist.
- Default TTL: 24 hours (`DEFAULT_TTL_SECONDS`). Per-route override via `opts.ttlSeconds`.

### D2. Route-key derivation
Caller-supplied string scope (`'items:create'`, `'documents:upload'`, etc.). Not auto-derived from path/method — clean for renames, brittle if a developer copies code and forgets to bump the routeKey.

### D3. Body-hash component
`crypto.createHash('sha256').update(JSON.stringify(req.body ?? {})).digest('hex')`. JSON.stringify is **not deterministic** for object key order — two semantically identical requests with different field order would produce different hashes and trip the 409. F-07. Mitigation in code: relies on the comment "routes never mutate the body before the middleware runs" + clients normally don't shuffle keys, but it IS a bug.

### D4. Response cache
JSON-only. The `serialize` step uses `JSON.stringify(body)` and skips persist on circular ref / BigInt (logs warning).

### D5. Concurrent same-key handling
**No locking.** Two near-simultaneous requests with the same `Idempotency-Key`:
- Both miss the SELECT.
- Both proceed into the handler.
- The handler should rely on its own DB-level uniqueness (`ON CONFLICT DO NOTHING` etc.). Comment at idempotency.ts:25-27 explicitly calls this out.
- Both will try to INSERT into `request_idempotency` — `ON CONFLICT DO NOTHING` means whichever lands second silently drops; whichever lands first is the cached response. Can produce **inconsistent** behavior: client gets the second response, but the cached row is the first. F-08.

### D6. TTL
24h default. The pruning cron runs daily (`pruneExpiredIdempotencyRows`) — see section I.

### D7. Failure mode (Redis is irrelevant — this is Postgres)
A DB error during the SELECT logs warning and **continues** — handler runs, no replay protection. A DB error during INSERT logs warning and **doesn't fail** the response (already sent via `originalJson`). Both correct fail-modes.

---

## E. CSRF middleware

### E1. middleware/csrf.ts (review)
- Cookie name: `csrf_token`, header: `x-csrf-token`. 32-byte hex token (256 bits).
- Cookie options: `httpOnly: false` (JS-readable for double-submit), `secure: true` in prod, `sameSite: 'lax'`, `maxAge: 24h`.
- `setCsrfToken` (line 45): rolls the cookie forward if already present. Does NOT mint for anonymous traffic (audit S-ME-02 fixed token-fixation by removing the unconditional mint).
- `rotateCsrfToken(res)` (line 62): invoked by auth handlers (login, register, refresh, OAuth-google, OAuth-apple, verify-email, etc. — 7 call sites in auth.ts).
- `validateCsrfToken` (line 98): bypass when **no cookies at all** are present. Otherwise, double-submit must match (constant-time compare).

### E2. CSRF bypass model
The bypass is `Object.keys(req.cookies ?? {}).length > 0` — i.e. ANY cookie. Mobile + curl + server-to-server have no cookies → skip. Browser session w/ cookie → must double-submit. Documented at csrf.ts:80-96.

### E3. Constant-time compare
`constantTimeEquals(a, b)`:
```ts
if (a.length !== b.length) return false;
const bufA = Buffer.from(a, 'utf8');
const bufB = Buffer.from(b, 'utf8');
return crypto.timingSafeEqual(bufA, bufB);
```
Length-mismatch short-circuit leaks token-length differential, but both tokens are always 64-char hex from the rotation function — fixed length in practice. F-09 is theoretical only.

### E4. Methods covered
Skips `GET`, `HEAD`, `OPTIONS`. All others (POST, PUT, PATCH, DELETE) require double-submit if any cookie is present.

### E5. Stripe / RevenueCat webhook bypass
Both webhook routes are mounted **before** `setCsrfToken` / `validateCsrfToken` in app.ts (Stripe at line 136, RC at line 157, CSRF middleware at line 174-175). They never see CSRF middleware. ✓

### E6. The "no-cookie bypass" gives mobile + dashboard-proxy traffic free passage. The dashboard proxy strips cookies before forwarding, so the API never sees them — dashboard relies on its own proxy-layer CSRF check (apps/partner-dashboard middleware). Comment at csrf.ts:88-96 documents the cross-app invariant.

---

## F. Request logger (middleware/requestLogger.ts)

### F1. Pino-http? No.
A custom middleware. Generates a request id (validates incoming `x-request-id` against `/^[A-Za-z0-9._-]{1,64}$/`, otherwise mints a `crypto.randomUUID()`), runs the rest of the request inside an `AsyncLocalStorage` store, emits ONE log line on `res.on('finish')` keyed on duration:
- `>= 5000ms` → `logger.warn` "Slow request (>5s)"
- `>= 1000ms` → `logger.info` with `slow: true`
- otherwise → `logger.info` "Request completed"

### F2. Redact paths
`utils/logger.ts:22-65` defines `REDACT_PATHS`. Covers:
- `req.headers.authorization`
- `req.headers.cookie`
- `req.headers["x-csrf-token"]`
- `req.headers["x-api-key"]`
- `req.headers["stripe-signature"]`
- `res.headers["set-cookie"]`
- Body fields: `password`, `password_hash`, `passwordHash`, `token`, `refresh_token`, `access_token`, `id_token`, `code`, `activation_code`, `image`, `api_key`, `stripe_secret_key`
- Glob variants for nested objects: `*.password`, `*.token`, `*.api_key`, `*.stripeSecretKey` etc.

**Missing** redactions worth flagging:
- `req.body.email` is NOT redacted. Login POSTs log full email in metadata. PII concern. F-10.
- `req.body.totp` / `req.body.totp_code` / `req.body.mfa_code` (MFA endpoints) — not redacted.
- `req.headers["x-revenuecat-signature"]` — not redacted (the `stripe-signature` header is, but RC's isn't).
- `req.body.stripeAccountId` / `req.body.payment_method_id` — Stripe object IDs aren't secrets per se, but worth mentioning.
- `req.body.client_secret` — not in the list.

### F3. Serializers
None defined. Pino's defaults log `req` and `res` as the bound objects (depends on what the caller passes; the requestLogger passes a `meta` object, not `req` itself). The `errorHandler` passes `{ err, ...rest }` → pino's default `err` serializer covers it.

### F4. Levels
- Default: `info` (prod) / `debug` (dev) — line 70.
- 4xx errors → `warn`; 5xx → `error` (errorHandler.ts:62-64).

### F5. Loki transport
None in code — pino emits JSON to stdout, Promtail on the host scrapes it (per CLAUDE.md). Pretty-print only in dev (`pino-pretty`).

### F6. PII in request body
The custom logger does NOT log `req.body`. Each `info` line carries `method, path, statusCode, durationMs, userAgent, ip`. The `errorHandler` includes `path, method` and (in dev) the error message + stack. So baseline request logs are PII-clean. The PII risk is when downstream code calls `logger.warn({ err, body })` directly — relies on `REDACT_PATHS` glob coverage.

### F7. genReqId
Custom: `incoming = req.get('x-request-id')` → if matches `/^[A-Za-z0-9._-]{1,64}$/` use it, else `crypto.randomUUID()`. Set on both `req.headers` and `res.setHeader`. Threaded through `AsyncLocalStorage` so every nested log line carries it.

---

## G. Error handler

### G1. errorHandler.ts (full review) — see read.
### G2. AppError + ValidationError — utils/errors.ts (full review):
```ts
export class AppError extends Error {
  statusCode: number;
  code: AppErrorCode;
  cause?: unknown;
}
export class ValidationError extends AppError {
  details: ValidationDetail[];  // 400, VALIDATION_ERROR
}
```

### G3. Error envelope
```ts
{ success: false, error: <message>, code: <AppErrorCode>, statusCode, requestId, details?, message?, stack? }
```
Consistent across AppError, JWT errors, and PG-mapped errors. The 404 handler uses a different shape (see F-01).

### G4. 5xx body — leaks?
Production: only `{ success: false, error: 'Internal server error', code: 'INTERNAL', statusCode: 500, requestId }`. No stack, no message. Dev/test (`isDev` from NODE_ENV): adds `message` and `stack`.

### G5. 5xx logging
`logger.error({ err, stack: err.stack, path: req.path, method: req.method }, 'Unexpected error')`. The `err` object is passed to pino's err serializer.

### G6. PG error mapping
`pgErrorToApp`:
- `23505` (unique violation) → 409 CONFLICT
- `23503` (FK violation) → 409 CONFLICT
- `23502` (NOT NULL) → 400 VALIDATION_ERROR (not 500)
- `22001` (string-too-long) → 400 VALIDATION_ERROR
- `22P02` (invalid enum / wrong type) → 400 VALIDATION_ERROR
- `57P03` (cannot_connect_now) → 503 UNHEALTHY

**Not covered**: `23514` (CHECK constraint), `40001` (serialization failure), `40P01` (deadlock), `42P01` (undefined table). These fall through to "Unexpected" 500. F-11.

### G7. Joi mapping
ValidationError hands its `details: [{ field, message }]` array to the envelope. errorHandler picks it up at line 83.

### G8. Unknown errors
Generic 500 with INTERNAL code; only dev sees the message + stack.

---

## H. Multer configs (file uploads)

Three handlers, three different shapes:

### H1. uploads.ts (uploads/avatar, uploads/item-image)
```ts
multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024, files: 1 },
  fileFilter: (req, file, cb) => {
    const allowedMimes = ['image/jpeg','image/png','image/webp','image/heic','image/heif'];
    if (allowedMimes.includes(file.mimetype)) cb(null, true);
    else cb(new Error(`File type not allowed: ${file.mimetype}`));
  },
})
```
- Memory storage (10MB into V8 heap). Comment at receipts.ts says memory is fine because the file goes straight to OpenAI; here the file goes to sharp + MinIO. 10MB × concurrent uploads × N workers = heap pressure. Documents.ts switched to disk for the same reason; uploads.ts didn't. F-12.
- The fileFilter doesn't allow PDF (uploads is images-only). **PDF is allowed by `isMimeTypeAllowed` (used by documents.ts)** but blocked here.

### H2. documents.ts
```ts
multer({
  storage: multer.diskStorage({}),  // OS tmpdir
  limits: { fileSize: 10 * 1024 * 1024, files: 5 },
  fileFilter: (req, file, cb) => {
    if (isMimeTypeAllowed(file.mimetype)) cb(null, true);
    else cb(new Error(`File type not allowed: ${file.mimetype}`));
  },
})
```
- Disk storage with `multer.diskStorage({})` — empty options use multer's defaults: `os.tmpdir()` + a random filename. Caller must clean up after response close (multer handles this via `fs.unlink` on response close).
- **Up to 5 files per request × 10MB = 50MB of disk write.**
- File-cleanup: relies on multer's auto-cleanup on response close. If the process crashes mid-request, tmp files leak. F-13.

### H3. receipts.ts
```ts
multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024, files: 1 },
  fileFilter: (req, file, cb) => {
    if (isMimeTypeAllowed(file.mimetype) && file.mimetype.startsWith('image/')) cb(null, true);
    else cb(new Error(`File type not allowed: ${file.mimetype}`));
  },
})
```
- 5MB hard cap (smaller than uploads.ts because the image goes straight to OpenAI as base64).
- Memory storage is correct here.

### H5. fileFilter
Documented above. **Note that uploads.ts uses a literal allowlist** while documents.ts uses the shared `isMimeTypeAllowed` (which includes PDF). Inconsistent — F-12.

### H6. Multer error mapping
Multer errors (e.g. `LIMIT_FILE_SIZE`, fileFilter cb errors) propagate as plain `Error`. They reach `errorHandler` as "unknown error" → generic 500 instead of 413 (size) or 400 (type). The test at `__tests__/documents.test.ts:230-250` documents this: "400 (fileFilter) | 413 (size) | 500 (multer wrap) | ECONNRESET" — the response is non-deterministic. F-14.

### H7. Image-specific limits
- `assertNotZipBomb` (utils/file-validation.ts:79) rejects PNG IHDR > 32768 width/height OR > 100M pixels, and PDF object spam > 50k.
- `validateMagicBytes` confirms file magic matches the declared MIME type. SVG / octet-stream / polyglots → rejected by default (`return false`).
- `SHARP_INPUT_OPTIONS` (utils/sharp-config.ts) sets the per-image pixel cap.

---

## I. Cron jobs (registered in index.ts)

All run as `runWithAdvisoryLock(lockId, label, fn)` → acquires `pg_try_advisory_lock`, runs fn, unlocks. Failure inside fn is caught and logged.

### I1. NOTIFICATION_JOB_LOCK (93422874) — daily expiration notifications
`runExpirationNotificationsJob` → `NotificationsService.checkAndNotifyExpirations()`. Fires from `runJobs()` at the daily deadline (NOTIFICATION_HOUR_UTC, default 14:00 UTC).

### I2. MAINTENANCE_JOB_LOCK (93422875) — daily maintenance reminders
`runMaintenanceDueJob` → `NotificationsService.checkAndNotifyMaintenanceDue()`.

### I3. WARRANTY_OFFERS_JOB_LOCK (93422876) — daily warranty-offer pings
`runWarrantyOffersJob` → `NotificationsService.checkAndNotifyWarrantyOffers()`.

### I4. PARTNER_GIFT_EXPIRY_LOCK (93422877) — partner gifts past expires_at
`expireUnactivatedPartnerGifts()` (index.ts:87-121). Wipes `activation_code` + `activation_url` plaintext at the terminal transition.

### I5. PARTNER_COMMISSION_AUTO_APPROVE_LOCK (93422878) — collision with DIGEST_FLUSH_LOCK
`autoApproveAgedPendingCommissions()` (index.ts:136-169). Hold window: `COMMISSION_AUTO_APPROVE_HOLD_DAYS=30` env, default 30. **Lock ID 93422878 is reused for `DIGEST_FLUSH_LOCK` (index.ts:470).** Two distinct logical jobs share the same Postgres advisory lock — one will block the other every minute. F-15. This is a real bug: the digest tick (every 60s) tries `pg_try_advisory_lock(93422878)`, and so does the daily commission-approve sweep. They never run "at the same instant" in normal operation, but if the daily sweep runs at minute boundary the digest tick sees the lock held and **silently no-ops that minute's digest flush**.

### I6. WarrantyPurchasesService.expireOverdueWarranties — daily, no advisory lock visible.

### I7. AuditService.verifyHashChain — daily audit-chain verification (S2-K). Logs `error` on chain break.

### I8. pruneExpiredIdempotencyRows — daily, sweeps `request_idempotency`.

### I9. purgeExpiredSoftDeletedAccounts — daily, hard-deletes users past 30-day cooling-off.

### I10. cleanup_old_audit_logs() — Postgres function call, daily (was weekly in audit history).

### I11. notification_history retention — `DELETE WHERE created_at < NOW() - INTERVAL '90 days'`, daily.

### I12. openai_usage retention — same shape, 90 days, daily.

### I13. webhook_events retention — `DELETE WHERE processed_at < NOW() - INTERVAL '7 days'`, daily.

### I14. webhook_event_high_water — `DELETE WHERE source='stripe' AND last_event_at < NOW() - INTERVAL '90 days'`. RC rows kept indefinitely.

### I15. email_scanner_seen_messages — `DELETE WHERE first_seen_at < NOW() - INTERVAL '90 days'`, daily.

### I16. FCM stale-token cleanup — `FcmService.cleanupStaleTokens(60)`, daily. Removes tokens with `last_seen_at` > 60 days old.

### I17. apple_sign_in_nonces — `DELETE WHERE expires_at < NOW()`, daily.

### I18. gift_verify_attempts — `DELETE WHERE bucket_minute < NOW() - INTERVAL '24 hours'`, daily.

### I19. receipt_scan_idempotency — `DELETE WHERE expires_at < NOW() - INTERVAL '7 days'`, daily.

### I20. ReconciliationService.reconcileUserAnalytics — Sundays only (`getUTCDay() === 0`).

### I21. DIGEST_FLUSH_LOCK (93422878) — every 60s
`startDigestTick()` (index.ts:471-504). Self-rescheduling setTimeout (not setInterval) so a long-running flush can't pile up overlapping ticks. Computed delay relative to start-of-tick — converges instead of diverging. Timer is `unref()`'d. **Lock collision with I5 — see above.**

### I22. Drift-resilient setTimeout pattern (daily scheduler)
`scheduleNext` recomputes deadline; `driftCheck` runs every 30 min, reschedules if drift > 5 min. Documented at index.ts:181-186.

### I23. Process restart mid-run
- The advisory lock is **session-scoped** (released when `client.release()` returns the connection to the pool, NOT when the SQL ends). The `runWithAdvisoryLock` `finally` block calls both `pg_advisory_unlock` and `client.release()`.
- If the process crashes mid-job, the advisory lock is released with the connection. The next replica can pick up immediately. ✓

---

## J. Config loader

### J1. config/index.ts (full review). Validator runs FIRST in index.ts:5 — before `./config` is imported.

### J2. Required envs
`ALWAYS_REQUIRED`: `NODE_ENV`, `PORT`, `JWT_SECRET`, `REFRESH_TOKEN_SECRET`. `PRODUCTION_REQUIRED`: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`. `OPTIONAL_FEATURES` (warned-on-missing): OPENAI, REVENUECAT_*, GOOGLE_CLIENT_ID, APPLE_BUNDLE_ID, OAUTH_TOKEN_ENCRYPTION_SECRET. DB: requires either `DATABASE_URL` OR all of `DB_HOST/DB_PORT/DB_NAME/DB_USER/DB_PASSWORD`.

### J3. Length validations
JWT_SECRET >= 32 chars, REFRESH_TOKEN_SECRET >= 32 chars, must differ. Production DB password >= 16 chars and != `havenkeep_dev_2026`. Provider-prefix sanity in production: `STRIPE_SECRET_KEY` must start with `sk_live_` / `rk_live_`, `STRIPE_WEBHOOK_SECRET` `whsec_`, `SENDGRID_API_KEY` `SG.`.

### J4. Defaults
- `PORT` → 3000.
- `DB_HOST` → 'localhost', `DB_PORT` → 5432.
- `REDIS_URL` → 'redis://localhost:6379'.
- `MINIO_ENDPOINT` → 'localhost', `MINIO_PORT` → 9000.
- `CORS_ORIGINS` → 'http://localhost:3000,http://localhost:3001'. **Falls back to localhost in prod if env unset** — but the validator doesn't require CORS_ORIGINS in prod, so a misconfigured prod can run with localhost origins. F-16.
- `NOTIFICATION_HOUR_UTC` → 14 (9am ET).
- `MICROSOFT_TENANT` → 'common'.
- `FREE_TIER_ITEM_LIMIT` → 5.
- `JWT_EXPIRES_IN` → '1h', `REFRESH_TOKEN_EXPIRES_IN` → '7d'.
- `SENDGRID_FROM_EMAIL` → 'noreply@havenkeep.com', `SENDGRID_REPLY_TO_EMAIL` → 'support@havenkeep.com' (defaults exposed in non-prod).

### J5. Env-var typos
None obvious. `STRIPE_WEBHOOK_SECRET` consistently spelled. `REVENUECAT_SECRET_API_KEY` matches the RC dashboard convention. `OAUTH_TOKEN_ENCRYPTION_SECRET` + legacy plural mirrors the rotation pattern.

### J6. intFromEnv / strFromEnv helpers
`intFromEnv(name, fallback)` returns fallback when undefined/empty/non-finite/negative. There is **no `strFromEnv`** helper — string fallbacks are inline `process.env.X || 'default'` which is fine but inconsistent.

### J7. readSecret helper
- Tries `${name}_FILE` first → reads file → trim.
- Falls back to `process.env[name]` → trim → falsy if empty.
- Throws on `_FILE` set but unreadable.

---

## K. Caddy config

### K1. Files in repo
- `caddy/havenkeep.caddyfile` — the only checked-in Caddy config. Header comment says "append this to Loni's Caddyfile" — i.e. this is the staging block, NOT the live config. Live Caddy config lives at `/opt/staging/infra/Caddyfile` per CLAUDE.md (not in this repo).

### K2. K3-K17 — review of `caddy/havenkeep.caddyfile`

Three vhost blocks: `api.havenkeep.kouakoudomagni.com`, `partner.havenkeep.kouakoudomagni.com`, `havenkeep.kouakoudomagni.com`. (Note: these subdomains do NOT match what CLAUDE.md says staging uses today — `api.staging.havenkeep.app`, `partner.staging.havenkeep.app`, `staging.havenkeep.app`. The checked-in file appears to be the older Loni-piggyback-staging block. F-17.)

#### K3. CSP (per vhost)
- `api.*` block: **does NOT set CSP**. Only `X-Content-Type-Options nosniff`, `X-Frame-Options DENY`, `HSTS`. CSP is set inside the API itself (helmet, see A2). Caddy doesn't add a duplicate.
- `partner.*` block:
  ```
  Content-Security-Policy "default-src 'self'; script-src 'self' 'strict-dynamic' 'unsafe-inline' https://js.stripe.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' https://api.havenkeep.kouakoudomagni.com https://api.stripe.com; frame-src https://js.stripe.com https://hooks.stripe.com; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
  ```
  - `script-src 'unsafe-inline'` is present. Comment claims `strict-dynamic` makes it ignored — that IS true in CSP3 browsers BUT older browsers fall back to `'unsafe-inline'`. Tradeoff documented inline.
  - `connect-src` whitelists the same-domain API + Stripe.
  - `img-src 'self' data: https:` — `https:` is wide. Lets the dashboard render images from any HTTPS host. F-18.
- Marketing block:
  ```
  Content-Security-Policy "default-src 'self'; script-src 'self' 'strict-dynamic'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' https://api.havenkeep.kouakoudomagni.com; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
  ```
  - `img-src https:` again. Same finding F-18.
  - `style-src 'unsafe-inline'` — Astro/Tailwind requirement.
  - No nonce or hash. `'strict-dynamic'` script-src works for Astro because no inline scripts are emitted.

#### K4. HSTS
All three vhosts: `Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"`. ✓ ≥1 year + preload.

#### K5. Referrer-Policy
Only on partner + marketing blocks: `strict-origin-when-cross-origin`. **API block does not emit Referrer-Policy from Caddy** — but helmet (in the API) sets it. ✓

#### K6. Permissions-Policy
Only on partner + marketing: `camera=(), microphone=(), geolocation=(), interest-cohort=()`. API block does not. **Helmet does not set Permissions-Policy by default** — so the API serves no Permissions-Policy header. F-19. Low impact (the API doesn't render UI), but worth aligning.

#### K7. X-Content-Type-Options
All three: `nosniff`. ✓

#### K8. X-Frame-Options
- API + marketing: `DENY`.
- Partner: `SAMEORIGIN`.
- The dashboard's `frame-ancestors 'none'` (CSP) is stricter than `SAMEORIGIN` (XFO) — modern browsers honor frame-ancestors, but the XFO header still permits same-origin framing. Not a real conflict.

#### K9. TLS config
Not in the checked-in Caddyfile. Caddy automates Let's Encrypt with default modern TLS (1.2 + 1.3). No `tls` block customization. Default cipher suites.

#### K10. Reverse-proxy upstreams
- `api.*` → `havenkeep-stg-api:3000` with health-check polling `/health` every 30s, 10s timeout, 2xx-required. Headers up: `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`. Transport: dial 5s, response_header 30s, read/write 60s.
- `partner.*` → `havenkeep-stg-dashboard:3001`. No health-check block. Transport: dial 5s, response_header 30s. No headers up — dashboard would receive Caddy's defaults.
- Marketing → `havenkeep-stg-marketing:80`. Transport: dial 5s, response_header 30s.

**The dashboard block does not forward `X-Forwarded-For` or `X-Real-IP`** — explicit `header_up` directives are missing. Caddy's default behavior in v2 IS to set XFF, but explicit-only-on-API is inconsistent. F-20.

The container names in the file (`havenkeep-stg-api`, `havenkeep-stg-dashboard`, `havenkeep-stg-marketing`) don't match CLAUDE.md (`havenkeep-api`, `havenkeep-dashboard`, `havenkeep-marketing`). Confirms that `caddy/havenkeep.caddyfile` is **stale** — not the file driving production staging. F-17 cont.

#### K11. Stripe webhook raw-body matcher
**Not present in the checked-in file.** CLAUDE.md says the live `/opt/staging/infra/Caddyfile` has a raw-body matcher for `/api/v1/webhooks/stripe` and `/api/v1/webhooks/revenuecat`, but the file in this repo doesn't. F-21. (This is consistent with F-17: the in-repo file is stale; live config is on the droplet.)

#### K12. RevenueCat webhook raw-body matcher
Same as above — not in checked-in file.

#### K13. AASA Content-Type override
On marketing block, lines 104-105:
```
@aasa path /.well-known/apple-app-site-association
header @aasa Content-Type application/json
```
✓.

#### K14. assetlinks Content-Type override
Lines 110-111:
```
@assetlinks path /.well-known/assetlinks.json
header @assetlinks Content-Type application/json
```
Already application/json by extension; pinned defensively. ✓

#### K15. Compression
Not configured in the checked-in file. Caddy defaults: no compression unless `encode gzip zstd` is declared. So no compression at the edge today; the API has its own `compression()` middleware. F-22 — given the comments in the live file claim a raw-body matcher (which implies compression is on for everything else), this is another sign the in-repo file is stale.

#### K16. Logging
JSON to file, 50MB roll, 3 files retained, 720h (30d) retention. Captured per-vhost.

#### K17. Edge rate limiting
**None.** No `rate_limit` directive in any block. Edge rate limiting (e.g. with Caddy's `mholt/caddy-ratelimit` plugin) would be a defense-in-depth layer for the auth endpoints — currently not present. F-23.

---

## L. Adversarial scenarios

### L1. Host: evil.com
Caddy vhost binding is by hostname. A request with `Host: evil.com` to the API IP doesn't match any block → Caddy returns its default 404. ✓

### L2. X-Forwarded-For: 1.2.3.4, attacker.ip
With `trust proxy=1`, Express drops the rightmost entry (the trusted Caddy hop) and uses what's left (`attacker.ip`). `getIpAddress` in utils/ip-address.ts does the same: strips `TRUST_PROXY_HOPS=1` from the right, returns parts[length-2] = `1.2.3.4`. Either way, the **client-supplied first XFF entry** is what we trust as the IP. **An attacker behind Caddy cannot inject XFF — Caddy overwrites it with `header_up X-Forwarded-For {remote_host}` (caddyfile line 34) — the comment in CLAUDE.md/audit Ch11-I005 acknowledges this.** ✓ for the API block. **The dashboard block does NOT have `header_up X-Forwarded-For` (F-20)** — Caddy's defaults DO set it, but explicit > implicit.

### L3. 1GB POST
- Express body parser caps at 1MB (`limit: '1mb'`) for json + urlencoded → `PayloadTooLargeError`.
- Multer routes cap at 5MB or 10MB depending on route.
- Caddy has no `request_body { max_size }` directive in the checked-in file. Caddy defaults: no limit. **A 1GB POST to the marketing site would buffer through Caddy → marketing upstream**, depending on the upstream's body limit. F-24.

### L4. Content-Type: application/x-www-form-urlencoded to a JSON endpoint
`express.json` ignores non-JSON Content-Type → body is `{}`. `validate(jsonSchema)` then 400s on missing fields. Graceful.

### L5. /.well-known/security.txt
Marketing site → Astro static handler. If `security.txt` doesn't exist, 404. Not configured in repo. F-25.

### L6. Accept-Encoding: br to Stripe webhook
Stripe never sends `Accept-Encoding` for webhook deliveries (it expects raw bytes). Caddy is request-side compression-naive (it would not compress an incoming request). The API's `compression()` middleware is response-side only. So this is a non-issue; raw body is preserved.

### L7. Malformed Authorization header
`authenticate` middleware: `if (!authHeader || !authHeader.startsWith('Bearer ')) throw new AppError('No token provided', 401)`. → generic 401 envelope. ✓ The handler does not log the malformed header (which could be a credential leak).

### L8. 10-minute idle connection
Caddy `read_timeout 60s, write_timeout 60s` for the API block. Connection idle past 60s → Caddy closes. Express has no explicit `server.timeout` in code; Node 20 default is 0 (unlimited). The Node `requestTimeout` default is 300s (5 min). Caddy will close first, so the API doesn't actually hold for 10 min. ✓ — but the Node-side `server.headersTimeout` and `server.requestTimeout` are not explicitly set. F-26.

---

## M. Health endpoints

Already reviewed in section A11/A12.

### M1. `/health` — pings DB, returns 200 or 503.
### M2. `/health/detailed` — admin-only; reports DB, Redis, MinIO. Each uses `safeMessage` to scrub credentials.
### M3. DB check: `pool.query('SELECT 1')`.
### M4. Redis check: `redis.ping()` via shared client.
### M5. MinIO check: `bucketExists(BUCKET_NAME)`.
### M6. No queue depths, no replication lag, no per-component versions exposed. ✓

`/ready` and `/live` reviewed; `/ready` flips to 503 the moment `markShuttingDown()` is called from `shutdown()` (lifecycle.ts shared flag).

---

## N. Other middlewares

### N1. cors — covered (A3).
### N2. helmet — covered (A2).
### N3. compression — covered (A6).
### N4. cookie-parser — populates `req.cookies` for csrf middleware.
### N5. validate (Joi) — middleware/validate.ts:
- `stripUnknown: true` in production, false in dev (audit Ch11-I023). Production silently drops unknown keys but logs them at warn level (S-LO-01).
- `abortEarly: false` so the response includes all field-level errors.
- Multi-target form: `validate({ body: schema, params: schema, query: schema })`.

### N6. asyncHandler — utils/async-handler.ts: `(fn) => (req,res,next) => Promise.resolve(fn(...)).catch(next)`. Wrap-only; logging is done by `errorHandler`.

---

# Findings (50+)

## Critical / High

**F-15 [HIGH]** — Lock-ID collision: `PARTNER_COMMISSION_AUTO_APPROVE_LOCK = 93422878` (index.ts:65) and `DIGEST_FLUSH_LOCK = 93422878` (index.ts:470) are the SAME number. The 60s digest tick competes with the daily commission auto-approve sweep for the same advisory lock. When the daily sweep runs, the same-minute digest tick silently no-ops (it only blocks until the daily sweep finishes, which can be seconds for a small commissions table — but on a busy day, an unbounded skip-window is possible). Fix: bump digest lock to `93422879`.

**F-08 [HIGH]** — Idempotency middleware has no concurrent-request locking. Two simultaneous requests with the same `Idempotency-Key` both miss the SELECT, both run the handler, and the cached row is whichever INSERTed first (the OTHER's response goes to the other client uncached). Mitigation lives in handler-side DB constraints (`ON CONFLICT DO NOTHING`), but the responses can diverge from the cached entry. Fix: `SELECT ... FOR UPDATE` or `INSERT ... ON CONFLICT DO NOTHING RETURNING xmax=0` to detect the race and replay.

**F-03 [HIGH]** — Per-endpoint rate limiters fail-open to in-memory store if `initializeEndpointRedis` errored at boot. `rateLimiter.ts:243-244` logs an error but does NOT throw. The global limiter (initializeRateLimiter) DOES throw — but per-endpoint ones don't. So in production, an `initializeEndpointRedis` failure means every per-endpoint limit becomes per-instance, multiplying the budget by replica count. Fix: throw in initializeEndpointRedis on failure, mirror the global limiter's policy.

**F-21 [HIGH]** — The checked-in `caddy/havenkeep.caddyfile` lacks the Stripe + RevenueCat raw-body matcher that CLAUDE.md says is required on the live droplet. If anyone deploys Caddy from this file, webhook signatures break under any compression. Fix: bring the file in sync with the live `/opt/staging/infra/Caddyfile` block, OR delete the in-repo file to remove the trap.

## High-medium

**F-17** — Checked-in Caddyfile is stale. Hostnames (`api.havenkeep.kouakoudomagni.com`) and container names (`havenkeep-stg-api`) don't match CLAUDE.md's stated staging surface (`api.staging.havenkeep.app`, container `havenkeep-api`). Either delete the file (it's not authoritative) or update it. Per CLAUDE.md Rule 3 (no legacy/dead code), this should be deleted.

**F-12** — `apps/api/src/routes/uploads.ts` uses `multer.memoryStorage()` for 10MB image uploads. `documents.ts` switched to `multer.diskStorage({})` for the same size class for a documented heap-pressure reason. Avatar + item-image uploads should use the same disk-storage pattern for consistency.

**F-13** — `documents.ts` uses `multer.diskStorage({})` with **default tmpdir + auto-cleanup-on-response-close**. If the worker crashes mid-request, tmp files leak. There's no scheduled tmp-dir sweeper. Fix: add a startup cleanup pass that removes stale `multer-` files in `os.tmpdir()` older than N hours.

**F-14** — Multer errors don't map to AppError. `LIMIT_FILE_SIZE` should produce 413; fileFilter cb errors should produce 400. Currently both fall through to errorHandler "unknown" 500. Fix: register a multer error-class handler (or wrap multer middleware in a try/catch shim) and translate `MulterError` → AppError.

**F-02** — Login limit is per-IP, not per-email. NAT'd users share the budget; distributed attackers bypass. Add a per-email lock: 5 failed attempts on `email=X` within 15 min → soft-lock that email's login (returns 429 regardless of correct password).

**F-05** — `requirePartner` is defined locally in `routes/partners.ts:70` and only checks the cached `req.user.isPartner` (10s Redis TTL). Compare with `requireAdmin` in `middleware/auth.ts` which re-reads DB on every call to close the demoted-admin window. Fix: hoist `requirePartner` into `middleware/auth.ts` and add a fresh DB check (or `verifyPartnerFresh` helper).

**F-04** — 429 responses don't set the standard `Retry-After` HTTP header. Body has `retryAfter` (seconds) but most HTTP clients (browsers, native SDKs) honor `Retry-After`, not body fields. Fix: `res.setHeader('Retry-After', String(retryAfterSec))` in the 429 handler.

**F-10** — `req.body.email` is not in `REDACT_PATHS`. Request bodies aren't logged by the standard `requestLogger`, but anywhere a developer does `logger.info({ body: req.body }, ...)` will leak email. Already a documented PII concern; promote `email` to the redact list.

**F-19** — API responses do not include `Permissions-Policy` (helmet doesn't set it by default). The dashboard + marketing vhosts emit it via Caddy. Add `permissionsPolicy` block to helmet config or set in Caddy for the API vhost.

**F-20** — Caddy `partner.*` and marketing vhost blocks lack explicit `header_up X-Forwarded-For {remote_host}`. Caddy's defaults DO set XFF, but explicit-only-on-API is inconsistent and a future Caddy default-behavior change would silently regress.

## Medium

**F-01** — 404 handler in `app.ts:210-215` returns `{ error, suggestion }` which differs from the standard envelope `{ success: false, error, code, statusCode, requestId }` produced by `errorHandler`. Fix: use the AppError envelope shape (or throw `new AppError('Not found', 404, 'NOT_FOUND')` and let errorHandler render).

**F-07** — Idempotency body-hash uses `JSON.stringify(req.body ?? {})` which is non-deterministic for object key order. Two semantically identical requests with reordered keys produce different hashes → false 409. Fix: stable-sort keys before hashing (e.g. recursive key-sort or `json-stable-stringify`).

**F-11** — `pgErrorToApp` in errorHandler doesn't map `23514` (CHECK), `40001` (serialization), `40P01` (deadlock), `42P01` (undefined table). Today these fall through to 500 "Internal server error". `40001`/`40P01` should be retryable 503; `23514` is a 400. Fix: extend the switch.

**F-09** — `constantTimeEquals` short-circuits on length mismatch before `crypto.timingSafeEqual`. Both tokens are fixed-length (64-char hex), so this is theoretical. But the function is documented to be safe against length oracle — strictly it isn't.

**F-16** — `CORS_ORIGINS` defaults to `http://localhost:3000,http://localhost:3001` if the env is unset. The validator does not require this var in production. A misconfigured prod deploy gets localhost origins → all browser CORS preflights fail → the app appears to be down without a clear error. Fix: add `CORS_ORIGINS` to `PRODUCTION_REQUIRED` in validator.ts.

**F-18** — Caddyfile CSP `img-src 'self' data: https:` is wide. The marketing site renders blog imagery from a curated set of domains; the dashboard renders avatars from MinIO + the API. Both can be tightened to specific hosts (the API helmet config did exactly this — see `app.ts:65-72`). Fix: tighten the dashboard + marketing CSPs to enumerated img-src.

**F-23** — No edge rate limiting in Caddy. The API's per-endpoint limiters fire AFTER request reaches the API process. A volumetric attacker still spends API CPU on every request before the limiter rejects. Add `caddy-ratelimit` plugin or front the Caddy with a CDN/WAF that rate-limits at the edge for `/auth/*` and `/contact`.

**F-24** — Caddy has no `request_body { max_size }` directive. Express + multer cap at 10MB; without an edge cap, a 1GB POST gets buffered all the way to the upstream. Add `request_body { max_size 12MB }` to the API vhost (slightly above the 10MB multer cap to avoid edge rejection on borderline uploads).

**F-25** — No `/.well-known/security.txt` shipped from the marketing static site. Audit-friendly to publish a contact for vulnerability reports.

**F-26** — Node HTTP server timeouts are not set explicitly. `server.headersTimeout` and `server.requestTimeout` default to 60s/300s in Node 20. Caddy's read_timeout (60s) closes before either fires, so this is moot today — but a Caddy-bypass (direct hit on port 3000) holds connections for 5 min. Fix: set `server.headersTimeout = 30000; server.requestTimeout = 120000;` in `start()`.

**F-22** — Caddy in the checked-in file has no `encode` directive. Without compression, large response bodies (CSV exports up to 100MB) hit the wire uncompressed. The API's `compression()` middleware compresses, but Caddy doesn't preserve any Vary/Accept-Encoding handling cleanly without `encode`. Add `encode gzip zstd` to all three vhosts.

## Low / hygiene

**F-06** — `POST /partners/register` flips a row in `partners` (which is JOIN-derived in the user-cache `is_partner` field) without calling `invalidateUserCache(userId)`. Worst case: 10s before the user's auth recognizes them as a partner. Fix: call `invalidateUserCache(req.user!.id)` on successful register.

**F-27** — `helmet` `style-src 'unsafe-inline'` is set even though the API doesn't render HTML. Cosmetic — remove it.

**F-28** — `cors` config has no `maxAge`. Each new path triggers a preflight OPTIONS round-trip on browsers with default low cache windows. Add `maxAge: 600` (10 min) for staging, 86400 (24h) for prod.

**F-29** — `cors` `methods` list omits `OPTIONS` and `HEAD`. The `cors` package handles preflight independently, but a `HEAD /api/v1/X` request (some HTTP clients use HEAD for cheap existence checks) is rejected at preflight. Add `HEAD` and `OPTIONS`.

**F-30** — `cors` accepts `Origin: null` (sandboxed iframe / file://) via `if (!origin) return cb(null, true)`. The intent is to allow mobile/curl, but `null` origin is technically a string. Fix: `if (!origin || origin === 'null') return cb(null, true)` is identical, OR explicitly reject `'null'` if browser sandboxing is a concern.

**F-31** — `requestLogger` slow-request thresholds (1s, 5s) are hard-coded constants. Make them env-configurable so noisy environments can dial up.

**F-32** — `requestLogger` doesn't flag the request as slow on `>= 10s` more loudly. The pattern is info → info(slow) → warn. A 30s request gets warn — same as a 5s. Add an error-level for >= 30s.

**F-33** — `pino` redact `*.image` pattern catches body image fields, but doesn't catch `req.files[*].buffer` (Multer-populated). If anyone logs `req.files`, the decoded image bytes hit Loki. Fix: add `req.files`, `*.files`, `*.buffer` to redact.

**F-34** — `pino` does not redact the `x-revenuecat-signature` header. The Stripe header is in the redact list — RC's isn't. Add it.

**F-35** — `auth.ts:1086` (Apple JWT error path comment) — matches the `algorithms: ['HS256']` pin in `authenticate`. ✓ But the pin is per-call (line 77); a future caller of `jwt.verify` elsewhere in the codebase could omit the algorithm pin. Add a wrapper utility.

**F-36** — `validateCsrfToken` reads `req.cookies` length to decide bypass. If `cookie-parser` ever fails (e.g. malformed `Cookie:` header), `req.cookies` is `{}` → bypass kicks in. A browser with a corrupted Cookie header could accidentally skip CSRF. Low impact; document.

**F-37** — `idempotency` only persists 2xx responses. A 409 response (different body, same key) is NOT cached — so the next reuse with the *original* body could still proceed if the prior 409 didn't write a row. Verify: looking at the code, the 409 throws and never reaches the persist branch, so the first request's body+success is cached, and the 409 response on the second is computed live every time. ✓ Working as intended; documenting.

**F-38** — `idempotency` body cap (32KB) silently skips persist with a warn log. The next replay attempt will re-run the handler. Documented as best-effort, but means a "successful" first request can produce a *different* (re-processed, with different timestamps/IDs) response on retry. For routes where re-processing is OK (the comment says "the client can refetch from the canonical list endpoint"), fine — but `idempotency('items:create')` is on POST /items where the client expects exactly-once semantics. Fix: either bump the cap, or drop the body cap entirely and rely on TTL.

**F-39** — `idempotency` row insert is fire-and-forget (`pool.query(...).catch(...)`). The response goes out before the row is persisted. A near-instant retry within the same TTL but BEFORE the INSERT lands sees no row → handler runs twice. Window is sub-millisecond but real. Fix: await the INSERT before `originalJson(body)`.

**F-40** — Memory store fallback in dev `createMemoryRateLimiter` uses `max * 10`. Documented. Be aware: if `NODE_ENV=production` is accidentally unset locally, this multiplier doesn't kick in. Low impact.

**F-41** — `RedisStore.LUA_INCREMENT` uses `math.random(1000000)` for ZSET member uniqueness within the same millisecond. The Redis Lua `math.random` is **not seeded per call** (it's seeded at server startup), so multiple Lua calls in the same Redis connection produce a deterministic sequence — collisions theoretically possible at high concurrency. ZADD on the same score+member is a no-op, which would under-count by 1. Fix: append `redis.call('TIME')` microseconds + a counter or use `INCR` for monotonicity.

**F-42** — `cors` exposes only `x-request-id`. `RateLimit-*` standard headers won't be readable from a browser fetch unless added to `exposedHeaders`. Fix: add `RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset`, `Retry-After` to expose.

**F-43** — `validate` middleware `allowUnknown: isProd, stripUnknown: isProd` — production silently drops typos with a warn log. The audit comment makes the trade-off explicit. Consider per-route override so security-critical schemas (auth, password, mfa) can run `stripUnknown: false` even in prod.

**F-44** — `errorHandler` includes `cause: err.cause` in the log line for AppError. `cause` may itself be an Error object or a PG result row — pino serializes it whole. If `cause` carries non-redacted secrets (e.g. a PG error with the failing INSERT in `err.detail`), they hit Loki. Fix: explicitly serialize `cause` to a safe summary.

**F-45** — `getIpAddress` parses `TRUST_PROXY_HOPS` differently than `app.ts` (number vs parseInt). For the default `'1'` they agree; for non-numeric values they diverge. Standardize on one helper.

**F-46** — `closeRateLimiterRedis()` doesn't actually close anything — it just nulls `sharedRedisClient`. The actual close is `closeRedisClient()` in utils/redis.ts. The naming implies action that doesn't happen — confusing. Rename to `releaseRateLimiterRedisRef`.

**F-47** — `RedisStore.decrement()` uses `zRemRangeByRank(key, 0, 0)` which removes the OLDEST entry. If express-rate-limit calls decrement on a request that just incremented, this removes a *different* entry (the oldest, not the most recent). For the current feature set (`skipSuccessfulRequests: false` or undefined everywhere except `refreshRateLimiter` which sets it false), this never fires — but the implementation is wrong and would under-count if a route ever flipped to skipSuccessfulRequests. Fix: ZADD a unique member, ZREM that specific member.

**F-48** — `cookie-parser` is mounted but no signing secret is provided. All cookies are unsigned. The CSRF cookie is double-submit (no signing needed); `csrf_token` is JS-readable so signing wouldn't help. Acceptable — but if any future cookie holds session data, it must be signed.

**F-49** — Helmet `crossOriginEmbedderPolicy: 'require-corp'` is strict and would break any iframe embedding from a non-CORP-tagged third party. The API doesn't render HTML so the directive is moot for browsers loading API responses. Document.

**F-50** — `safeMessage` in health.ts redacts only `key=value` patterns and Postgres/Redis URIs. AWS access keys (`AKIA...`), generic JWTs (`eyJ...`), MinIO keys (no fixed prefix) are not scrubbed. Fix: add `eyJ[A-Za-z0-9._-]+`, `AKIA[0-9A-Z]{16}`, sequences of >32 base64 chars to the regex set.

**F-51** — `request_idempotency` rows store the response body as-is. If the handler returns an envelope with `requestId`, replays will return the OLD `requestId` — making distributed tracing harder. Fix: post-process replays to substitute `requestId`.

**F-52** — `request_idempotency` `route_key` is a free-text string. Two routes accidentally using the same key (`'foo:create'`) share their cache and would falsely 409 each other. No registry/enum exists. Fix: enumerate route keys (TS const literal type) and grep-test for duplicates.

**F-53** — `requestLogger` UA truncation at 200 chars (`UA_MAX`) is good, but it doesn't truncate `req.path`. A 30KB URL (rare, but possible via query-string abuse) bloats every log line. Fix: cap path/url length at, say, 1024 chars.

**F-54** — `errorHandler` "unknown error" path includes `err` (full object) in pino metadata. If `err` is a PG error with `err.detail` carrying the failing row's plaintext, that lands in Loki. Same family as F-44. Fix: when error code is unmapped PG, scrub `detail`.

**F-55** — Multer uploads inheriting from `documents.ts`'s diskStorage have NO explicit `destination` — defaults to `os.tmpdir()`. In a containerized prod, tmp is the writable layer; on Kubernetes with `readOnlyRootFilesystem: true`, this would crash. Fix: set explicit `destination: '/var/tmp/uploads'` and mount an emptyDir/tmpfs there.

**F-56** — The 404 handler's `suggestion: 'Check API documentation for available endpoints'` is fine, but there's no link to the docs. Cosmetic.

---

# Summary

55 findings. Highest-impact:
- **F-15** (lock-id collision between digest tick and commission auto-approve, both at `93422878`).
- **F-08** (idempotency middleware races concurrent same-key requests; cached response can diverge from what the second client received).
- **F-03** (per-endpoint rate limiters fail-open to in-memory if Redis fails at boot — only the global limiter fails-fast).
- **F-21 / F-17** (the checked-in `caddy/havenkeep.caddyfile` is stale and lacks the documented Stripe webhook raw-body matcher; either delete it or sync to live).

Mid-tier hygiene: F-12/F-13/F-14 (multer storage choices and error mapping), F-02 (login per-email throttle), F-05 (requirePartner has no fresh DB check), F-04 (Retry-After header), F-10 (email PII in redact), F-19/F-20 (Caddy header alignment), F-23 (edge rate limiting), F-24 (Caddy body cap).

Long tail of low-risk hygiene items (F-27 onward) covers redact-list completeness, route-key registry, env-typo guards, header tightening, and timer settings.

The middleware chain ordering itself is sound: helmet → CORS → Stripe-raw → json/urlencoded → compression → RC → cookie-parser → requestLogger → rateLimiter → CSRF → routes → 404 → errorHandler. Trust-proxy posture is correct for the documented single-Caddy-hop topology. CSP at the API layer is tight; the dashboard CSP is permissive on `img-src https:` (F-18). The auth+CSRF+idempotency triad is well-thought-through with documented audit-history; the bypass conditions are explicit and tested.

The biggest concrete risks are (a) the lock-id collision, (b) the idempotency race, and (c) a stale Caddyfile in the repo that does not match what's deployed.

Files cited:
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/app.ts`
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/index.ts`
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/middleware/auth.ts`
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/middleware/csrf.ts`
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/middleware/errorHandler.ts`
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/middleware/idempotency.ts`
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/middleware/rateLimiter.ts`
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/middleware/requestLogger.ts`
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/middleware/validate.ts`
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/utils/{redis,token-blacklist,logger,errors,ip-address,lifecycle,async-handler}.ts`
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/utils/file-validation.ts`
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/config/{index,validator,minio}.ts`
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/src/routes/{health,csrf,uploads,documents,receipts,partners}.ts`
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/Dockerfile`
- `/Users/pacomedomagni/Projects/havenkeep/apps/api/package.json`
- `/Users/pacomedomagni/Projects/havenkeep/caddy/havenkeep.caddyfile`
