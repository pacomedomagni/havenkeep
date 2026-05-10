# Audit Run 06 — Partner Dashboard (Next.js)

**Scope.** `apps/partner-dashboard/middleware.ts`, `src/app/api/v1/[...path]/route.ts`, `src/app/api/auth/{refresh,logout}/route.ts`, `src/lib/*`, every page under `src/app/{login,signup,forgot-password,reset-password,onboarding,unauthorized,dashboard,admin}`, every component under `src/components/`, and the test suite under `src/__tests__/`. The Express API itself, the database, the mobile app, and the marketing site were out of scope (other agents own them).

**Date.** 2026-05-10
**Branch.** main (clean)

**Headline.** The hardening effort is real and the major attack surfaces are tight: the proxy strips cookies + enforces a header allowlist + double-submit CSRF + same-origin guard + response-header reduction; the Edge middleware drives auth via API-derived role caches rather than unverified JWT claims; logout is CSRF-checked. The single critical finding is a `next.config.js` rewrite that, when `API_UPSTREAM_URL` is set, **completely bypasses the proxy and ships the browser's cookies upstream** — that one env var inverts every guarantee in the proxy doc. Everything else is medium/low: a few inconsistencies (admin commission action URLs not URL-encoded; `clearAuthCookies` doesn't clear `hk_role_check`; `STRIPE_HOSTS` does not include `stripe.com` for live links; CSP enables `unsafe-inline` script-src), an inflight-controller gap on `/dashboard/analytics`, and a stash of low-impact UX gaps.

Severity legend: **Critical** = auth bypass / CSRF hole / data exposure · **High** = silent failure / data corruption / drift that breaks contract · **Medium** = UX bug / dead code / inconsistency · **Low** = cosmetic.

---

## Critical

### C1 — `next.config.js` rewrites `/api/v1/*` upstream when `API_UPSTREAM_URL` is set, bypassing the entire proxy
File: `apps/partner-dashboard/next.config.js:74-83`

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

Next.js `afterFiles` rewrites do NOT take precedence over the file-system Route Handler at `src/app/api/v1/[...path]/route.ts`, so under normal conditions the proxy wins. **But** rewrites are matched against the *original* request URL, and any other route shape that sneaks through the matcher (e.g. an early-bird route, an `_app/_next` rewrite, or a future folder reorg) will defer to this rule. In an environment where the App Router file ever loses (404, build error, route shape change) the dashboard will start sending the *browser's cookies* — including `hk_access_token` httpOnly *and* the unprotected `csrf_token` — directly to the upstream API.

Two compounding problems:
1. The proxy is the only thing minting `Authorization` from `hk_access_token` and stripping cookies (Section 4.2 invariant in `route.ts:51-75`). Bypassing it routes raw cookies to upstream. The upstream API's `validateCsrfToken` middleware is documented to **bypass CSRF when no cookies are present**; with cookies present from this rewrite, the upstream would expect a matching `x-csrf-token`. The browser fetch from the dashboard does send `X-CSRF-Token`, so functionally it might still work — but every same-site mutation (e.g. a malicious app on `*.havenkeep.com`) can ride the cookie because no proxy CSRF check fires.
2. There is no documentation tying `API_UPSTREAM_URL` to any deployment; it isn't in `.env.local.example` (which lists `API_URL` and `NEXT_PUBLIC_API_URL` only) and it isn't read anywhere else in the dashboard codebase. So this rewrite block is a **footgun stub** — code that does nothing in the documented environments but silently turns the proxy off if anyone ever copy-pastes the env var.

**Fix.** Delete the rewrite block — the proxy at `src/app/api/v1/[...path]/route.ts` is the single supported upstream path and the rewrite block contradicts it.

---

## High

### H1 — `clearAuthCookies` does NOT delete `hk_role_check`
File: `src/lib/auth.ts:11-12`, `src/lib/auth.ts:165-169`

```ts
const CLEARABLE_COOKIES = [ACCESS_TOKEN_COOKIE, REFRESH_TOKEN_COOKIE, CSRF_COOKIE] as const;
…
export function clearAuthCookies(cookieStore: …) {
  for (const name of CLEARABLE_COOKIES) {
    cookieStore.delete(name);
  }
}
```

Logout (and any other session-clearing path) leaves `hk_role_check` in place. The cookie is httpOnly so JS can't forge it, but it's also a 30-second cache of `{isAdmin, isPartner}` keyed on no signature and read by middleware before the JWT is decoded (`middleware.ts:317`). Concrete consequences:

- A user logs out, then logs in as a *different* user whose access cookie hasn't been refreshed yet. The stale `hk_role_check` from session A drives middleware routing for up to 30 s — could redirect a partner-only user to `/admin` and the layout would then `redirect('/unauthorized')`. UX bug, not a privilege escalation, but ugly.
- More importantly, this violates the doc's intent (Ch10 audit `hk_role_check` design says it should match the auth cookies' lifetime).

**Fix.** Add `'hk_role_check'` to `CLEARABLE_COOKIES`. Also clear it in `redirectToLogin()` in `middleware.ts:94-100` so the failure path on the edge is symmetric with `/api/auth/logout`.

### H2 — Edge `redirectToLogin` does NOT delete `hk_role_check`
File: `middleware.ts:94-100`

```ts
function redirectToLogin(request: NextRequest): NextResponse {
  const response = NextResponse.redirect(new URL('/login', request.url))
  response.cookies.delete(ACCESS_TOKEN_COOKIE)
  response.cookies.delete(REFRESH_TOKEN_COOKIE)
  response.cookies.delete(CSRF_COOKIE)
  return response
}
```

Same root cause as H1 but at the edge layer. Every refresh-failure / malformed-token path lands here and leaves the role cache cookie behind. With its 30-second TTL the cached role can drive middleware decisions on the *next* request even though the access cookie has been wiped. Not exploitable for privilege escalation (the page-level `requireRole` re-fetches user via API) but every cleared session should clear every cookie.

### H3 — `/api/auth/refresh` route does NOT clear cookies on validation/401 failure paths
File: `src/app/api/auth/refresh/route.ts:33-58`

The refresh route returns 401 with `{ error: 'Session expired' }` when the refresh token is missing/malformed (line 33-35), when the upstream rejects refresh (line 48-50), or when the upstream returns a malformed response (line 57-59). None of those paths call `clearAuthCookies`. A subsequent request still carries the now-known-bad `hk_refresh_token` cookie; the client `apiClient` in `src/lib/api.ts:127-146` then redirects to `/login`, which the middleware *does* handle with `redirectToLogin`. So in practice the cookie does get cleared eventually — but the refresh route having an inconsistent contract is a footgun if anyone wires another caller (e.g. a periodic background refresh) that doesn't follow up with a navigation.

**Fix.** Call `clearAuthCookies(cookieStore)` in every 401-return branch of `refresh/route.ts`. Cheap, defensive, makes the contract self-evident.

### H4 — `/api/v1/[...path]` proxy has no per-request body-size limit
File: `src/app/api/v1/[...path]/route.ts:132-133`

```ts
const body =
  method === 'GET' || method === 'HEAD' ? undefined : await request.arrayBuffer();
```

The proxy reads the entire request body into memory before forwarding. No `Content-Length` check, no streaming, no max-size guard. A logged-in malicious actor can send a 100 MB POST and the proxy will buffer all of it before talking to the API. Same on the response side: `await response.arrayBuffer()` (line 148) buffers the entire upstream payload.

The 30-second `controller.abort()` (line 137) bounds *time*, not *bytes*. A slow-stream attack or a buggy upstream that returns a 50 MB JSON payload will hold the proxy's memory until completion.

The dashboard's expected mutation bodies are tiny (gift create, partner profile, ~few KB), so a 1 MB request cap and a 5 MB response cap would be reasonable and would not break any existing UX. Add `if (request.headers.get('content-length') > MAX_REQUEST_BYTES) return 413` and stream the response via `response.body` directly into `NextResponse` rather than buffering.

### H5 — `originGuardOk` rejects every `sec-fetch-site: 'none'` request, including legitimate first-loads / Safari edge cases
File: `src/app/api/v1/[...path]/route.ts:101-107`

```ts
function originGuardOk(request: NextRequest): boolean {
  const fetchSite = request.headers.get('sec-fetch-site');
  return fetchSite === 'same-origin' || fetchSite === 'same-site';
}
```

The header is sent as `'none'` for user-typed URLs and some Safari version bugs. The proxy treats `'none'` as cross-origin and rejects mutations. For mutations that's correct — a user can't directly type a `POST` from the URL bar — but it also rejects mutations from very old browser versions (Edge < 79, Safari < 14, certain Chrome embeds) that don't send the header at all. The guard correctly returns `false` for missing header (which is what the doc intent describes), so the failure mode is "mutation rejected" not "mutation allowed", which is the right direction. **Not a security hole — a UX gap on legacy browsers.** Confirmed by reading 4.2 cross-app invariant comment in the same file (line 51-75): the design relies on this being tight, so leaving it strict is correct.

Worth a comment in the file explaining why the `'none'` value is intentionally rejected — the next maintainer might think it's a bug and loosen it.

---

## Medium

### M1 — Admin commission action URLs do NOT URL-encode the commission id
File: `src/components/admin-commission-table.tsx:45,66,87`

```ts
await apiClient(`/api/v1/partners/admin/commissions/${commissionId}/approve`, …);
await apiClient(`/api/v1/partners/admin/commissions/${commissionId}/pay`, …);
await apiClient(`/api/v1/partners/admin/commissions/${commissionId}/cancel`, …);
```

Compare with `partner-table.tsx:77`, `partner-actions.tsx:32`, `UserTable.tsx:63,81` — all encode their ids via `encodeURIComponent`. The Ch10-W055 fix wired encoding into every other admin URL builder. The admin commission table didn't get the same treatment. In practice commission ids are server-generated UUIDs so the bug is latent, but consistency matters and the proxy's `SAFE_SEGMENT` would 400 the request if a malformed id ever slipped in, surfacing as an opaque "Failed to approve commission" toast. Wrap each `${commissionId}` in `encodeURIComponent`.

### M2 — `STRIPE_HOSTS` allowlist on `/dashboard/settings` is missing `stripe.com`
File: `src/app/dashboard/settings/page.tsx:9-14`

```ts
const STRIPE_HOSTS = new Set([
  'stripe.com',                  // ← present
  'connect.stripe.com',
  'dashboard.stripe.com',
  'checkout.stripe.com',
]);
```

Re-reading: `stripe.com` IS present. Apologies — false alarm. **Strike this finding** but leaving the file:line for the reviewer's sanity check. The allowlist matches the doc's Ch10-W022 intent.

### M3 — `isSafeActivationUrl` allowlist hardcodes `havenkeep.com` only; staging gift-link copy will fail
File: `src/lib/utils.ts:30-53`

```ts
const allowed = new Set([
  'havenkeep.com',
  'www.havenkeep.com',
  'app.havenkeep.com',
  'partners.havenkeep.com',
]);
…
if (process.env.NODE_ENV !== 'production' && url.hostname === 'localhost') return true;
```

In staging (`NODE_ENV=production` is true on the Docker image, per CLAUDE.md "staging deployment" section) the partner UI will refuse to copy a `staging.havenkeep.app` activation URL to clipboard. The user gets `'That activation URL failed validation and was not copied.'` — confusing on a working staging environment. The brief flagged this directly.

**Fix.** Either (a) add `'staging.havenkeep.app'` to the allowed set, or (b) read the allowed set from a server-config endpoint, or (c) drive it from `NEXT_PUBLIC_APP_URL`. Option (a) is the least intrusive.

Also note: the doc says the marketing site is `havenkeep.com`, the mobile app uses `havenkeep.app`. Production probably wants `app.havenkeep.app` here too. Whichever — pick one and document it.

### M4 — `dashboard/analytics/page.tsx` does NOT use the inflight-AbortController pattern
File: `src/app/dashboard/analytics/page.tsx:35-73`

The analytics page rapidly re-fetches via `useCallback` keyed on `[startDate, endDate]`, but unlike `dashboard/page.tsx:49-79`, `gifts/[id]/page.tsx:48-88`, and `dashboard/settings/page.tsx:39-69`, it has no `useRef<AbortController>` to cancel an in-flight request when the date range changes again. A user typing rapidly in the date inputs can queue 5+ in-flight requests; whichever returns last wins, which is not necessarily the user's last input. The fix is the same pattern the other pages use:

```ts
const inflight = useRef<AbortController | null>(null);
const fetchAnalytics = useCallback(async () => {
  inflight.current?.abort();
  const controller = new AbortController();
  inflight.current = controller;
  …
  if (controller.signal.aborted) return;
}, [startDate, endDate]);
useEffect(() => {
  fetchAnalytics();
  return () => { inflight.current?.abort(); inflight.current = null; };
}, [fetchAnalytics]);
```

Same thing on `dashboard/commissions/page.tsx` and `dashboard/referrals/page.tsx` and `dashboard/payouts/page.tsx` — none use the inflight ref. They are mounted once and re-fetched on user action only, so the consequences are smaller, but a tab-switch / back-button / unmount can leak a setState into an unmounted component.

### M5 — CSP is `'unsafe-inline'` on `script-src` (defeats much of the CSP)
File: `next.config.js:42`

```
"script-src 'self' 'strict-dynamic' https: 'unsafe-inline'",
```

The comment above (line 39-41) says "Next 14 still emits a small inline bootstrap; allow it via 'self' + the runtime nonce. We do NOT enable 'unsafe-inline'." — but the value literally contains `'unsafe-inline'`. This is the textbook CSP foot-gun: in browsers that honor `'strict-dynamic'`, the `'unsafe-inline'` is ignored; in older browsers, it isn't. The doc intent is correct (use nonces) but the implementation drops the guard.

Next 14 supports nonces via `next.config.js`'s `experimental.nonce` plus middleware-level nonce injection. The cleaner fix is to add `'nonce-<random>'` per request via middleware and remove `'unsafe-inline'`. As written this is partly mitigated by `'strict-dynamic'` (only modern browsers honor the directive that ignores `'unsafe-inline'`) but the comment claiming the directive is absent is a lie.

Update the comment OR remove `'unsafe-inline'` and ship a nonce. Don't leave the contradiction.

### M6 — `forgot-password` action surfaces upstream 400 message verbatim (anti-enumeration leak risk)
File: `src/app/forgot-password/actions.ts:22-32`

```ts
if (response.status === 400) {
  return { error: data.error || data.message || 'Please enter a valid email address' };
}
```

Every other server action (login, signup, reset-password) returns *generic* copy on the way up. Forgot-password leaks `data.error || data.message` from the upstream API on a 400. The intent (line 24-25 comment) is "don't reveal whether the email exists" — and the code does fall through to `return null` on success cases — but the 400 branch passes the upstream string verbatim. If the upstream ever changed to return e.g. `"User not found for email foo@bar.com"`, the dashboard would render it directly. The dashboard's password-reset / login do NOT have this hole.

**Fix.** Mirror login: `return { error: 'Please enter a valid email address' };` regardless of upstream payload.

### M7 — `setAuthCookies` does NOT validate the refresh token shape; signup blindly trusts upstream
File: `src/app/signup/actions.ts:60-66`

```ts
const data = body?.data;
if (!data?.accessToken || !data?.refreshToken) {
  return { error: 'We could not create your account. Please try again.' };
}

const cookieStore = await cookies();
setAuthCookies(data.accessToken, data.refreshToken, cookieStore);
```

Compare with `login/actions.ts:64-72` which uses `looksLikeJwt(data.accessToken)` — signup does NOT. A misconfigured upstream that returns `accessToken: 'whatever'` will land junk in `hk_access_token`, then the next page navigation hits middleware which detects the malformed JWT and bounces back to `/login`. Functional, but a small consistency gap. Add the `looksLikeJwt` check on `data.accessToken` and `data.refreshToken` before calling `setAuthCookies` — the same way login does it.

### M8 — `clearAuthCookies` test fails to verify CSRF cookie is cleared
File: `src/__tests__/lib/auth.test.ts:246-250`

```ts
it('deletes both cookies when clearing', () => {
  clearAuthCookies(mockCookieStore as any);
  expect(mockCookieStore.delete).toHaveBeenCalledWith(ACCESS_TOKEN_COOKIE);
  expect(mockCookieStore.delete).toHaveBeenCalledWith(REFRESH_TOKEN_COOKIE);
});
```

The test asserts the access + refresh cookies are deleted but doesn't assert `csrf_token` is also deleted. If H1's fix lands and adds `hk_role_check` to the clear list, the test will still pass blind. Strengthen with an explicit count: `expect(mockCookieStore.delete).toHaveBeenCalledTimes(N)` where N is the full clear-list length.

### M9 — `commissions` and `referrals` and `audit` pages: filtering happens client-side after a single fetch
File: `src/app/dashboard/commissions/page.tsx:11-42`, `src/app/dashboard/referrals/page.tsx:25-58`, `src/components/audit-log-table.tsx:35-50`

Each page fetches all rows from the API once and filters in-memory by the active tab. With pagination at 50/page that's fine, but the audit-log table has no pagination loop in `audit-log-table.tsx` — it filters whatever was passed in initialLogs. The audit page's outer `getAuditLogs` does paginate (50/page), so the client-side filter is on a 50-row window only. If a user is searching for a 'critical' event that happened 100 rows back, they'll silently miss it because the search only sees the current page. Either push the search up to the URL (so pagination follows) or warn the user "filtering only on this page".

This isn't security-critical but it's an honest UX bug — the filter UX implies global search and delivers per-page search.

### M10 — `dashboard/commissions/page.tsx:29` parses commission `amount` as float (precision loss)
```ts
amount: parseFloat(c.amount),
```

The CLAUDE.md comment in `dashboard/page.tsx:14-18` and the `formatCurrency` doc in `lib/utils.ts:9-15` explicitly say to keep DECIMAL columns as strings/numbers (the canonical wire shape) without parseFloat. This file ignores that guidance, which means the per-row total in the page's `pendingTotal` / `paidTotal` reduces (`commissions.tsx:44-50`) accumulate float drift on long lists. Real-world impact: tiny (cents off on hundreds of commissions). Direction is wrong for the stated discipline.

**Fix.** Either keep `c.amount` as the string and use `formatCurrency` directly on it (as `dashboard/page.tsx` does), or maintain a server-provided `pending_total` / `paid_total` field rather than client-side sums.

### M11 — `dashboard/commissions/page.tsx:32` includes `referralId: c.reference_id || c.id` — the fallback masks server contract drift
```ts
referralId: c.reference_id || c.id,
```

The API was changed from `referral_id` → `reference_id` (per `lib/types.ts`). Falling back to `c.id` if the API ever ships a partial response means a row's commission would get rendered keyed by its own ID rather than being skipped or flagged. If the API drops `reference_id` from the response, the bug is silent. Either drop the fallback (let it render `'-'` or skip the row) or surface a server validation error. The "ALL means ALL" rule says don't backfill unless the user OKs it.

### M12 — `dashboard/commissions/page.tsx`, `dashboard/referrals/page.tsx`: no `noopener` analog needed but they `as any` the response
```ts
const data = await apiClient<any[]>('/api/v1/partners/commissions');
```

Shared response types exist in `lib/api-types.ts`. The pages fall back to `any[]` instead of `Commission[]` / `Referral[]`. Type-safety drift. Replace with `apiClient<AdminCommission[]>(…)`.

### M13 — `dashboard/payouts/page.tsx` does NOT confirm before requesting a payout
File: `src/app/dashboard/payouts/page.tsx:62-82`

The payout button kicks off a real Stripe transfer with no `confirm(...)` step. Compare with `admin-commission-table.tsx:36-77` which confirms approve/pay/cancel and `UserTable.tsx:60` which confirms suspend. Payouts are reversible at Stripe level but a single misclick triggers real bank wire fees. Suggest a typed confirm modal mirroring the user-delete pattern: "Type SEND to confirm the $X.XX payout."

### M14 — Dashboard page-level `requireAuth` calls do not exist — only layout-level
Files: `src/app/admin/page.tsx:41`, `src/app/admin/users/page.tsx:16`, `src/app/admin/partners/page.tsx:23`, `src/app/admin/commissions/page.tsx:32`, `src/app/admin/audit/page.tsx:38`, `src/app/admin/health/page.tsx:76`, `src/app/admin/analytics/page.tsx:56`

Every admin page calls `requireAdmin()` AND the layout calls `requireRole('admin')`. That's the correct defence-in-depth (matches the Ch10-W044 layout-gate intent). But the dashboard side is *not* defended in depth: `dashboard/page.tsx`, `dashboard/gifts/page.tsx`, `dashboard/payouts/page.tsx`, `dashboard/settings/page.tsx`, `dashboard/commissions/page.tsx`, etc. all rely *only* on the layout (`dashboard/layout.tsx:13` calls `requireRole('partner-or-admin')`). If anyone ever extracts a `dashboard` page outside the layout context (e.g. a future redirect / new variant), the page would be unprotected.

Mirror admin's pattern: each `dashboard/**/page.tsx` should also call `requirePartner()` directly. Cheap, makes the protection self-evident.

### M15 — `lib/types.ts` does not include the per-page status enums (drift between table and types)
The `AdminCommission` interface in `lib/types.ts:28-38` has `status: 'pending' | 'approved' | 'paid' | 'cancelled'`. The `commission-table.tsx:11` uses an exported `CommissionStatus`. The `admin-commission-table.tsx` uses inline string types `'pending' | 'approved' | 'paid' | 'cancelled'` again. Two slightly different definitions of the same enum. Drift risk if the API ever adds a new status (e.g. `'disputed'`) — only the inline list needs updating in two places.

Centralize in `lib/types.ts`.

---

## Low

### L1 — `unauthorized/page.tsx` copy says "admin privileges" only
File: `src/app/unauthorized/page.tsx:12`

```html
<p>You do not have admin privileges to access this dashboard.</p>
```

Both partners and admins land here when their role doesn't match the route. A partner bouncing off `/admin` sees "you do not have admin privileges" (correct). A non-partner-non-admin user bouncing off `/dashboard` (the layout enforces `partner-or-admin`) also sees it (less correct). Soften: "You do not have permission to access this page." The user's actual role doesn't matter — they get the same UI either way.

### L2 — `forgot-password/actions.ts:9` reads `formData.get('email') as string` without normalization
The login + signup actions use `isValidEmail` + `normalizeEmail`. Forgot-password just trusts the browser. So an email of `'  Foo@Example.com  '` is sent verbatim to the upstream. The upstream presumably normalizes again — but if it doesn't, two requests for `Foo@example.com` and `foo@example.com` may register as different rate-limit keys.

Apply `normalizeEmail(rawEmail)` and the validity check before forwarding. (This is a self-evident anti-enumeration UX bug — you can probe email shapes by getting different error messages.)

### L3 — `dashboard/gifts/page.tsx:32` re-fetches on every `filter` change without aborting the previous request
File: `src/app/dashboard/gifts/page.tsx:30-32`

```ts
useEffect(() => {
  fetchGifts();
}, [filter]);
```

Same flavor as M4 — rapid filter clicks queue overlapping fetches; the last to return wins. A user toggling `all → pending → activated` quickly might see `pending` data render under the `activated` tab. Add the inflight-ref pattern.

### L4 — `lib/log-error.ts` only logs to console; no upstream ingest
The Express side has structured logging via Pino → Loki (per CLAUDE.md). The dashboard's `logError` just hits `console.error` after sanitizing. In production browsers the user's devtools is closed, so these logs evaporate. If you want a record of "the dashboard's gift page failed to load for partner X at time Y", you need a small `/api/v1/log` endpoint + a `navigator.sendBeacon` call. Not a security finding — an observability gap.

### L5 — `src/app/admin/settings/page.tsx` has only Account Information; the section is one card
This isn't a bug — just observation. The page exists, renders email + ID, and that's all. If admin settings is meant to grow features, fine; if it's a placeholder, leave a TODO… wait, the rules say no TODOs. Either delete the page (and remove the sidebar nav) OR ship the features that justify it. As-is it's dead-ish weight.

### L6 — `dashboard/page.tsx:201` row keys use `created_at`-fallback that can collide
```ts
key={`${activity.created_at ?? 'noDate'}-${index}`}
```

If two activities both have `created_at: null`, the keys are `noDate-0`, `noDate-1` — fine because `index` differentiates. ✓ This is correct, just verbose. (No action needed.)

### L7 — `dashboard/gifts/[id]/page.tsx:437,447` calls `mailto:` and `tel:` with `encodeURIComponent`
These two protocol handlers don't follow URL encoding rules — `encodeURIComponent` on a phone number breaks the `+` sign in international format (`+15551234567` becomes `%2B15551234567` and most dialers won't accept that). Switch to a no-op or use `tel:${phone.replace(/\s+/g, '')}` and validate at write-time.

### L8 — `dashboard/settings/page.tsx` `useEffect` dependency suppresses lint
File: line 51 — `// eslint-disable-next-line react-hooks/exhaustive-deps`. The bootstrap function captures `router.push` and `loadStripeStatus` etc., none of which are stable references. The current pattern works (the effect is intentionally one-shot) but the suppress comment is the wrong fix — the right fix is to put the bootstrap function inside `useEffect` directly or memoize it via `useCallback`. Minor.

### L9 — `apps/partner-dashboard/src/app/dashboard/error.tsx:9-10` and `admin/error.tsx:13-15` log nothing useful
Both logs only `error.name` and `error.digest` (no message). That's the right call for security (avoid leaking internals to console for screen-watchers) but it makes debugging "user reports white screen" almost impossible — without `error.message`, the dev tab shows no signal. Consider a `logError(label, err)` that uses the existing sanitizer in `lib/log-error.ts` so message gets scrubbed but is at least *present*.

### L10 — `lib/api.ts:99-100` mutates the AbortController's signal with a custom `__timeout` property
```ts
(controller as AbortController & { __timeout?: ReturnType<typeof setTimeout> }).__timeout =
  timeout;
```

Stashing a timer ID on the controller object is clever but fragile — any future iteration over the controller's properties will trip on it. The standard pattern is to store the timeout in the surrounding closure and clear it on success/error. The current code already does this in `send()` line 110-114, so the property assignment is dead weight — the `clearTimeout(timeout)` in `send()` reads the same timer via property access but you could just close over the local. Small refactor.

### L11 — `dashboard/payouts/page.tsx:84-104` `openTaxDocs` → `window.open(... 'noopener,noreferrer')` — correct, but no Referer-Policy override
The CSP/Referrer-Policy in `next.config.js:25` is `strict-origin-when-cross-origin`, so the browser will send `https://partners.havenkeep.com` (origin only) as the referer. That's leaking the partner-portal origin to Stripe. Stripe doesn't care, so this is fine. **No action.**

### L12 — `dashboard/page.tsx:201` activity item rendering uses emoji icons via inline strings
File: `dashboard/gifts/[id]/page.tsx:382-410` (engagement timeline)

The CLAUDE.md rules say "Only use emojis if the user explicitly requests it". The page has emoji glyphs `📨 👀 📱 🏠 ✅` baked into the icon arrays. If the user wants emoji-free UI, swap to Heroicons. (Not a security/correctness issue — calling it out per the project rule.)

---

## Tests — coverage gaps

The audit asked specifically about three coverage areas:

1. **Path-validation cases (.. / encoded / unicode).** The proxy's `SAFE_SEGMENT` regex and the decode-then-test logic in `buildUpstreamUrl` (`route.ts:38-49`) is **not directly tested** — the test file is all middleware-level. Add a `proxy.test.ts` that exercises `..`, `%2e%2e`, encoded slashes, unicode home-glyph attempts, and oversized segments.
2. **Refresh race scenario.** Covered in `refresh-race.test.ts:155-186` — single-flight refresh assertion is solid. Good.
3. **CSRF cookie+header mismatch.** **Not tested.** No test for `csrfTokenOk` directly; no test for the proxy returning 403 when CSRF mismatches; no test for the logout route's CSRF-required path. Add a `csrf.test.ts` that covers (a) cookie missing, (b) header missing, (c) different lengths (the constant-time-ish comparison rejects), (d) same-length-but-different-bytes, and (e) the happy path. Also add an end-to-end proxy mutation test to lock the CSRF + same-origin guards together.

Other gaps:
- No test for the proxy's response-header reduction (does it actually strip Set-Cookie?). `route.ts:91-99`.
- No test for `originGuardOk` — particularly the "missing header → false" case.
- No test for `clearAuthCookies` clearing the role cache once H1 ships (the cookie surface is currently incomplete).
- No test for the `STRIPE_HOSTS` validation in `dashboard/settings/page.tsx`.

---

## Summary

| Severity | Count |
|---|---|
| Critical | 1 (C1 — rewrite footgun) |
| High | 5 (H1-H5) |
| Medium | 15 (M1, M3-M15; M2 was a false alarm on re-read) |
| Low | 12 (L1-L12) |

**The single must-fix-before-prod item is C1.** Delete the rewrite block in `next.config.js` — it is a code path that, when accidentally enabled by an env var, silently bypasses every proxy guarantee. Everything else is incremental.

The H-class items (H1-H4) are about defence-in-depth and contract consistency — none represent a current exploit path, but each is a "you'll regret not fixing this" item the next time someone refactors. H5 is comment-only.

The Medium tier is dominated by drift / consistency issues (M1, M7, M11, M14, M15) and UX gaps (M3, M4, M9, M13). M5 (CSP `'unsafe-inline'`) deserves attention because the comment in the code explicitly disclaims what the value enables.

The Low tier is mostly cosmetic plus L12 (emoji in UI, per project rule) and L2 (forgot-password normalization).

The proxy at `src/app/api/v1/[...path]/route.ts` is in good shape — the comments documenting the cross-app CSRF invariant (lines 51-75) are exactly the kind of thing a reviewer needs to *not* foot-gun a future change. The `buildForwardedHeaders` defence-in-depth `out.delete('cookie')` after the allowlist iteration (line 87) is the right idiom: if a future allowlist edit ever puts `cookie` back in, the post-loop delete kills it.

The Edge middleware's switch from JWT-claim-derived roles to API-derived roles via `hk_role_check` (Ch10-W008) is correctly done. The fallback to JWT claims on API failure (line 325-326) is documented as intentional, but worth noting in a comment that this fallback DOES allow the unverified JWT body to drive routing for up to ROLE_CHECK_TIMEOUT_MS — fine for routing hints, would be a hole if any authorization decision ever rode this path. Currently no authorization decision rides this path (the page-level `requireRole` re-derives via API).
