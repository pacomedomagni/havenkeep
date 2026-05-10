# Audit Run 06 v2 — Partner Dashboard (deep)

**Scope.** Every file under `apps/partner-dashboard/src/**`, `apps/partner-dashboard/middleware.ts`, `apps/partner-dashboard/next.config.js`. Cross-checked against `apps/api/src/middleware/{csrf,idempotency}.ts` and `apps/api/src/routes/auth.ts`.

**Date.** 2026-05-10
**Branch.** main
**v1 reference.** [docs/audit-runs/06-partner-dashboard.md](../audit-runs/06-partner-dashboard.md) — v1 found 1 Critical (`API_UPSTREAM_URL` rewrite footgun), 5 High, 15 Medium, 12 Low. v2 keeps every still-unfixed v1 finding (none of v1's items have shipped), and adds new findings the shallow pass missed.

**Headline.** Two new criticals jumped out on a per-line read.
1. **C2 — `SAFE_SEGMENT` accepts `..`.** The proxy's segment regex is `[A-Za-z0-9._~-]{1,128}`. The `.` is unconstrained, so `..` (and `....`) match, and so does `%2e%2e` after the decode-then-test pass. A request like `/api/v1/admin/foo/..` survives validation; Node's `fetch(...)` URL normalization then collapses the `..`, turning the upstream call into `${API_URL}/api/v1/admin/`. This is a path-traversal hole in a route that's specifically meant to be the only gatekeeper between the browser and the upstream API.
2. **C3 — Login flow ignores the `mfa_required` response.** The API's `/auth/login` returns `{ success: true, data: { mfa_required: true, mfa_token, factor_types } }` for any user with a verified MFA factor (apps/api/src/routes/auth.ts:521-541). The dashboard's `signIn` action (apps/partner-dashboard/src/app/login/actions.ts:60-66) reads `data.accessToken` only and bails with the generic "email or password is incorrect" message. **Effect:** any partner or admin who enables MFA via mobile or via direct API call cannot log into the partner dashboard. Their login looks like a credentials problem, not an MFA gate. There is no `/mfa/challenge` page in the dashboard at all.

C1 (rewrite footgun) is unchanged from v1 and still ships on `main`.

The remaining body of the audit splits into Highs (cookie hygiene, body limits, race conditions, proxy-vs-fetch normalization), Mediums (consistency / drift), and Lows (cosmetic).

---

## Critical

### C1 — `next.config.js` rewrites `/api/v1/*` upstream when `API_UPSTREAM_URL` is set, bypassing the entire proxy
File: [apps/partner-dashboard/next.config.js:74-83](../../apps/partner-dashboard/next.config.js).

Unchanged from v1. Reproduced here so the v2 ledger is self-contained.

```js
async rewrites() {
  const upstream = process.env.API_UPSTREAM_URL;
  if (!upstream) return [];
  return [
    {
      source: '/api/v1/:path*',
      destination: `${upstream.replace(/\/$/, '')}/api/v1/:path*`,
    },
  ];
},
```

Next.js `afterFiles` rewrites lose to file-system Route Handlers in normal operation, so under standard build the proxy at `src/app/api/v1/[...path]/route.ts` wins. **But:** rewrites match the *original* request URL, so any future shape change (folder rename, build error producing a 404 fallback to rewrites, an explicit `beforeFiles` reorder) flips the entire proxy off and routes the browser's cookies — `hk_access_token` httpOnly + `csrf_token` non-httpOnly — directly to the upstream API. The proxy's invariant comment (`route.ts:51-75`) says CSRF is ONLY validated at the proxy layer because the upstream API bypasses CSRF when no cookies are present. With cookies forwarded by this rewrite, the upstream's "no cookies = bypass" branch flips OFF, the upstream then expects a matching `x-csrf-token` cookie, and the dashboard's *different* double-submit token (its own) won't match the cookie value. So in the bypass case **mutations would also start failing 403** until a developer noticed.

**Fix.** Delete the rewrite block. The proxy is the only supported upstream path.

---

### C2 — `SAFE_SEGMENT` accepts `..`, allowing path traversal upstream
File: [apps/partner-dashboard/src/app/api/v1/[...path]/route.ts:20,38-49](../../apps/partner-dashboard/src/app/api/v1/[...path]/route.ts).

```ts
const SAFE_SEGMENT = /^[A-Za-z0-9._~-]{1,128}$/;
…
function buildUpstreamUrl(pathParts: string[], search: string): string | null {
  for (const segment of pathParts) {
    const decoded = decodeURIComponent(segment);
    if (!SAFE_SEGMENT.test(segment) || !SAFE_SEGMENT.test(decoded)) {
      return null;
    }
  }
  return `${API_URL}/api/v1/${pathParts.join('/')}${search}`;
}
```

`.` is in the character class with no positional anchor, so `..`, `...`, `....` all match. The decode-then-test pattern catches `%2e%2e` (decoded → `..`, raw `%2e%2e` fails first regex but the OR'd guard is `||` not `&&` — actually re-reading: it's `!A || !B`, so EITHER failing rejects. Re-confirmed: `%2e%2e` is rejected (raw fails `SAFE_SEGMENT`), but **literal `..` is accepted because both raw `..` and decoded `..` pass**). Ditto `..%2F` is rejected (raw fails) but `..` alone is not.

I ran:
```sh
node -e 'const r = /^[A-Za-z0-9._~-]{1,128}$/;
  console.log(r.test(".."));     // true
  console.log(r.test("..."));    // true
  console.log(r.test("...."));   // true
  const u = new URL("http://api/api/v1/admin/users/../bypass");
  console.log(u.toString());     // http://api/api/v1/admin/bypass'
```

The downstream `fetch(targetUrl, …)` runs the URL through Node's WHATWG URL normalizer, which collapses `..` segments. So a route param vector `['admin', 'users', '..', 'bypass']` produces an upstream URL of `${API_URL}/api/v1/admin/bypass` after fetch normalization. The "browser normally normalizes" defense is *not* a defense — a custom HTTP client (curl `--path-as-is`, server-side cron, mobile in-app webview override) can send literal `..` segments to the dashboard's domain.

**Concrete exploit shape.** A logged-in partner could craft a request to `/api/v1/admin/users/../analytics` from a tampered client, and the proxy would forward it to `${API_URL}/api/v1/admin/analytics` — an admin endpoint. The upstream's own `requireAdmin` middleware would still reject it on role grounds, so this isn't a privilege-escalation today. But: (a) it's defense-in-depth that explicitly didn't fail closed, (b) any internal endpoint that's authenticated-but-not-role-gated (e.g. `/auth/role-check`, `/health`) is now reachable from a partner, (c) a future endpoint added behind the dashboard's role gate but not the API's becomes a hole the day it ships.

**Fix.** The regex needs `^[A-Za-z0-9_~-][A-Za-z0-9._~-]{0,127}$` AND an explicit `decoded === '..' || decoded === '.'` reject. Or simpler: use a path-segment allowlist that explicitly rejects `'..'` and `'.'`:

```ts
function buildUpstreamUrl(pathParts: string[], search: string): string | null {
  for (const segment of pathParts) {
    if (!segment || segment === '.' || segment === '..') return null;
    const decoded = decodeURIComponent(segment);
    if (decoded === '.' || decoded === '..') return null;
    if (!SAFE_SEGMENT.test(segment) || !SAFE_SEGMENT.test(decoded)) return null;
  }
  return `${API_URL}/api/v1/${pathParts.join('/')}${search}`;
}
```

This is the kind of bug that should have been caught by the path-validation tests v1 flagged as missing — see test gaps section below.

---

### C3 — Login flow does NOT handle the API's `mfa_required` response
File: [apps/partner-dashboard/src/app/login/actions.ts:60-77](../../apps/partner-dashboard/src/app/login/actions.ts), cross-ref [apps/api/src/routes/auth.ts:521-542](../../apps/api/src/routes/auth.ts).

API's login response when MFA is enabled:
```ts
res.json({
  success: true,
  data: {
    mfa_required: true,
    mfa_token: mfaToken,
    factor_types: mfaStatus.factorTypes,
  },
});
return;
```

Dashboard's signIn action reads:
```ts
const data = body?.data;
if (!data || typeof data.accessToken !== 'string' || !looksLikeJwt(data.accessToken)) {
  return { error: GENERIC_LOGIN_ERROR };  // "The email or password is incorrect."
}
if (!data.user?.is_admin && !data.user?.is_partner) {
  return { error: 'Access restricted to partners and administrators' };
}
```

`mfa_required` returns a body with NO `accessToken`, NO `user`. Both branches fall through to `GENERIC_LOGIN_ERROR`. **A partner or admin who enables TOTP MFA via the mobile app — or via a direct API call — will see "The email or password is incorrect." every time they try to log into the partner dashboard.** Customer support will tell them to reset their password, which won't fix anything because the password is correct.

There is no `/mfa/challenge` page, no UI to enter a TOTP code, and no exchange flow that POSTs `mfa_token + code` to `/auth/mfa/challenge`. Search of `apps/partner-dashboard/src/` for `mfa_required`, `mfa_token`, `mfa_challenge`, or `mfa/challenge` returns zero results.

**Effect.** MFA is incompatible with the dashboard. Either:
1. The dashboard should detect `mfa_required` and route to a `/mfa/challenge` page that posts the code + mfa_token to the API, completing the exchange.
2. Or the dashboard/API contract should explicitly disable MFA for partner-dashboard sessions (which leaks the cross-product invariant the audit was meant to police).

V2 audit advises Option 1. The same `factor_types` field already tells the dashboard whether to render TOTP vs WebAuthn vs backup-code UI. The exchange call can mint cookies the same way `signIn` does today.

(Cross-check note: this is also a regression hole vs the audit's S-C2 finding in apps/api. The API correctly blocks MFA users from logging in until they pass the challenge; the dashboard simply doesn't have the second half of that flow.)

---

## High

### H1 — `clearAuthCookies` does NOT delete `hk_role_check` (v1 H1, unfixed)
File: [src/lib/auth.ts:11-12,165-169](../../apps/partner-dashboard/src/lib/auth.ts).

```ts
const CLEARABLE_COOKIES = [ACCESS_TOKEN_COOKIE, REFRESH_TOKEN_COOKIE, CSRF_COOKIE] as const;
…
export function clearAuthCookies(cookieStore: …) {
  for (const name of CLEARABLE_COOKIES) cookieStore.delete(name);
}
```

`hk_role_check` is the 30-second role cache (`middleware.ts:33`). Logout clears every cookie EXCEPT this one, so a user who logs out and a different user who logs in within ~30s on the same browser sees the previous user's role drive middleware redirects until the cache expires. Not a privilege escalation (page-level `requireRole` re-fetches via API), but a real UX bug. Add `'hk_role_check'` to `CLEARABLE_COOKIES`.

### H2 — Edge `redirectToLogin` does NOT delete `hk_role_check` (v1 H2, unfixed)
File: [middleware.ts:94-100](../../apps/partner-dashboard/middleware.ts).

```ts
function redirectToLogin(request: NextRequest): NextResponse {
  const response = NextResponse.redirect(new URL('/login', request.url))
  response.cookies.delete(ACCESS_TOKEN_COOKIE)
  response.cookies.delete(REFRESH_TOKEN_COOKIE)
  response.cookies.delete(CSRF_COOKIE)
  return response
}
```

Same root cause as H1, edge variant. Every refresh-failure path lands here without clearing the role cookie. Add `response.cookies.delete(ROLE_COOKIE)`.

### H3 — `/api/auth/refresh` does NOT clear cookies on validation/401 failure paths (v1 H3, unfixed)
File: [src/app/api/auth/refresh/route.ts:33-58](../../apps/partner-dashboard/src/app/api/auth/refresh/route.ts).

The four 401-return branches don't call `clearAuthCookies`. The browser's auto-refresh logic in `apiClient` then redirects to `/login`, where middleware DOES clear cookies, so end-state is correct. But the route is a public contract — any new caller (background refresh poller, ServiceWorker pre-warm, etc) that doesn't follow up with a navigation would carry stale cookies indefinitely. Defensive fix: add `clearAuthCookies(cookieStore)` to every 401 branch.

### H4 — Proxy has no per-request body-size limit (v1 H4, unfixed)
File: [src/app/api/v1/[...path]/route.ts:132-148](../../apps/partner-dashboard/src/app/api/v1/[...path]/route.ts).

```ts
const body = method === 'GET' || method === 'HEAD' ? undefined : await request.arrayBuffer();
…
return new NextResponse(await response.arrayBuffer(), { … });
```

Both `request.arrayBuffer()` (line 133) and `response.arrayBuffer()` (line 148) buffer the entire payload. No `Content-Length` ceiling, no streaming. A logged-in partner can POST 100 MB; the dashboard process holds it in memory until upstream answers. The 30 s timeout bounds *time*, not *bytes*. A coordinated 100-tab burst from one client at 100 MB each is a 10 GB heap pressure; the Next runtime OOMs.

The dashboard's expected mutation bodies are tiny (gift create ~few KB). 1 MB request cap, 5 MB response cap, both rejected with 413. Stream the response via `response.body` directly into `NextResponse` instead of buffering — Web Streams are first-class in Next 14.

### H5 — `originGuardOk` rejects `sec-fetch-site: 'none'` (v1 H5, unfixed)
File: [src/app/api/v1/[...path]/route.ts:101-107](../../apps/partner-dashboard/src/app/api/v1/[...path]/route.ts).

The header is sent as `'none'` for user-typed URLs and on certain Safari versions. The guard treats `'none'` as cross-origin and rejects mutations. For mutations this is correct (a typed POST URL is the same shape as a CSRF attempt), but the comment says "missing header → false" — the actual code is checking a string-equality, so the `null` (missing header) branch falls through to `return false` correctly via the boolean expression. Comment claim and code agree on the failure direction. **Not a security hole — a UX gap** for legacy browsers that don't send the header at all. Worth a one-line comment in the file documenting why `'none'` is intentionally rejected.

### H6 — `redirectToLogin` does NOT preserve the user's intended destination (NEW)
File: [middleware.ts:94-100,220,297,335](../../apps/partner-dashboard/middleware.ts).

Every middleware path that redirects to `/login` does so with no `?from=…` querystring. After the user re-authenticates, `signIn` always sends them to `/dashboard` or `/admin` — never back to where they wanted to go. A partner deep-linking to `/dashboard/gifts/abc123` who happens to have an expired session lands on the dashboard root, not the gift they actually wanted. Standard pattern: `redirectToLogin(request)` carries `?from=${encodeURIComponent(pathname + search)}`, and the login action validates `from` against an allowlist of dashboard prefixes before navigating there.

Not security-critical, but it's a pre-prod UX bug that a partner support call will surface immediately. Bonus: it nulls the SEO-friendly deep-link experience.

### H7 — `GET /api/auth/refresh` accepts `sec-fetch-site` of any value as long as it's set (NEW)
File: [src/app/api/auth/refresh/route.ts:19-28](../../apps/partner-dashboard/src/app/api/auth/refresh/route.ts).

```ts
function isSameOriginFetch(request: NextRequest): boolean {
  const fetchSite = request.headers.get('sec-fetch-site');
  if (!fetchSite) return false;
  return fetchSite === 'same-origin' || fetchSite === 'same-site';
}
```

Wait — this looks correct on re-read. `null → false`, then explicit equality. Equivalent on the wire to the proxy's `originGuardOk`. **Strike — this finding is a false alarm on close read.** Leaving the file/line citation for the reviewer's sanity check.

### H8 — `apiClient` mutates `signal` with a custom `__timeout` property (NEW, latent)
File: [src/lib/api.ts:99-100,111-114](../../apps/partner-dashboard/src/lib/api.ts).

```ts
(controller as AbortController & { __timeout?: ReturnType<typeof setTimeout> }).__timeout = timeout;
…
const timeout = (init.signal as unknown as { __timeout?: ReturnType<typeof setTimeout> })
  ?.__timeout;
```

Stashing a `setTimeout` id on a built-in DOM-ish object is fragile: any future iteration over `controller`'s properties trips on it, and assigning to `init.signal` (which is a getter on `RequestInit`) is a no-op semantically — the timer would actually be on `controller`, not on `init.signal`. Grep shows the timer is *also* clean-cleared in the `finally`, so the redundant property write is dead weight that mostly harms readability. Replace with a closure-captured timer id and clear it in the surrounding `finally`. Same finding as v1 L10 promoted because the pattern silently creates a bug if anyone refactors `send()` and forgets to read `init.signal`'s patched-property.

### H9 — Edge middleware `fetchFreshRole` swallows non-200 responses including 5xx (NEW)
File: [middleware.ts:152-181](../../apps/partner-dashboard/middleware.ts).

```ts
if (!response.ok) return null
```

When the API returns a 5xx for `/auth/role-check`, the middleware silently falls back to the unverified JWT body for role decisions:
```ts
const isAdmin = cachedRole?.isAdmin ?? payload.isAdmin === true
const isPartner = cachedRole?.isPartner ?? payload.isPartner === true
```

The audit's H-A8 design says "we no longer trust the unverified JWT body for role decisions" — but on every 5xx the code does exactly that. A demoted user whose API call fails for a transient reason (Postgres restart, network blip, Loki timeout) sees the OLD JWT-claim role drive routing for up to 1 hour (until the JWT expires). The page-level `requireRole` re-fetches and would 5xx-fail the SAME way, then `ApiUnavailableError` bubbles to the error boundary which renders a generic message — but the SIDEBAR may already have rendered with the wrong role.

Gap: the JWT-fallback should only fire on a network/timeout error, NOT on a 5xx body returned from the API (which means the API IS reachable and is the authoritative voice on role state).

```ts
if (response.status >= 500) return null  // network alone — fall back to JWT
if (!response.ok) {
  // 4xx from the API: the JWT is reachable AND rejected. Treat as no-role.
  return { isAdmin: false, isPartner: false, cachedAt: Date.now() }
}
```

(The current `return null` falls back to JWT — for 401 / 403 from `/role-check`, that's wrong: those mean the JWT itself is no longer valid, so trusting it is exactly the wrong move. Should `redirectToLogin` instead.)

### H10 — Server-side `serverApiClient` does not forward `Idempotency-Key` (NEW)
File: [src/lib/auth.ts:199-240](../../apps/partner-dashboard/src/lib/auth.ts).

```ts
const fetchOptions: RequestInit = {
  method,
  headers: {
    'Content-Type': 'application/json',
    ...(tokens ? { Authorization: `Bearer ${tokens.accessToken}` } : {}),
    ...headers,
  },
  cache: 'no-store',
};
```

Every server action that talks to the API — `dashboard/settings/actions.ts:updatePartnerProfile`, `onboarding/actions.ts:createPartnerProfile` — calls `serverApiClient` and never passes an `Idempotency-Key` header. The API's idempotency middleware (apps/api/src/middleware/idempotency.ts:49) is keyed on `(user_id, route_key, idempotency_key)`. Without the key, every retry of "Complete setup" / "Save changes" creates a fresh row, defeating the audit Ch10-W021's single-flight intent.

The client-side `apiClient` *also* doesn't auto-mint an idempotency key (the test in onboarding's submitGuard ref is a client-side guard only — a network retry kicks past it). At minimum every server-side mutation should mint a UUID key when the caller doesn't pass one and forward it; even better, the action signature should accept an explicit key.

### H11 — `analytics/page.tsx` flashes the spinner over the date inputs on every range change (NEW)
File: [src/app/dashboard/analytics/page.tsx:44,75-81](../../apps/partner-dashboard/src/app/dashboard/analytics/page.tsx).

```ts
setLoading(true);
…
if (loading) return <div className="flex items-center justify-center h-64"><div className="animate-spin..."/></div>;
```

`fetchAnalytics` sets `loading = true` and the page early-returns the spinner BEFORE the rest of the UI renders. Every keystroke in the date input field unmounts the date inputs (replaced by spinner), losing focus, blur events fire, the keyboard closes on mobile. A user typing `2026-04-15` in the start-date field has the input vanish on each digit. UX regression vs. having a thin loading bar above the cards.

Also — the inflight pattern v1 M4 flagged is still missing. `useCallback([startDate, endDate])` builds a fresh fetcher on every range change with no AbortController; the previous in-flight request races the new one. Last-to-return wins, not last-typed.

Combined fix (mirrors `dashboard/page.tsx`):

```ts
const inflight = useRef<AbortController | null>(null);
const fetchAnalytics = useCallback(async () => {
  inflight.current?.abort();
  const controller = new AbortController();
  inflight.current = controller;
  …
  if (controller.signal.aborted) return;
}, [startDate, endDate]);
```

Plus drop the `if (loading) return <spinner>` and inline the spinner above the cards.

---

## Medium

### M1 — Admin commission action URLs do NOT URL-encode the commission id (v1 M1, unfixed)
File: [src/components/admin-commission-table.tsx:45,66,87](../../apps/partner-dashboard/src/components/admin-commission-table.tsx).

```ts
await apiClient(`/api/v1/partners/admin/commissions/${commissionId}/approve`, …);
```

Versus `partner-table.tsx:77`, `partner-actions.tsx:32`, `UserTable.tsx:63,81` — all encode their ids. Apply `encodeURIComponent(commissionId)` in all three handlers.

### M2 — `STRIPE_HOSTS` allowlist is fine on re-read (v1 M2 false alarm, confirmed)
File: [src/app/dashboard/settings/page.tsx:9-14](../../apps/partner-dashboard/src/app/dashboard/settings/page.tsx). `stripe.com` IS in the set. Strike.

### M3 — `isSafeActivationUrl` allowlist hardcodes `havenkeep.com` only (v1 M3, unfixed)
File: [src/lib/utils.ts:30-53](../../apps/partner-dashboard/src/lib/utils.ts).

```ts
const allowed = new Set([
  'havenkeep.com',
  'www.havenkeep.com',
  'app.havenkeep.com',
  'partners.havenkeep.com',
]);
```

Staging is `staging.havenkeep.app` (per CLAUDE.md). The set has no entry for it; in staging the production NODE_ENV is set, so the localhost dev branch doesn't fire either. Partner copies a real activation URL → "That activation URL failed validation and was not copied." Add `'staging.havenkeep.app'` plus the `app.havenkeep.app` production host (per CLAUDE.md, mobile uses `havenkeep.app`).

Also: the `generate-referral.tsx:70` builds `${process.env.NEXT_PUBLIC_APP_URL || 'https://havenkeep.com'}/referral/${code}` — the URL it generates would NOT pass `isSafeActivationUrl` if `NEXT_PUBLIC_APP_URL=https://staging.havenkeep.app`. Two halves of the same misconfig.

### M4 — `dashboard/{commissions,referrals,payouts}` use `apiClient<any[]>` (v1 M12, unfixed)
File: [src/app/dashboard/commissions/page.tsx:23](../../apps/partner-dashboard/src/app/dashboard/commissions/page.tsx), [referrals/page.tsx:32](../../apps/partner-dashboard/src/app/dashboard/referrals/page.tsx).

Replace with the typed shape from `lib/api-types.ts` / `lib/types.ts`. Drift risk if the API ever adds a field — no compile error today.

### M5 — CSP is `'unsafe-inline'` on `script-src` (v1 M5, unfixed)
File: [next.config.js:42](../../apps/partner-dashboard/next.config.js).

```
"script-src 'self' 'strict-dynamic' https: 'unsafe-inline'",
```

Comment above (line 39-41) says "We do NOT enable 'unsafe-inline'." The value literally contains it. In modern browsers `'strict-dynamic'` ignores `'unsafe-inline'`; in older browsers it doesn't. The comment is a lie either way.

Pick: (a) update the comment to "We allow 'unsafe-inline' as a fallback; modern browsers honor 'strict-dynamic' which suppresses it", or (b) ship a per-request nonce via middleware + remove `'unsafe-inline'`.

### M6 — `forgot-password` action surfaces upstream 400 verbatim (v1 M6, unfixed)
File: [src/app/forgot-password/actions.ts:22-32](../../apps/partner-dashboard/src/app/forgot-password/actions.ts).

```ts
return { error: data.error || data.message || 'Please enter a valid email address' };
```

Mirror the login action's discipline: return generic copy regardless of upstream payload.

### M7 — `setAuthCookies` in signup does NOT validate the JWT shape (v1 M7, unfixed)
File: [src/app/signup/actions.ts:60-66](../../apps/partner-dashboard/src/app/signup/actions.ts). Login action runs `looksLikeJwt(data.accessToken)`; signup just trusts upstream. Cheap consistency fix.

### M8 — `clearAuthCookies` test is incomplete (v1 M8, unfixed)
File: [src/__tests__/lib/auth.test.ts:246-250](../../apps/partner-dashboard/src/__tests__/lib/auth.test.ts).

```ts
expect(mockCookieStore.delete).toHaveBeenCalledWith(ACCESS_TOKEN_COOKIE);
expect(mockCookieStore.delete).toHaveBeenCalledWith(REFRESH_TOKEN_COOKIE);
```

Missing assertion for `csrf_token`. After H1 lands and adds `hk_role_check`, the test still wouldn't catch a regression that drops it. Use `expect(mockCookieStore.delete).toHaveBeenCalledTimes(N)` with N = full clear-list length, plus explicit `expect(...).toHaveBeenCalledWith('hk_role_check')`.

### M9 — Audit/commissions/referrals filter client-side after a single fetch (v1 M9, unfixed)
File: [src/components/audit-log-table.tsx:35-50](../../apps/partner-dashboard/src/components/audit-log-table.tsx), [src/app/dashboard/commissions/page.tsx:11-42](../../apps/partner-dashboard/src/app/dashboard/commissions/page.tsx), [src/app/dashboard/referrals/page.tsx:25-58](../../apps/partner-dashboard/src/app/dashboard/referrals/page.tsx).

The audit table receives initial 50 rows from server-side pagination; its severity + action-search filters operate on THAT page only. Searching for "critical" while viewing page 1 misses critical events on pages 2+. UX bug — the filter UI implies a global search.

Push the search up to the URL (so pagination + filter compose) or add a "Searches this page only" hint.

### M10 — `dashboard/commissions/page.tsx:29` parses commission `amount` via `parseFloat` (v1 M10, unfixed)
File: [src/app/dashboard/commissions/page.tsx:25-33](../../apps/partner-dashboard/src/app/dashboard/commissions/page.tsx).

```ts
amount: parseFloat(c.amount),
```

CLAUDE.md and `formatCurrency`'s doc both say keep DECIMAL columns as strings on the wire. The `pendingTotal` and `paidTotal` reduces accumulate float drift. Either: (a) keep `c.amount` as a string and use `formatCurrency` directly per row (no client-side sum), or (b) consume a server-provided `pending_total`/`paid_total` field rather than summing client-side.

### M11 — `referralId: c.reference_id || c.id` masks server contract drift (v1 M11, unfixed)
File: [src/app/dashboard/commissions/page.tsx:32](../../apps/partner-dashboard/src/app/dashboard/commissions/page.tsx). The API field is `reference_id`. Falling back to `c.id` makes a missing `reference_id` invisible. Drop the fallback; render `'-'` if the field is missing.

### M12 — `dashboard/payouts/page.tsx` doesn't typed-confirm before requesting a payout (v1 M13, unfixed)
File: [src/app/dashboard/payouts/page.tsx:62-82](../../apps/partner-dashboard/src/app/dashboard/payouts/page.tsx). Suspend in `UserTable.tsx` confirms; admin commission approve confirms; user delete uses a typed-token modal. Payout button kicks off real Stripe transfers with no confirm. Add `confirm("Send $X.XX to your connected Stripe account?")` at minimum. The user-delete pattern (typed `SEND` token) is the highest bar.

### M13 — Page-level `requireAuth` calls do not exist for /dashboard pages (v1 M14, unfixed)
File: [src/app/dashboard/page.tsx](../../apps/partner-dashboard/src/app/dashboard/page.tsx) etc. Every admin page calls `requireAdmin()`; every dashboard page relies on the layout-level `requireRole('partner-or-admin')` only. Mirror admin's defence-in-depth pattern: each `dashboard/**/page.tsx` should also call `requirePartner()` directly. Note: the dashboard pages are `'use client'` — they CAN'T directly call the server action `requirePartner()`. So the pattern needs to be: split each page into a server-component shell that calls `requirePartner()` and a client component that does the rendering.

### M14 — `lib/types.ts` enum drift (v1 M15, unfixed)
File: [src/lib/types.ts](../../apps/partner-dashboard/src/lib/types.ts). `AdminCommission.status` is one inline string union; `CommissionStatus` is the exported alias. Inline strings re-occur in `admin-commission-table.tsx`. Centralize.

### M15 — Page-level `getPartner(id)` does NOT URL-encode (NEW)
File: [src/app/admin/partners/[id]/page.tsx:9-14](../../apps/partner-dashboard/src/app/admin/partners/[id]/page.tsx).

```ts
const { data: partner } = await serverApiClient<{ data: AdminPartnerDetail }>(`/api/v1/admin/partners/${id}`)
```

The id comes from route params (`Promise<{ id: string }>`) and goes straight into the URL. Next 14 already URL-decodes the param, but anything pre-decoded must be re-encoded before re-injection or `serverApiClient` will hit a malformed upstream URL. Wrap with `encodeURIComponent(id)`. Same idiom as `partner-actions.tsx:32`.

### M16 — `getCommissionStats` defaulting strategy hides 5xx as zeros (NEW)
File: [src/app/admin/commissions/page.tsx:18-25](../../apps/partner-dashboard/src/app/admin/commissions/page.tsx), [admin/page.tsx:7-29](../../apps/partner-dashboard/src/app/admin/page.tsx), [admin/audit/page.tsx:15-31](../../apps/partner-dashboard/src/app/admin/audit/page.tsx), [admin/analytics/page.tsx:9-53](../../apps/partner-dashboard/src/app/admin/analytics/page.tsx).

Every admin page does:
```ts
} catch {
  return { data: { total_pending_amount: 0, … }, error: true }
}
```

Then renders the zero values with a small banner "Failed to load data from the API. The values shown below may be inaccurate." That's actually a sensible UX pattern — but the FIRST signal an admin sees is large `$0` numbers. A panicky admin reads "0 pending commissions" before reading the banner. Two suggestions:

1. Render `—` or "Unavailable" in StatsCard slots when `error === true`, instead of zeroes, so the failure mode is visually obvious.
2. The banner copy says "may be inaccurate" — but the values are 0, not stale data; the copy should say "could not be loaded."

### M17 — `dashboard/payouts/page.tsx` `openTaxDocs` opens a window with no URL validation (NEW)
File: [src/app/dashboard/payouts/page.tsx:84-104](../../apps/partner-dashboard/src/app/dashboard/payouts/page.tsx).

```ts
const res = await apiClient<{ url: string }>('/api/v1/partners/me/tax-form-link', { method: 'POST' });
…
window.open(res.data.url, '_blank', 'noopener,noreferrer');
```

A tampered upstream response (or a misconfigured Stripe API call returning a bad URL) opens whatever it returns. The setting page's `handleStripeConnect` (`settings/page.tsx:151-186`) validates against `STRIPE_HOSTS` BEFORE redirecting — payouts doesn't.

Even if upstream is trusted, defense-in-depth: parse the URL, assert protocol === 'https:', assert hostname is in `STRIPE_HOSTS` (lift the constant out of `settings/page.tsx`), only then call `window.open`.

### M18 — `dashboard/gifts/page.tsx` `parseFloat`-style amount handling (NEW)
File: [src/app/dashboard/gifts/page.tsx:207](../../apps/partner-dashboard/src/app/dashboard/gifts/page.tsx).

```tsx
${(gift.amount_charged || 0).toFixed(2)}
```

Same gripe as M10. The interface declares `amount_charged: number`, but the API can serialize DECIMAL as string OR number. `(string || 0).toFixed` throws because strings have no `.toFixed`. Use `formatCurrency(gift.amount_charged ?? 0)`.

Same on `dashboard/gifts/[id]/page.tsx:261,365`.

### M19 — `audit-log-table.tsx` truncates `resource_id` slice without null-guarding the type (NEW)
File: [src/components/audit-log-table.tsx:189-191](../../apps/partner-dashboard/src/components/audit-log-table.tsx).

```ts
{log.resource_id && (
  <span className="text-haven-text-tertiary ml-1 font-mono text-xs">
    ({log.resource_id.slice(0, 8)}...)
  </span>
)}
```

If `log.resource_id` is a number (e.g. an integer FK), `.slice` throws. The `AuditLogEntry` interface in `types.ts:58` declares it `string`, but the table component's props are `any[]` (line 30: `initialLogs: any[]`). Tighten the prop type to `AuditLogEntry[]`.

### M20 — `audit-log-table.tsx` props are `any[]` (NEW)
File: [src/components/audit-log-table.tsx:30](../../apps/partner-dashboard/src/components/audit-log-table.tsx). Replace with `AuditLogEntry[]`.

Same on [admin-commission-table.tsx:8](../../apps/partner-dashboard/src/components/admin-commission-table.tsx) (`commissions: any[]`). Replace with `AdminCommission[]`.

### M21 — `audit-log-table.tsx` row click expands every nested mutation event to plaintext metadata (NEW)
File: [src/components/audit-log-table.tsx:198-247](../../apps/partner-dashboard/src/components/audit-log-table.tsx). Some `metadata` records carry email addresses, IP addresses, partial card numbers (per the API's audit logger). The component renders the JSON wholesale to the admin's screen. The 4 KB cap is good as a render-perf guard, but it doesn't redact PII before display. CLAUDE.md's logger has a `SENSITIVE_KEYS` redaction list; the audit table component doesn't apply anything similar. Either route the metadata through `lib/log-error.ts:sanitize` before stringifying, or mark fields like `partner_email`/`ip_address` as already-displayed-elsewhere and skip them from the metadata block.

This is more sensitive than v1 caught, since the audit table is a logged-in admin's view of every other user's actions — plaintext PII display is in scope for the audit-log discipline the rest of the system follows.

---

## Low

### L1 — `unauthorized/page.tsx` copy says "admin privileges" only (v1 L1, unfixed)
File: [src/app/unauthorized/page.tsx:12](../../apps/partner-dashboard/src/app/unauthorized/page.tsx). Soften to "you do not have permission to access this page."

### L2 — `forgot-password/actions.ts` doesn't normalize email (v1 L2, unfixed)
File: [src/app/forgot-password/actions.ts:9](../../apps/partner-dashboard/src/app/forgot-password/actions.ts). Apply `isValidEmail` + `normalizeEmail` before forwarding upstream.

### L3 — `dashboard/gifts/page.tsx:30-32` no AbortController on filter change (v1 L3, unfixed)
Same fix shape as H11.

### L4 — `lib/log-error.ts` only logs to console (v1 L4, unfixed)
Observability gap; not security. Out of scope for this audit unless we wire a `/api/v1/log` endpoint.

### L5 — `admin/settings/page.tsx` is a one-card placeholder (v1 L5, unfixed)
Either delete the page (and remove the sidebar entry) OR ship features. As-is it's dead-ish weight.

### L6 — `dashboard/page.tsx:201` fallback row keys can collide harmlessly (v1 L6, observation)
Correct as-is. Index disambiguates.

### L7 — `dashboard/gifts/[id]/page.tsx:437,447` `mailto:` and `tel:` use `encodeURIComponent` (v1 L7, unfixed)
File: [src/app/dashboard/gifts/[id]/page.tsx:437,447](../../apps/partner-dashboard/src/app/dashboard/gifts/[id]/page.tsx). `tel:%2B15551234567` is rejected by some dialers. For phone use `phone.replace(/\s+/g, '')`. For email, `mailto:` already URL-decodes — encoding is harmless but unnecessary.

### L8 — `settings/page.tsx:51` exhaustive-deps suppress (v1 L8, unfixed)
Move the bootstrap function inside `useEffect` directly, or memoize via `useCallback`.

### L9 — `error.tsx` files log no `error.message` (v1 L9, unfixed)
File: dashboard/error.tsx:18-21, admin/error.tsx:19-23. Right call for security; debugging gap. Route through `lib/log-error.ts:logError(label, err)` so the message gets scrubbed but is at least *present*.

### L10 — `lib/api.ts:99-100` `__timeout` property hack (v1 L10, promoted to H8 above)
See H8 for treatment.

### L11 — `dashboard/payouts/page.tsx:84-104` Referer-Policy concern (v1 L11, no action)
Stripe doesn't care about partner-portal origin in Referer. Confirmed safe.

### L12 — `dashboard/gifts/[id]/page.tsx:382-410` engagement timeline emoji (v1 L12, unfixed)
CLAUDE.md rule says no emoji unless explicitly requested. Swap for Heroicons.

### L13 — `dashboard/gifts/page.tsx:207` `(amount || 0).toFixed(2)` will throw on string amount (NEW, see M18)

### L14 — `gifts/page.tsx:182` row `key={gift.id}` is correct, but `gifts.map` filter scope is unbounded (NEW)
File: [src/app/dashboard/gifts/page.tsx:182](../../apps/partner-dashboard/src/app/dashboard/gifts/page.tsx). The fetch returns ALL gifts for the partner (no pagination), then renders the entire list. A power partner with 1000+ gifts has that whole table in the DOM. Add server-side pagination (the API supports it) or virtualize.

### L15 — `referrals/page.tsx` synthesizes referral status from `r.plan !== 'free'` (NEW)
File: [src/app/dashboard/referrals/page.tsx:39-43](../../apps/partner-dashboard/src/app/dashboard/referrals/page.tsx).

```ts
status: r.plan !== 'free' ? 'converted' : 'pending',
```

This conflates "user upgraded to premium AFTER signing up via referral" with "the referral converted." A user who signs up via the referral link and stays free shows as "pending" forever — even though they DID convert (signup is the conversion event). The actual conversion logic lives server-side in `partner_commissions`; the referrals page should consume that, not re-derive plan vs status.

### L16 — `lib/api.ts:120-124` swallows error name capture (NEW)
File: [src/lib/api.ts:120-125](../../apps/partner-dashboard/src/lib/api.ts).

```ts
} catch (err: unknown) {
  if (err && typeof err === 'object' && (err as { name?: string }).name === 'AbortError') {
    throw new ApiError('Request timed out. Please try again.', 408);
  }
  throw new ApiError('Network error. Please check your connection.', 0);
}
```

A `TypeError` (e.g. `Failed to fetch` on a CORS preflight reject) gets bucketed as "Network error" — true but obscures the underlying class. Not security, but logger-side it'd be useful to forward `err.name` to `logError` so devtools triage is faster.

### L17 — `commission-table.tsx:48` truncates `referralId` to 8 chars (NEW)
File: [src/components/commission-table.tsx:48](../../apps/partner-dashboard/src/components/commission-table.tsx).

```ts
{commission.referralId.slice(0, 8)}
```

If `referralId` is undefined or null (which the type declares it isn't, but the API allows it via the M11 fallback), `.slice` throws. Belt-and-suspenders: `(commission.referralId ?? '').slice(0, 8)`.

### L18 — `partner-table.tsx:286` `slice(0, 1024)` for reject reason (NEW)
File: [src/components/partner-table.tsx:286](../../apps/partner-dashboard/src/components/partner-table.tsx). Already done via maxLength, but the slice is in the onChange handler — a paste of 5000 chars gets visibly cut to 1024 mid-keystroke; inserts feel choppy. Just rely on `maxLength={1024}` and drop the slice. Pure UX nit.

### L19 — Audit log expanded row renders `metadata` raw — see M21 (NEW)

### L20 — `OnboardingClient` step 1 → step 2 navigation re-validates without server check (NEW)
File: [src/app/onboarding/client.tsx:128-141](../../apps/partner-dashboard/src/app/onboarding/client.tsx). Going from step 2 back to step 1 doesn't re-fetch the partner profile. If a different tab completed onboarding in parallel, the user clicking "Complete setup" on step 2 hits a 409. The action handles it (returns nice error) but the page-level `hasPartnerProfile` is only checked once on mount. Acceptable.

### L21 — `payouts/page.tsx:115-120` `canRequestPayout` formula doesn't check pending payout-in-flight (NEW)
File: [src/app/dashboard/payouts/page.tsx:114-120](../../apps/partner-dashboard/src/app/dashboard/payouts/page.tsx).

```ts
const canRequestPayout = !!summary && summary.stripe_payouts_enabled && summary.approved_amount > 0 && !requesting;
```

A user who clicks "Request payout", the request hangs for 25s, then they refresh the tab. `requesting` resets to `false` but the upstream Stripe transfer may still be in flight. They click again, second transfer fires. Server-side idempotency-key would catch this — see H10. Symptomatically: also store a "last_payout_request_id" client-side and disable button if a request is in the cooldown window (60s).

---

## Adversarial scenarios

### S1 — 100 MB POST mutation
See H4. Proxy buffers entire body before forwarding. Concrete: hold a 100 MB heap × 100 concurrent partners = OOM.

### S2 — Demoted admin's `hk_role_check` cookie cached for 30 s
The cookie holds. Middleware sees `isAdmin: true`. They navigate to `/admin/users` — middleware passes. Layout calls `requireRole('admin')` → `serverApiClient('/admin/me')` → API returns `is_admin: false` → `redirect('/unauthorized')`. Net: bad UX (admin nav rendered briefly), no privilege escalation. Acceptable per the audit's H-A8 design intent; worth logging when the cookie says yes but API says no.

### S3 — Logged-out user navigates to `/dashboard`
Middleware checks tokens (none) → `NextResponse.redirect(new URL('/login', request.url))`. No `?from=` → user re-authenticates and lands on `/dashboard` root, not where they wanted (see H6).

### S4 — Cross-origin POST with `sec-fetch-site: cross-site`
Proxy `originGuardOk` returns false → 403 + `'Cross-origin request rejected'`. CSRF check never runs. Correct.

### S5 — Forged CSRF token
`csrfTokenOk(request)` checks header byte-by-byte against cookie. Length mismatch → fast-fail. Same length, different bytes → constant-time XOR comparison fails. The dashboard's csrf check is constant-time-ish (the loop iterates through every byte). Note: the API's `crypto.timingSafeEqual` is stronger; the dashboard rolls its own — see also concern below about subtle differences.

### S6 — Upstream returns 502
Proxy `fetch` throws → `error: 'Service unavailable', message: 'Unable to connect…'` JSON, status 502. UI in `apiClient` reads `errorData.error` → throws `ApiError('Service unavailable', 502)`. `dashboard/error.tsx` renders generic. **No way for the user to retry except `reset()`.**

### S7 — Upstream times out (>30 s)
Proxy `controller.abort()` → 504 + `'Request timed out'`. Dashboard renders generic error.

### S8 — Partner with `stripe_account_status='disabled'` clicks Request Payout
Server enforces (apps/api/src/routes/partners.ts:887-891) → 409 with friendly message. Dashboard `apiClient` throws `ApiError(message, 409)`. The `requestPayout` handler in [payouts/page.tsx:74-77](../../apps/partner-dashboard/src/app/dashboard/payouts/page.tsx) reads `res.error || 'Payout request failed'` — but the message lives on the THROWN error, not on `res.error` (which is undefined since `apiClient` already threw). The user sees the generic fallback "Payout request failed. Please try again." — losing the server's helpful "Stripe Connect onboarding is not complete (current status: 'disabled')" message.

Bug: handler's catch block should pull `err.message` via the ApiError instance, not from `res.error`.

---

## Tests — coverage gaps

### Tests that exist
- `middleware.test.ts` — 12 cases. Covers root redirect, public-route bypass, partner / admin role gating, refresh OK + fail, expired token w/ public route. Good baseline.
- `refresh-race.test.ts` — 4 cases. Covers `looksLikeJwt` rejection of `'a.b'`, refresh-with-non-JWT body rejection, refresh fetch abort, single-flight `apiClient` coalescing.
- `lib/auth.test.ts` — 12 cases. Token-shape, getTokens, getUser (incl. 401, 5xx, ApiUnavailableError), requireAuth, set/clearAuthCookies.
- `lib/api.test.ts` — 12 cases. apiClient happy path, body, credentials:include, 401-refresh-retry, refresh-fails-redirect, abort timeout.
- `lib/utils.test.ts` — 8 cases. formatCurrency. **Does NOT test `isSafeActivationUrl` or `isSafeLogoUrl`.**
- `actions/login.test.ts` — 8 cases. Generic error on invalid creds, redirect by role, etc. **Does NOT test the MFA-required response (because the action doesn't handle it — see C3).**
- `actions/signup.test.ts` — 8 cases. Email validation, password policy, full-name required.
- `components/{AuthForm,DashboardPage,Pagination,StatsCard}.test.tsx` — render + footer logic.

### Coverage gaps from v1 (still missing)
- **Path-validation cases** (`..`, encoded slashes, unicode, `.`-only segment) — would have caught C2.
- **CSRF cookie+header mismatch** — no test for `csrfTokenOk` directly.
- **Response-header reduction** — does the proxy actually strip `Set-Cookie`? Untested.
- **`originGuardOk`** — particularly the missing-header → false case.
- **`isSafeActivationUrl` / `isSafeLogoUrl`** — protocol allowlist + hostname allowlist.

### NEW gaps v1 didn't flag
- **MFA-required login response** — there's no test asserting the action handles `data.mfa_required === true`. There's also no `/mfa/challenge` page in the dashboard at all (C3).
- **Idempotency-Key forwarding** — no test asserting `serverApiClient` and `apiClient` either pass-through or auto-mint idempotency keys (H10).
- **`fetchFreshRole` 5xx fallback** — no test asserting the JWT-claim fallback only fires on network errors, not on API-returned 5xx (H9).
- **Edge `redirectToLogin` cookie clears** — no test asserting `hk_role_check` is cleared in the future-fixed code (would catch H2 regressions).
- **Proxy upstream-URL builder** — no direct test exercising `buildUpstreamUrl` against `..`, mixed-case `%2E`, unicode home-glyph normalization, oversized segments. ALL of C2 is untested.
- **Dashboard `redirectToLogin` carries `?from=`** — no test for H6's UX issue.

The actions / api / auth tests are fine but don't cover the rest of the surface (proxy, middleware role-cache, csrfTokenOk). The middleware tests don't exercise the role-cookie write paths, so the H1/H2 fixes would land without test coverage unless explicitly added.

---

## State management cross-check

### Server vs client component boundaries
- Admin pages: server components, no client state leak.
- Dashboard pages: ALL client components except layout. `requireRole('partner-or-admin')` is the only server-side gate. M13 above.
- `/onboarding/page.tsx` is a server component that delegates to `OnboardingClient` — clean split.

### useEffect dependency hygiene
- `dashboard/page.tsx:51-58` — empty deps, refers `fetchAnalytics` via closure. eslint-disable-next-line. Matches the pattern of one-shot bootstrap. Acceptable.
- `dashboard/gifts/page.tsx:30-32` — deps `[filter]`. No AbortController. L3.
- `dashboard/analytics/page.tsx:71-73` — deps `[fetchAnalytics]` (a `useCallback`). H11.
- `dashboard/settings/page.tsx:39-51` — empty deps, eslint-disable. L8.
- `dashboard/gifts/[id]/page.tsx:59-66` — deps `[giftId]`, eslint-disable. AbortController via inflight ref. ✓

### useRef AbortController pattern
Three pages do it correctly: `dashboard/page.tsx`, `gifts/[id]/page.tsx`, `dashboard/settings/page.tsx`. Three pages don't: `dashboard/gifts/page.tsx` (L3), `analytics/page.tsx` (H11), `dashboard/commissions/page.tsx` (one-shot — less critical), `dashboard/referrals/page.tsx` (one-shot), `dashboard/payouts/page.tsx` (one-shot). Where the page is one-shot, a tab unmount mid-fetch can leak a setState into an unmounted component — minor.

### Race conditions on rapid filter changes
- `dashboard/gifts/page.tsx` filter tabs (L3): yes
- `dashboard/analytics/page.tsx` date range (H11): yes
- `dashboard/referrals/page.tsx` filter tabs: client-side filter only (no fetch on tab change). Safe.

---

## API cross-check

- **CSRF header.** API expects lowercase `x-csrf-token` (apps/api/src/middleware/csrf.ts:5). Dashboard sends `X-CSRF-Token` (lib/api.ts:93) and proxies match case-insensitively (`get('sec-fetch-site')` etc are already lowercase). HTTP headers are case-insensitive on transport, so this is fine.

- **`Idempotency-Key` header.** API matches both `idempotency-key` and `Idempotency-Key` in `req.headers` (apps/api/src/middleware/idempotency.ts:49). Proxy allowlist contains `'x-idempotency-key', 'idempotency-key'`. Dashboard's `apiClient` and `serverApiClient` neither auto-mint nor accept idempotency-key. H10.

- **`Authorization: Bearer …`.** Proxy mints `Authorization: Bearer ${accessToken}` (route.ts:84). API decodes Bearer (apps/api/src/middleware/auth.ts). Match.

- **`/auth/login` MFA branch.** API returns `{success: true, data: {mfa_required: true, mfa_token, factor_types}}`. Dashboard reads `data.accessToken`. C3.

- **`/auth/role-check`.** API returns `{success: true, data: {user_id, is_admin, is_partner}}`. Dashboard middleware reads `data.is_admin`/`data.is_partner`. ✓.

- **`/admin/me`.** API returns user payload wrapped in `{success: true, data: {...}}`. Dashboard `getUserUncached` reads `data.data.id`/`data.data.email`/etc. ✓.

---

## Summary

| Severity | Count | Δ vs v1 |
|---|---|---|
| Critical | **3** (C1 v1; C2 + C3 NEW) | +2 |
| High | 11 (H1-H10 + H11; v1 H1-H4 + 6 new + H7 false-alarm strike) | +6 |
| Medium | 21 (M1-M21 with two false-alarm strikes; 6 new) | +5 |
| Low | 21 (12 v1 + 9 new) | +9 |

**Must-fix-before-prod additions to the C1 already on v1's list:**
- **C2 (path traversal via `..` in SAFE_SEGMENT)** — the proxy's stated job is "the only thing between the browser and the upstream API". A literal-`..` bypass that the regex didn't fail closed on is the exact failure the v1 audit's path-validation tests were supposed to catch. Trivial regex tightening fix.
- **C3 (no MFA support in dashboard login)** — any partner or admin enabling MFA via the mobile app immediately loses dashboard access. A live partner who turns this on becomes a support ticket. Requires building the `/mfa/challenge` page + `/auth/mfa/challenge` exchange in the action.

The High tier is split between cookie hygiene (H1-H3 unfixed v1 items), proxy memory safety (H4 unfixed), and 6 new defense-in-depth gaps. H10 (no Idempotency-Key forwarding) is the most operationally important new finding — without it, the audit Ch10-W021 single-flight discipline is half-implemented.

The Medium tier dominates with consistency / drift items (M1, M11, M14, M15, M18, M20) plus PII concerns in audit log display (M21) and the typed-confirm gap on payouts (M12). M11 (`payouts.openTaxDocs` doesn't validate URL like `handleStripeConnect` does) is a real cross-handler inconsistency.

Three test gaps deserve immediate remediation:
1. `buildUpstreamUrl` direct tests with `..`, `.`, `%2e%2e`, oversized segments. Would have caught C2.
2. `csrfTokenOk` direct tests covering all the rejection paths.
3. `fetchFreshRole` API-failure-mode tests — both 5xx (should NOT fall back to JWT) and network (should fall back).

The proxy at `route.ts` is otherwise quite tight — the cross-app CSRF invariant comment (lines 51-75) is excellent reviewer documentation, the cookie strip + post-loop `out.delete('cookie')` is correct defense-in-depth idiom, and the response-header allowlist + Set-Cookie strip is the right shape. C2 is the one place the proxy itself fails closed — and it's a regex bug, not a model bug.
