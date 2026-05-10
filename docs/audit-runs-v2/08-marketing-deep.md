# Audit 08 (deep) — Marketing site, legal claims, deep links, cross-cutting drift

Scope: deep, per-file pass over `apps/marketing/src/**`, the two `/.well-known/`
files, `apps/marketing/scripts/build-og-image.cjs`, `astro.config.mjs`,
`tailwind.config.mjs`, the marketing `package.json`, every blog `*.json` +
matching `*.astro`, the checked-in `caddy/havenkeep.caddyfile`, the
`.env.example` files for api / mobile / partner-dashboard, the root `.gitignore`,
and the cross-cutting copy/code drift the v1 pass surfaced.

The v1 file is at `docs/audit-runs/08-marketing-cross-cutting.md`; everything
in v1 still applies. This file is **additive** — it documents what v1 missed,
goes deeper on what v1 only sketched, and carries every cross-doc / cross-file
drift the audit-rerun checklist asked for.

Severity legend (matches the rest of the v2 run):
- **C — Critical** — false privacy/security claim, fictional sub-processor /
  cookie list (regulatory exposure), broken Universal Link, secrets leak,
  marketing claim that a feature exists when no code path implements it,
  unfulfillable contractual promise (partner tier, refund, retention).
- **H — High** — drift between two on-site claims, missing sub-processor that
  the policy is silent on, env-example missing keys the code requires, hardcoded
  staging vs prod URL in Astro layout, blog publish-date drift listing-vs-page.
- **M — Medium** — copy nit that misleads but is not a contractual breach,
  orphan page, missing OG image for an orphan, broken anchor, stale or invented
  marketing collateral (jobs, awards, technology stack).
- **L — Low** — cosmetic / nit / future-proofing.

---

# CRITICAL findings

## C1 — `/cookies` page is wholesale fabricated; lists sub-processors that don't exist (Intercom, Cloudflare, Google Analytics, retargeting pixels)

[apps/marketing/src/pages/cookies.astro](apps/marketing/src/pages/cookies.astro):37-66, 70-77, 97-100

The cookie policy claims:
- **Performance Cookies** — "Google Analytics (anonymized)", "Page load performance monitoring", "Error tracking"
- **Marketing Cookies** — "Ad conversion tracking", "Retargeting pixels", "Social media cookies (when you share content)"
- **Third-Party Cookies set by us** — "Google Analytics", "Stripe", "Intercom: Customer support chat", "Cloudflare: Security and performance optimization"
- **Cookie Consent Tool** — "When you first visit our website, you'll see a cookie consent banner that allows you to choose which types of cookies you want to accept. You can change your preferences at any time by clicking the 'Cookie Settings' link in the footer."

**None of these are true.** I grepped:
- `grep -rn "intercom\|Intercom\|cookie consent\|cookieConsent\|cookie banner" apps` — only the cookies.astro file itself; no banner, no consent tool, no Intercom widget.
- `grep -rn "google.analytics\|gtag\|analytics\.google" apps/marketing` — nothing.
- The `Cloudflare` mention is fictitious; HavenKeep runs behind Caddy on a single Digital Ocean droplet (per CLAUDE.md Part 2; no Cloudflare in front).
- The footer ([apps/marketing/src/components/Footer.astro](apps/marketing/src/components/Footer.astro):42-51) has zero "Cookie Settings" link.
- Privacy policy ([legal/privacy.astro](apps/marketing/src/pages/legal/privacy.astro):75-90) explicitly says "We do not have any advertising SDKs in the app." — directly contradicting the cookies page's "Marketing Cookies → Ad conversion tracking, Retargeting pixels, Social media cookies".

**Why this is critical:** the cookies page is a regulatory document. ICO / CNIL / state DPA enforcement actions hinge on accurately describing what cookies you set. Listing four third-party cookie providers you do not use is a textbook "false-statement-in-a-data-protection-disclosure" finding. Combined with the "Cookie Settings" footer link that doesn't exist, this is also a UX/contract failure (user reads "you can change your preferences," tries, fails — that's an Article 7 GDPR consent-withdrawability problem).

**Required fix (severity C):** rewrite cookies.astro from first principles. The actual cookie inventory I found: the contact + newsletter forms run `credentials: 'omit'` — the marketing site sets **no cookies of its own**; the only cookies any visitor gets are the ones Astro's static output doesn't set, i.e. **none**. The page should say:

> HavenKeep's marketing site (havenkeep.com) does not set first-party cookies, embed third-party analytics, or run retargeting pixels. The mobile app uses your device's secure storage for authentication tokens and does not set browser cookies. Stripe sets cookies on its hosted checkout pages when you complete a purchase, governed by Stripe's own cookie policy.

Then delete every section that claims things we don't do.

---

## C2 — Privacy policy lists sub-processors that don't include OpenAI (the receipt scanner), even though every Premium-paying user is uploading photos of receipts to OpenAI

[apps/marketing/src/pages/legal/privacy.astro](apps/marketing/src/pages/legal/privacy.astro):76-90 lists:

> Google (Firebase Auth, Crashlytics, Cloud Messaging, Sign-In) | Apple (Sign in with Apple, APNs) | Microsoft (Outlook OAuth) | Stripe | RevenueCat | SendGrid | Our own servers (Postgres + MinIO)

Code reality:
- [apps/api/src/routes/receipts.ts](apps/api/src/routes/receipts.ts) — every Premium user's receipt photo is base64'd and POSTed to OpenAI for OCR (the file goes "straight to OpenAI as base64", per the code comment at line 21). Per-user usage is logged in `openai_usage` and retained for 90 days ([index.ts:299](apps/api/src/index.ts)).
- [apps/api/src/services/email-scanner.service.ts](apps/api/src/services/email-scanner.service.ts) — emailed receipt extraction also uses OpenAI for content parsing.

**OpenAI is a sub-processor handling user-content data**, period. It is silently absent from the privacy policy's third-party list. CCPA §1798.140(g) and GDPR Article 28 both require accurate sub-processor disclosure; California specifically requires data processors to be named in the privacy policy when consumer data is shared. A user who exercises their CCPA right-to-know request and is told "we share data with Google, Apple, etc." while the API silently sends every uploaded receipt to OpenAI has a deceptive-practices complaint with very clean evidence.

There are also implicit sub-processors the privacy policy is silent on:
- **DigitalOcean** — the droplet hosting Postgres + MinIO + the API ("our own servers" misrepresents this; the data is on a third party's hardware under DigitalOcean's TOS).
- **Loki / Grafana Cloud** (if the Loki URL points there). The `LOKI_URL` env exists for log shipping; if production points it at Grafana Cloud or another managed Loki host, that's another sub-processor.
- **Crashlytics** is technically a Firebase service so it's covered by "Google (Firebase…)" — but the parenthetical in the policy lists Auth/Crashlytics/Cloud Messaging/Sign-In and is correct. (Privacy verified clean here — see V1 cross-check below.)

**Required fix (severity C):**
1. Add **OpenAI** to the third-party list with the data category ("receipt photos and email-receipt text extracted for warranty/purchase recognition").
2. Add **DigitalOcean** (or whoever hosts Postgres / MinIO in production — pick after Part 3 production decisions are made; for now, "DigitalOcean (US)" matches the staging deploy).
3. If `LOKI_URL` will point to a third-party Loki host in production, add that. If it points at a self-hosted box on the same droplet, the existing "our own servers" line covers it.
4. Rephrase "Our own servers — Postgres for application data, MinIO for receipt photos. Self-hosted, not on a third-party cloud database." The "not on a third-party cloud database" phrasing is misleading — a managed VM on DO is still third-party infrastructure even if Postgres itself is self-installed. Suggest: "Postgres + MinIO running on our infrastructure (DigitalOcean droplet); raw data is not handed to a managed-database vendor, but the underlying compute and storage are provided by DigitalOcean."

---

## C3 — Privacy promise "you can opt out of telemetry in Settings → Privacy → Telemetry" — that screen does not exist in the mobile app

[apps/marketing/src/pages/legal/privacy.astro:71](apps/marketing/src/pages/legal/privacy.astro):

> "We log limited usage events (e.g. 'item created', 'reminder dismissed') so we know which features get used and where users get stuck. These events are linked to your account, and **you can opt out in Settings → Privacy → Telemetry.**"

Searched the mobile codebase:
- `find apps/mobile/lib/features/settings -type f` — 9 screens. None is a Privacy or Telemetry screen.
- `grep -rEn "telemetry|optOut|opt_out|Privacy.*Telemetry|TelemetrySettings|TelemetryScreen"` — only one hit in `splash_screen.dart`, in a code comment about telemetry pipelines, not a UI surface.

**Right-to-object (GDPR Article 21) consequence:** the privacy policy publicly contracts that the user can withdraw consent for non-essential telemetry. The user opens the app and there's no toggle, no setting, no way to do it. That's a violated contractual term and an Article 21 enforcement target. CCPA §1798.120 has a parallel "right to opt out of sale/sharing" that, while telemetry isn't "sale," is close enough that "we promised you a toggle, and there isn't one" is a practical liability.

**Required fix (severity C):** either ship the toggle (Settings → Privacy → Telemetry, hooked up to a `telemetry_opt_out` user flag the API checks before recording usage events), OR delete the sentence from the privacy policy and replace it with the truth ("usage events are linked to your account; deleting your account removes them"). Shipping the policy without the toggle is the worst of both worlds.

---

## C4 — Privacy promise "Settings → Data → Export" — that screen does not exist; only `/api/v1/items/export.csv` exists, and only Premium users can hit it via the (un-shipped) export UI

[legal/privacy.astro:124](apps/marketing/src/pages/legal/privacy.astro):

> "Export — download all your items, warranties, and uploaded documents in a portable format from Settings → Data → Export."

Searched mobile + API:
- `find apps/mobile/lib/features/settings -type f` — no Data screen, no Export screen.
- `grep -rEn "DataExportScreen\|export.*screen\|ExportSettings"` — zero hits.
- API has only one export endpoint: `apps/api/src/routes/items.ts:168` `GET /api/v1/items/export.csv` — items only, **not warranties, not uploaded documents**, no portable archive (zip with originals + JSON), no PDF.

The privacy policy is overpromising on the GDPR Article 20 "right to data portability." A user requesting an export today cannot get one through the app. They could email `privacy@havenkeep.com` and ask, but the policy promises a self-serve flow. Article 20 specifies "a structured, commonly used and machine-readable format" — CSV of items alone, without warranties or uploaded documents, is a partial export that doesn't meet the article's standard.

**Required fix (severity C):** ship the actual export — `GET /api/v1/me/export` that returns a zip with `items.json` + `warranties.json` + `documents/<id>/<original-filename>` — and a Settings → Data → Export screen that triggers it. Until that ships, soften the policy to "to request a copy of your data, email privacy@havenkeep.com" and remove the in-app path claim.

The same `Settings → Data → Export` claim appears verbatim on the **delete-account page** is implicitly via the privacy-policy link, and the FAQ ([faq.astro:57-58](apps/marketing/src/pages/faq.astro)) tells Premium users they can "export their full warranty database, receipts, and documents as PDF or CSV files at any time." Same problem — only items.csv works.

---

## C5 — Privacy claim "Mobile clients pin the leaf certificate on production builds" is false (already in v1 as C2; reaffirmed and broadened)

[legal/privacy.astro:97](apps/marketing/src/pages/legal/privacy.astro):

> "Mobile clients additionally pin the leaf certificate on production builds so a compromised CA can't intercept HavenKeep traffic."

V1 documented that no `SecurityContext`, no `badCertificateCallback`, no `_spkiMatches` is wired in any release-mode mobile path. Re-grep confirms — only the doc-comment block in [packages/api_client/lib/src/client.dart:202-217](packages/api_client/lib/src/client.dart). No production code path constructs a pinned IOClient.

Adding to v1's analysis:
- Even the **OG-image build script** ([apps/marketing/scripts/build-og-image.cjs:85](apps/marketing/scripts/build-og-image.cjs)) leaks the false claim into the marketing security card: `tagline: 'TLS pinning, encryption at rest, no Sentry'`. Anyone landing on `/security` from a social-share will see "TLS pinning" as a featured selling point for SEO purposes — without that pinning existing.

**Required fix:** v1's C2 fix (either implement SPKI pinning or delete the privacy claim) **also applies to the build-og-image.cjs PAGES list**: change the security tagline to something we can prove ("AES-256 encryption, TLS 1.3 in transit"). Otherwise the lie persists in OG snapshots even after the privacy policy is fixed.

---

## C6 — `/licenses` page lists React Native and Expo as core dependencies, but the mobile app is **Flutter**

[apps/marketing/src/pages/licenses.astro](apps/marketing/src/pages/licenses.astro):18-48

The page advertises:
- **React Native** — "A framework for building native apps using React" (line 23) — MIT license
- **Expo** — "An open-source platform for making universal native apps" (line 39) — MIT license

CLAUDE.md Part 2:
> `apps/mobile` — **Flutter** (Dart SDK ^3.0.0). Riverpod, Dio …

Confirmed by [apps/mobile/pubspec.yaml] — every dep is Flutter / Dart. There is no React Native, no Expo, anywhere in the codebase. They were never used.

The careers page ([careers.astro:12](apps/marketing/src/pages/careers.astro)) doubles down: the "Senior Full-Stack Engineer" job description says "React Native, TypeScript, and Node.js" — the React Native part is fictitious for this product. Same page advertises a "Mobile Engineer (iOS)" position to "Build native iOS features and optimize our mobile experience for iPhone and iPad" — possibly accurate if you consider Flutter native builds, but the page's framework name (React Native) is wrong.

The cookies page (already C1) also says "Cloudflare" which we don't use.

**Required fix (severity C):**
1. Replace the React Native + Expo entries in licenses.astro with the actual Flutter dep stack: **Flutter SDK**, **Dart SDK**, **Riverpod**, **Dio**, **GoRouter**, **Drift+SQLCipher** (the "encrypted on-device DB" mentioned in the privacy policy + security pages), **firebase_messaging**, **firebase_crashlytics**, **purchases_flutter** (the actual RevenueCat SDK), **google_sign_in**, **sign_in_with_apple**.
2. Replace the careers job description's "React Native" with "Flutter / Dart" — otherwise applicants apply expecting React Native, and the first interview question is awkward.
3. Audit: the "Stripe Node.js Library" entry on `licenses.astro:178-192` is correct — `apps/api` does use it. Express, PostgreSQL, TypeScript, Tailwind, Astro, Redis, jsonwebtoken — all correct. **Only the React Native + Expo entries need to be replaced.** The "Complete Dependency List" link at the bottom points to `https://github.com/havenkeep` which doesn't exist (see C7).

---

## C7 — `https://github.com/havenkeep` and `https://twitter.com/havenkeep` social handles in Footer + Contact + Licenses pages are unverified — possibly squatted / hijacked

Multiple files link to:
- `https://github.com/havenkeep` — [Footer.astro:83](apps/marketing/src/components/Footer.astro), [contact.astro:197](apps/marketing/src/pages/contact.astro), [licenses.astro:201](apps/marketing/src/pages/licenses.astro)
- `https://twitter.com/havenkeep` — [Footer.astro:78](apps/marketing/src/components/Footer.astro), [contact.astro:192](apps/marketing/src/pages/contact.astro)

I cannot verify from inside the repo whether HavenKeep owns these handles. The licenses.astro link to `https://github.com/havenkeep` for the "Complete Dependency List" implies an open-source organisation that may not exist — clicking it could land users on a 404 or a parked-name page run by a squatter.

**Required action (severity C — pre-launch):**
1. Manually verify `github.com/havenkeep` is owned by HavenKeep. If it's a squatter, file a GitHub username-conflict report under Trust & Safety. If the org doesn't exist yet, create it and pin a placeholder repo.
2. Same for `twitter.com/havenkeep` (or `x.com/havenkeep`).
3. If you don't intend to maintain a public GitHub org or X presence pre-launch, **remove the social-icon links** from Footer + Contact + Licenses entirely. A 404 link signals "abandoned product," and a squatted link signals "we don't own our brand."

---

## C8 — `apps/marketing` reads `import.meta.env.PUBLIC_API_URL` and `PUBLIC_PARTNER_DASHBOARD_URL` but ships **no `.env.example`**, and is not in repo's `.gitignore` allowlist either

[apps/marketing/src/pages/contact.astro:244](apps/marketing/src/pages/contact.astro):
```ts
const apiUrl = (import.meta.env.PUBLIC_API_URL as string | undefined) ?? '';
```

[apps/marketing/src/pages/blog.astro:189](apps/marketing/src/pages/blog.astro), [verify-email-change.astro:90](apps/marketing/src/pages/verify-email-change.astro), [partners.astro:12](apps/marketing/src/pages/partners.astro) — same pattern. The contact / newsletter / verify-email-change features all silently no-op (POST to `''`) when these vars aren't set.

`ls apps/marketing/.env*` returns nothing — there is no example file. A new dev cloning the repo runs `npm run dev` in `apps/marketing/`, the page renders, the contact form submits to `/api/v1/contact` (the empty prefix becomes a relative URL hitting the marketing dev server's port), and the request 404s with no error in dev tools.

**Required fix (severity C — onboarding-blocking):** create `apps/marketing/.env.example`:
```
# Marketing-side env (Vite-prefixed; everything bundled into the
# client must be PUBLIC_*).

# Backend API. In dev: http://localhost:3000.
# Caddy production: https://api.havenkeep.com
PUBLIC_API_URL=http://localhost:3000

# Partner-dashboard host. In dev: http://localhost:3001.
# In production: https://partners.havenkeep.com (or partner.* on staging).
PUBLIC_PARTNER_DASHBOARD_URL=http://localhost:3001
```
Add corresponding `apps/marketing/.env.development` / `.env.production` to `.gitignore` (or rely on the global `.env*` rule that already covers it). Currently the global `.env*` rule means a real `apps/marketing/.env` would be ignored — but **the example file would also be ignored** unless explicitly excluded. The root `.gitignore` for `apps/api` and `apps/mobile` makes `.env.example` an explicit exception via the API/mobile-relative tracking; same exception needed for marketing.

---

# HIGH findings

## H1 — Blog post pages display dates that DON'T match their JSON frontmatter dates — listing/RSS sort by JSON, page body shows the hardcoded constant

For each post, the JSON frontmatter date (used by [blog.astro:13-21](apps/marketing/src/pages/blog.astro) for sorting + display, used by [rss.xml.js:18](apps/marketing/src/pages/rss.xml.js) for `pubDate`) and the **hardcoded `const date = "..."` inside the post page** disagree:

| Post | JSON date (`content/blog/*.json`) | Page constant (`pages/blog/*.astro`) |
|---|---|---|
| `cost-of-lost-warranties` | `2025-01-20` | `October 28, 2024` |
| `extended-warranties-worth-it` | `2025-01-13` | `October 22, 2024` |
| `organize-home-warranties` | `2025-01-27` | `November 5, 2024` |
| `warranties-you-should-never-ignore` | `2025-02-03` | `November 10, 2024` |
| `warranty-rights` | `2025-01-06` | `October 15, 2024` |
| `warranty-claims-guide` | `2025-02-10` | (uses `<time datetime="2025-02-10">February 10, 2025</time>` — correct) |

So a visitor sees the listing page say "January 20, 2025," clicks through, and the article header says "October 28, 2024" — three months earlier. RSS readers (Feedly, Reader, etc.) get the JSON date as `<pubDate>`, sort the post into January 2025; users following the link see October 2024. SEO impact: Google treats the page-body date as the canonical "datePublished" hint when no `<time>` element is present, so search-result snippets will show the older date — potentially de-ranking the blog over time.

**Required fix (severity H):** delete the hardcoded `const date = "..."` from each post page and use a `getEntry('blog', slug)` lookup to render the JSON-frontmatter date with `<time datetime={...}>`. The `warranty-claims-guide.astro` page already does this correctly — make every post follow that pattern.

---

## H2 — Pricing page hero says "$2/mo" — Premium component says "$2.99/month" or "$24/year ($2/mo)" — the hero is technically wrong (the $2 figure is annual-divided-by-12, only true for annual billing)

[pricing.astro:21](apps/marketing/src/pages/pricing.astro): "HavenKeep Premium starts at **$2/mo**"
[pricing.astro:124](apps/marketing/src/pages/pricing.astro): monthly billing card says "$2.99/month"
[pricing.astro:294](apps/marketing/src/pages/pricing.astro): FAQ "$24/year, compared to $2.99/month ($35.88/year)"
[Pricing.astro (component):14-15](apps/marketing/src/components/Pricing.astro): "HavenKeep Premium starts at **$2/mo**" (same as page hero)

The "$2/mo" framing is a marketing simplification — annual ($24/yr) divided by 12 = $2/mo. The actual monthly billing rate is $2.99. A user who reads "starts at $2/mo," picks the **Monthly** toggle, and sees $2.99 may feel mildly bait-switched. CCPA / FTC don't have a clear-cut rule against per-month-equivalent pricing display, but the FTC's "deceptive pricing" guidance (16 CFR §233) leans toward "the lowest price commonly charged for a single billing period" — which would be $24/yr, not $2/mo.

**Required fix (severity H):** change hero copy to "$24/yr (or $2.99/mo if you prefer monthly billing)" or "Premium is $24/yr — works out to about $2/mo." The ambiguity of "starts at $2/mo" without the "annual billing" caveat is the failure mode.

---

## H3 — Pricing FAQ #1 "we'll prorate any charges or credits" is wrong — Apple + Google handle proration, not us. (V1 M4 reaffirmed; severity bumped to H because this is a contractual claim about billing.)

[pricing.astro:254](apps/marketing/src/pages/pricing.astro). V1 noted this as M4. After re-reading [terms.astro:79-89](apps/marketing/src/pages/legal/terms.astro), the terms correctly defer to "the platform under its published policy" — but the pricing FAQ says "Changes take effect immediately, and we'll prorate any charges or credits." The two pages disagree on **who controls billing**.

If a user reads the pricing FAQ and then disputes a non-prorated change with Apple, they'll cite the HavenKeep page that promised proration — and HavenKeep cannot deliver. That's a deceptive-billing-practice exposure.

**Required fix (severity H):** rewrite to "Plan changes follow the App Store / Google Play policy on the platform you signed up through. Apple does not prorate within the same family unless you switch durations; Google's proration is set per app — see the in-app upgrade screen for the exact terms before you confirm."

---

## H4 — Pricing FAQ #2 "We keep your data for 30 days after cancellation in case you change your mind" — false, conflates **subscription cancellation** with **account deletion**. (V1 M3 reaffirmed; severity bumped to H.)

[pricing.astro:264](apps/marketing/src/pages/pricing.astro). V1 said this needs a rewrite. Re-reading: a user cancels Premium → they are downgraded to Free, their data **stays indefinitely** (subject to free-tier item limit visibility, but the rows aren't deleted). The FAQ tells them their data has a 30-day clock that starts at sub cancellation. That misleads users into either (a) believing they have a fire-drill to export within 30 days when they don't, or (b) believing their data will be deleted automatically — and then complaining when it isn't.

The FAQ #2 in faq.astro ([faq.astro:74-76](apps/marketing/src/pages/faq.astro)) repeats the same broken claim:
> "We keep your data for 30 days after cancellation in case you change your mind, then permanently delete it."

Both FAQs are wrong. **Required fix (severity H):** rewrite both occurrences:
> "Cancelling Premium does NOT delete your data. Your account stays on the Free plan; your last 5 active items remain visible (the rest are archived but accessible if you re-upgrade later). To permanently delete your data, see the Delete Account page."

---

## H5 — Hardcoded canonical URL in Layout.astro will leak `https://havenkeep.com` into staging og:url + twitter:url + `<link rel="canonical">` (V1 H5 reaffirmed; widening the scope.)

[apps/marketing/src/layouts/Layout.astro:58-63](apps/marketing/src/layouts/Layout.astro):
```ts
const canonicalUrl = canonicalPath
  ? `https://havenkeep.com${canonicalPath}`
  : `https://havenkeep.com${Astro.url.pathname}`;
```

V1 covered this. Additional findings on re-review:
- The same hardcoded base shows up in `absoluteOgImage` ([Layout.astro:61-63](apps/marketing/src/layouts/Layout.astro)). Every staging social-card preview will render `og:image=https://havenkeep.com/og/<slug>.png` — pointing at the **production** OG asset URL, which won't exist until production launches. So today, every staging Twitter / iMessage / Slack preview embed will fail to load the OG image (production URL doesn't resolve).
- `astro.config.mjs:22` also pins `site: 'https://havenkeep.com'`. Astro's built-in `Astro.site` reads from this and is what `@astrojs/sitemap` uses to generate `<loc>` entries. So **the staging sitemap also says https://havenkeep.com**, which means:
  - Googlebot crawls staging's sitemap-index.xml → reads `<loc>https://havenkeep.com/about</loc>` → fetches the production URL → 404 (production isn't live yet) → no indexing.
  - Or worse, when production launches, Google has been hitting a non-existent URL for months and has aged-out the discovery cycle. The first prod-deploy will need a Search Console re-submit.

**Required fix:** read `Astro.site` (or a per-environment `PUBLIC_SITE_URL`) and configure staging compose to set `PUBLIC_SITE_URL=https://staging.havenkeep.app`. Also add a `<meta name="robots" content="noindex">` on staging-only via env-conditional rendering — or risk Googlebot indexing the staging URLs and treating them as duplicate content of production once both are live.

---

## H6 — Privacy + Security pages disagree on TLS version (v1 H1) AND on encryption-at-rest descriptions

V1 H1 documented the TLS version drift. Re-reading both pages with the receipt-photo claim in mind, there's a SECOND drift:

| Page | Encryption-at-rest claim |
|---|---|
| `legal/privacy.astro:98` | "AES-256-GCM for sensitive fields in the database; full-disk encryption on the database host; receipts and photos encrypted in object storage." |
| `security.astro:38, 51` | "Sensitive fields are encrypted at the application layer with AES-256-GCM, the database disk is fully encrypted, and the on-device database on your phone is encrypted with SQLCipher (AES-256)." (no mention of object storage) |
| `Hero.astro:91` | "**AES-256** encrypted" (no algo qualifier) |
| `Features.astro:31`  | "AES-256-GCM on sensitive fields, TLS 1.3 in transit, full-disk encryption at rest, **and an encrypted on-device database**." |
| `about.astro:160` | "We use **AES-256** encryption at rest, TLS 1.3 in transit" (no mention of GCM mode, no on-device DB) |
| `faq.astro:54` | "Sensitive fields are encrypted at the application layer with AES-256-GCM, the database disk is fully encrypted, and the local on-device database uses SQLCipher (AES-256). Everything is sent over TLS 1.3." |

Six different framings of the same encryption story. The underlying truth (per code grep):
- **AES-256-GCM** is used for OAuth refresh tokens (`utils/oauth-encryption.ts`) and MFA secrets (`mfa.service.ts`). NOT for general "sensitive fields in the database" — only those two.
- **SQLCipher AES-256** is the mobile on-device DB (correct).
- **Full-disk encryption on the DB host** — depends on whether DigitalOcean's volume encryption is enabled. Not visible from this repo.
- **Receipt + photo encryption in object storage** — V1 H2 already established that no SSE-S3 header is set on `putObject` calls, and bucket-level default encryption isn't documented anywhere.

**Required fix (severity H):** pick one phrasing and apply it everywhere. Suggest:
> "We encrypt OAuth tokens and 2FA secrets at the application layer with AES-256-GCM. The database host is full-disk encrypted, and the on-device mobile database uses SQLCipher (AES-256). Photos and receipts in object storage are encrypted by the storage layer; data flows over TLS 1.3 (with TLS 1.2 fallback)."

That phrasing is honest about *what* is application-layer encrypted (just OAuth + MFA, not "all sensitive fields"), defers object-storage encryption to "the storage layer" (which lets ops handle the actual MinIO config), and unifies the TLS line.

---

## H7 — `apps/marketing` is missing `.env.example` AND the cookies/licenses pages aren't gated by `import.meta.env.PUBLIC_*` despite being meant to be production-only

This is a different angle on C8, severity H rather than C because it's not strictly onboarding-blocking — you can deploy without env vars set. But the pages will silently degrade:

- **`/cookies`** has no env-conditional logic — it ships the cookie banner reference unconditionally even though no banner exists.
- **`/contact`** and **`/blog`** newsletter form silently no-op when `PUBLIC_API_URL` is unset (`fetch('/api/v1/contact')` becomes a same-origin POST to a 404).

**Required fix:** add the env example (C8) AND add a build-time assertion in `astro.config.mjs` that fails the build if `PUBLIC_API_URL` is missing on production. Use `import.meta.env.MODE` to skip the assertion in dev.

---

## H8 — `apps/api/.env.example` is missing several env vars that the API actually reads

The example file lists `LOG_LEVEL` (not actually read — confirmed by grep), `BACKUP_S3_*` (commented; actual backup script doesn't exist per V1 H3). It is **missing**:

- `COMMISSION_AUTO_APPROVE_HOLD_DAYS` — read at [apps/api/src/index.ts:78](apps/api/src/index.ts), defaults to `'30'`. A new dev wanting to test the auto-approve sweep with a shorter window has no documented var.
- `DB_CLIENT_LEAK_THRESHOLD`, `DB_IDLE_IN_TRANSACTION_TIMEOUT`, `DB_SLOW_QUERY_THRESHOLD` — referenced by `intFromEnv(...)` in the config layer; absent from `.env.example`.
- `TEST_REDIS_URL` — read in tests; not in example.
- `MINIO_PORT` — not in `.env.example` (only `MINIO_ENDPOINT` is there); read at [config/index.ts:97](apps/api/src/config/index.ts) `intFromEnv('MINIO_PORT', 9000)`.

The example file's header comment explicitly says it should be "regenerated from the union of `process.env.*` reads." It is not currently in sync. **Required fix:** regenerate from the actual reads.

The example **also has**:
- `LOG_LEVEL=info` — never read; pino logger uses `isProd ? 'info' : 'debug'` directly. Either delete from `.env.example` or wire it up.
- `BACKUP_S3_*` block (lines 200-207) — references "scripts/backup-database.sh" that doesn't exist (V1 H3). Either ship the script or delete the env block.

---

## H9 — `apps/mobile/.env.example` is missing the Firebase API keys and the marketing/Gmail config (V1 C4 reaffirmed; widening to specific list)

V1 documented this. Concrete diff against the actual reads in `apps/mobile/lib/`:

Currently in `.env.example`: `API_BASE_URL`, `LOKI_URL`, `REVENUECAT_API_KEY`, `OUTLOOK_CLIENT_ID`, `OUTLOOK_TENANT`, `OUTLOOK_REDIRECT_URI`, `GOOGLE_SERVER_CLIENT_ID`, `APPLE_SERVICES_ID`, `APPLE_REDIRECT_URI`.

Missing (but read in code AND present in `.env.staging` with empty values):
- `FIREBASE_ANDROID_API_KEY`, `FIREBASE_ANDROID_APP_ID`
- `FIREBASE_IOS_API_KEY`, `FIREBASE_IOS_APP_ID`, `FIREBASE_IOS_BUNDLE_ID`
- `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_PROJECT_ID`, `FIREBASE_STORAGE_BUCKET`
- `APP_URL`, `SUPPORT_EMAIL`, `GMAIL_REDIRECT_URI`

**Required fix:** regenerate `apps/mobile/.env.example` from the union of `dotenv.get(...)` and `dotenv.maybeGet(...)` reads in `apps/mobile/lib`. Annotate which are required vs optional.

---

## H10 — `apps/mobile/.env.production` points API at `https://api.havenkeep.io` while the marketing site Layout.astro hardcodes `https://havenkeep.com` and the partners.astro `PUBLIC_PARTNER_DASHBOARD_URL` defaults to relative `/signup`

Three files, three different production-domain assumptions:
- [apps/mobile/.env.production:3](apps/mobile/.env.production): `API_BASE_URL=https://api.havenkeep.io`
- [apps/mobile/.env.production:25](apps/mobile/.env.production): `APP_URL=https://havenkeep.com`
- [apps/marketing/src/layouts/Layout.astro:58-63](apps/marketing/src/layouts/Layout.astro): hardcoded `https://havenkeep.com`
- [partners.astro:11-13](apps/marketing/src/pages/partners.astro): `PUBLIC_PARTNER_DASHBOARD_URL` defaults to `''` so signup link becomes `/signup` (relative — only works if the dashboard is hosted under the marketing origin or behind a same-origin reverse proxy).
- API `.env.example:18-19`: `APP_BASE_URL=http://localhost:3000` / `FRONTEND_URL=http://localhost:3000` (these would be `https://havenkeep.com` and either `https://app.havenkeep.com` or `https://partner.havenkeep.com` in production — undocumented).

The "what is the production domain stack?" question has no definitive answer in the repo. CLAUDE.md Part 2 says **staging** uses:
- Marketing: `https://staging.havenkeep.app`
- API: `https://api.staging.havenkeep.app`
- Partner dashboard: `https://partner.staging.havenkeep.app` (singular)

Production isn't documented. The mobile prod-env hardcodes `havenkeep.io` and `havenkeep.com` — implying the production domain is `havenkeep.io` for the API. Marketing Layout hardcodes `havenkeep.com`. Possibly the intent is `havenkeep.com` for marketing, `havenkeep.io` for API/app — or possibly `havenkeep.com` everywhere with `api.havenkeep.com` and `partners.havenkeep.com` subdomains. **The repo does not commit to one.**

**Required fix (severity H):** pick the production domain stack now and apply it across `apps/mobile/.env.production` + Layout.astro + partners.astro + the api `.env.example`. The audit-runs sweep should not be the place to discover that production routing is undecided.

---

# MEDIUM findings

## M1 — `/support` page is orphan: no inbound links from anywhere on the site

[apps/marketing/src/pages/support.astro](apps/marketing/src/pages/support.astro) exists at `/support`, but `grep -rEn 'href="/support'` across the whole `apps/marketing/src` returns nothing. It's not in Footer.astro, not in Navigation.astro, not in the FAQ page's CTAs.

The page is also not in `Layout.astro`'s `KNOWN_OG_SLUGS`, so its social-card image falls back to `/og-image.png`. Not in `build-og-image.cjs` PAGES list either, so no per-page OG card exists.

A user only lands on `/support` if they type the URL or follow an external email signature link. This is dead code. Either:
1. Add a Support link to the Footer (alongside Contact / Careers / Blog), regenerate its OG card, AND add the `support` slug to `Layout.astro`'s `KNOWN_OG_SLUGS`.
2. Delete the page and rely on Contact + FAQ + the in-app help (whatever that is).

**Required fix (severity M):** pick (1) or (2). Rule 3 says ship a link or kill the page.

---

## M2 — `Stats.astro` claims $16B+ "per industry reporting" — no citation, no source link

[components/Stats.astro:29-31](apps/marketing/src/components/Stats.astro):
> "$16B+ — estimated annual U.S. consumer loss to unused warranties, per industry reporting."

V1 hadn't dug into this. The "$16B" figure is also referenced in:
- [Hero.astro:14](apps/marketing/src/components/Hero.astro): "Americans lose $16B in unused warranties every year"
- [pricing.astro:18](apps/marketing/src/pages/pricing.astro), [Pricing.astro:14](apps/marketing/src/components/Pricing.astro): "average household wastes $340/year"
- [about.astro:38, 54](apps/marketing/src/pages/about.astro): "Americans lose over $16 billion each year on forgotten warranties alone"
- [blog/cost-of-lost-warranties.astro:48, 252](apps/marketing/src/pages/blog/cost-of-lost-warranties.astro): "$16 billion every year in warranty value they already paid for"
- [blog/warranty-claims-guide.astro:24, 37](apps/marketing/src/pages/blog/warranty-claims-guide.astro): "Americans throw away $16 billion in unused warranties every year" + "$340 per year"
- The OG-image build script ([scripts/build-og-image.cjs:86](apps/marketing/scripts/build-og-image.cjs)): "Help homeowners stop losing $16B/yr"

Nine separate places use the figure. Stats.astro is the only one that even hand-waves "per industry reporting" — every other use treats it as a fact. The figure is from Nick Maggiulli's blog or similar consumer-reporting blogs that themselves rarely cite a primary source. The **FTC's 2018 Magnuson-Moss enforcement report** mentions roughly $40B in unfiled warranty claims, not $16B. The numerical consistency across nine surfaces is strength, but the source attribution is weakness.

**Required fix (severity M):** either find a citable primary source (FTC consumer protection bureau, Consumer Reports research, BIA/Kelsey market data) and link it from Stats.astro + Hero.astro + about.astro + the blog, OR soften the framing across all nine surfaces ("estimated $16B," not "Americans lose $16B"). A regulator pulling a thread on the unsourced stat is a "deceptive endorsement" pretext.

The $340/year figure is similarly unsourced. Same fix.

---

## M3 — Roadmap page promises "Insurance Integration" + "Warranty Marketplace" + "AI Purchase Recommendations" + "Blockchain Verification" + "AR Item Scanning" — no design doc, no code, no track record of shipping these

[apps/marketing/src/pages/roadmap.astro:6-43](apps/marketing/src/pages/roadmap.astro). Two issues:

1. **The "Recently Completed" section** (lines 45-50) lists "Dark Mode (January 2026)", "Barcode Scanner Improvements (December 2025)", "PDF Export (November 2025)", "Smart Reminders (October 2025)". Today is **2026-05-10** (per the system context). Dark mode shipped 4 months ago, smart reminders 7 months ago — these are stale. No "April 2026" item.

2. **The future quarters** include features like "Blockchain Verification (Q4 2026: Immutable proof of purchase using blockchain technology)", "Insurance Integration (Q1 2026: Direct integration with major insurance providers for claims)", "AR Item Scanning (Q4 2026)". None of these have a design doc, an issue tracker entry, or a single line of code in the repo. CLAUDE.md Part 3 says "production is months away" — the existing roadmap promises features for Q1 2026 that are now overdue, and Q4 2026 features that have zero implementation.

The page also has a "Join Beta Program" CTA at line 149 — there is no beta program documented anywhere in the repo (no enrollment endpoint, no test-flight invite link, no email-list capture for beta signups).

**Required fix (severity M):**
1. Update "Recently Completed" with what actually shipped post-January 2026 (per CLAUDE.md, the audit-remediation arc and Stripe integration). Remove items > 6 months old.
2. Soften Q1/Q2/Q3/Q4 2026 to "Under exploration" labels until there's a design doc. Replace specific features with broad themes ("Improve receipt OCR accuracy"; "Investigate insurance-claim partnerships").
3. Either (a) wire up the beta program (capture email → backend `beta_signups` table → confirmation email) or (b) delete the "Join Beta Program" CTA. The current state makes a public commitment with no fulfilment.
4. "Blockchain Verification" should be quietly retired. Listing it implies HavenKeep is exploring crypto, which conflicts with the privacy-first positioning.

---

## M4 — Careers page lists 4 specific job postings with mailto links to `careers@havenkeep.com` — pre-launch, this attracts a noise channel and creates an applicant-data retention obligation

[apps/marketing/src/pages/careers.astro:6-35](apps/marketing/src/pages/careers.astro):
- Senior Full-Stack Engineer (mentions React Native — see C6)
- Product Designer
- Customer Success Manager
- Mobile Engineer (iOS)

Each role's "Apply Now" button is a `mailto:careers@havenkeep.com?subject=Application for ...`. The page also says "We read every application" (line 199) — pre-launch, this is a public hiring promise the founder may not be able to honor.

CLAUDE.md Part 3 says production is months away. There's no documented hiring runway, no team page, no engineering culture doc. Listing 4 specific roles signals "we're a 20-person company hiring" when the repo's commit history shows one author (`pacomedomagni@gmail.com`).

**Privacy implication:** Once an applicant emails `careers@havenkeep.com`, that's PII the founder must retain in line with the Privacy Policy's retention rules. There is no documented applicant-data retention process.

**Required fix (severity M):** either (a) close the page until a hiring round actually opens (replace the 4 roles with "We're not hiring right now — drop us a note if you'd like to be the first to know"), or (b) keep the page but remove the specific role descriptions (they're misleading) and add a one-liner about applicant-data retention ("We retain applications for 12 months under our privacy policy; email careers@havenkeep.com to request deletion").

---

## M5 — Verify-email-change page leaks server error message verbatim — 400 response body shown to user, info-disclosure risk (V1 M2 reaffirmed; severity unchanged)

V1 documented this. Concrete code path at [verify-email-change.astro:108-124](apps/marketing/src/pages/verify-email-change.astro):
```ts
serverMessage = body?.error?.message ?? body?.message;
…
showError(serverMessage ?? 'The verification link is invalid or has expired.');
```

Re-reviewing: the script handles 409, 429, 5xx with fixed strings — but the 400 path falls through to `serverMessage`. The API today returns generic "invalid or expired" but a future change could surface "user 'foo@bar.com' has email change cooldown" or similar. **Required fix:** drop the `serverMessage ?? …` for 400; map every status code to a fixed marketing-side string.

---

## M6 — `Hero.astro` Trust Signals row says "AES-256 encrypted" + "iOS & Android apps" + "Quick setup" — the third claim is honest but the first is the AES-256 framing inconsistency (M-NEW; sub-finding of H6)

Already covered in H6. Listing here as a separate medium because Hero is the **first thing a visitor reads**. The "AES-256 encrypted" trust badge is a one-liner that matches the privacy/about pages but conflicts with the security/features pages saying "AES-256-GCM" specifically. A security-conscious visitor sees three different framings on three different pages.

**Required fix:** unify under H6's recommended phrasing.

---

## M7 — Pricing FAQ #4 "When the App Store and Google Play offer Premium intro pricing or trials, you'll see them in the upgrade flow inside the app" — this implicitly promises a free trial may exist; no code path mentions intro pricing

[pricing.astro:284](apps/marketing/src/pages/pricing.astro):
> "When the App Store and Google Play offer Premium intro pricing or trials, you'll see them in the upgrade flow inside the app."

There's no `app_store_intro_offer` config or RevenueCat integration that uses Apple's intro-pricing API. The FAQ implies "intro pricing might be offered when we want it to" — but that requires explicit configuration in App Store Connect / Play Console + matching server-side handling. CLAUDE.md doesn't mention either.

**Required fix (severity M):** soften to "We don't currently offer a paid trial. When App Store / Play Store run their own promotional pricing on subscription apps, those will show in the upgrade flow." Or just delete the FAQ entry until intro pricing is actually configured.

---

## M8 — Partner page guarantees a 24-month Premium grant on the Platinum tier; `defaultPremiumMonths` validator caps at 12 (CRITICAL DRIFT — fixing severity)

[partners.astro:50-56](apps/marketing/src/pages/partners.astro): Platinum perks include "**2-year Premium gift**".
[partners.service.ts](apps/api/src/services/partners.service.ts):549: `const premiumMonths = data.premiumMonths || partner.default_premium_months || 6;`
[validators/partners.validator.ts:36, 58](apps/api/src/validators/partners.validator.ts): both `defaultPremiumMonths` and `premiumMonths` use `Joi.number().integer().min(1).max(12)`.

A Platinum partner attempting to set their `default_premium_months = 24` (or call the gift API with `premiumMonths: 24`) will get a 400 validation error. The marketing page's "2-year Premium gift" promise is **physically impossible** given the current API contract. Same problem applies to Premium tier's "1-year Premium gift" claim — that's exactly 12, which is the max, so it's at the edge but fine. Basic at 6 months is the default fallback, also fine.

**The 24-month claim is the only broken one — but the fix is critical because Platinum is the highest-revenue tier (per CLAUDE.md, $249/gift, 20% commission).** Bumping severity to consider critical.

**Required fix (severity M, leaning C — see also: this could land in C9):** raise the Joi `max(12)` to `max(24)` in both `updatePartnerSchema` AND `createGiftSchema`. Update `default_premium_months` per-tier (e.g. Basic=6, Premium=12, Platinum=24) when partners are created or upgraded. Otherwise rewrite the marketing copy to promise only "1-year Premium gift" on Platinum (matching the validator).

---

## M9 — Caddy edge config does NOT pin a TLS minimum version; relies on Caddy's defaults (TLS 1.2+)

[caddy/havenkeep.caddyfile](caddy/havenkeep.caddyfile) does not include `tls { protocols tls1.3 tls1.3 }` or `min_version`. Caddy 2.x defaults to TLS 1.2 minimum and TLS 1.3 enabled. So:
- A client supporting only TLS 1.2 (rare today) WILL connect.
- This contradicts the **Security page's "TLS 1.3"** claim, which would be falsifiable by an `nmap --script ssl-enum-ciphers` against the staging endpoint.

**Required fix (severity M):** add to each site block:
```
tls {
  protocols tls1.2 tls1.3
}
```
OR explicitly drop the TLS-1.3 claim from security.astro / faq.astro / features.astro / about.astro and pivot to "TLS 1.2+" everywhere (matching the privacy policy).

---

## M10 — The marketing CSP allows `connect-src 'self' https://api.havenkeep.kouakoudomagni.com` — locks the marketing site to staging API; production deploy requires Caddy edit

[caddy/havenkeep.caddyfile:122](caddy/havenkeep.caddyfile):
> `connect-src 'self' https://api.havenkeep.kouakoudomagni.com`

Production rollout requires editing this to `https://api.havenkeep.com` (or `https://api.havenkeep.io`, see H10). If production goes live and ops forgets the Caddyfile edit, the CSP will block fetches from production marketing → production API → contact form, newsletter, verify-email-change all silently break.

**Required fix (severity M):** parameterize the API origin via env-substitution in the Caddyfile (Caddy supports `{$ENV_VAR}` syntax). Set `API_ORIGIN` per environment.

---

# LOWER findings (M-cont., L)

## M11 — Carrier domain ambiguity: `apps/mobile/.env.production` uses `https://havenkeep.io` for the API while `APP_URL` uses `https://havenkeep.com` (also covered in H10; severity downgraded for the mobile-side specific case)

Already in H10. Listing here for completeness.

---

## M12 — `roadmap.astro` "Suggest a Feature" + "Submit Feature Request" both target `mailto:feedback@havenkeep.com`

[roadmap.astro:66, 145](apps/marketing/src/pages/roadmap.astro). Two CTAs, same email. Privacy policy lists `privacy@`, `support@`, `legal@`, `careers@`, `sales@`, `hello@`, `partners@` (implicit). `feedback@` is not on the privacy contact list.

If a user emails feedback and wants to know how it's processed (retention, sharing), no answer is documented. **Required fix:** either (a) consolidate to `support@` (which is documented), or (b) add `feedback@` to the privacy policy's "Contact" section + applicant-data-style retention note. Pick (a) — fewer mailing lists to monitor.

---

## L1 — `legal/privacy.astro` "Last Updated: April 25, 2026" — today is 2026-05-10. Privacy policy was last touched 15 days ago. Reasonable. No fix.

[legal/privacy.astro:13](apps/marketing/src/pages/legal/privacy.astro). Recent enough.

## L2 — `legal/terms.astro` "Last Updated: April 25, 2026" — same. No fix.

## L3 — `cookies.astro` "Last updated: February 2026" — 3 months stale, AND the page itself is fictitious (C1). Fix as part of C1 rewrite.

## L4 — `Hero.astro` `<a href="https://apps.apple.com/app/havenkeep">` — "havenkeep" path slug is unverified. This is the iOS App Store app's path; I cannot validate from inside the repo whether the slug is registered. If unregistered, this 404s and harms conversion. Pre-TestFlight, this is fine. **Recommend verifying after first TestFlight build is uploaded.**

## L5 — `partners.astro` signup link defaults to `'/signup'` (relative) when `PUBLIC_PARTNER_DASHBOARD_URL` is unset. If marketing is at `havenkeep.com` and the partner dashboard is at `partner.havenkeep.com`, the relative link will hit `havenkeep.com/signup` — a 404 on the marketing site. Already documented in H10's domain-stack discussion.

## L6 — `Hero.astro` mobile CTA "60-second setup" was removed (V1 verified clean) — now reads "Quick to get started" (line 83). Honest. No fix.

## L7 — `Testimonials.astro` correctly labels scenarios as "Illustrative examples — not actual customers" (V1 verified clean) — line 35. Good. No fix.

## L8 — Footer's "Powered by flokou" external link has `rel="noopener noreferrer"` (V1 L1 still verified). No fix.

---

# Cross-doc drift summary table

| Claim | Source 1 | Source 2 | Disagreement |
|---|---|---|---|
| Account-deletion grace period | privacy:108 (7d) | delete-account:24 (7d) | Code says 30d (V1 C1) — UNFIXED in v1's surfaced files |
| TLS version | privacy:97 (1.2+) | security:38 (1.3) | V1 H1 — UNFIXED |
| Encryption-at-rest framing | 6 different pages (this audit H6) | code (only OAuth + MFA AES-256-GCM) | NEW — this audit |
| Sub-processor list | privacy:80-87 | code (OpenAI) | NEW — this audit C2 |
| Premium grant duration | partners.astro Platinum=24mo | validator max=12 | NEW — this audit M8 |
| Backup retention | privacy:101 ("30-day"), security:153 | no script in repo | V1 H3 — UNFIXED |
| Bug bounty | security:220 | no policy in repo | V1 H4 — UNFIXED |
| TLS pinning | privacy:97 + build-og-image.cjs:86 ("TLS pinning") | mobile code (no SecurityContext) | V1 C2 + this audit's broadened scope |
| Cookies / Marketing cookies | cookies.astro full page | privacy.astro:90 ("no advertising SDKs") | NEW — this audit C1 |
| Free tier item count | pricing:59 (5) | constants.dart (5) + api config (5) | V1 verified clean |
| Premium price | pricing:117 ($24/yr) + Pricing component + terms.astro | RevenueCat (not in repo) | V1 verified clean |
| Partner tier prices | partners.astro (99/149/249) | partners.service.ts (99/149/249) | V1 verified clean |
| Canonical URL | Layout.astro hardcoded `havenkeep.com` | astro.config.mjs `site: havenkeep.com` | V1 H5 — UNFIXED |
| Production domain stack | mobile prod env (`havenkeep.io` API) | marketing Layout (`havenkeep.com`) | NEW — this audit H10 |
| Blog publish dates | content/blog/*.json | pages/blog/*.astro hardcoded `const date` | NEW — this audit H1 |
| Service availability | terms.astro:142 "99.9% uptime target" | no SLA tracking documented | NEW — could be "honestly aspirational" but not provable |

---

# Adversarial scenarios

## O1 — Regulator pulls "show me the SSE on receipts" thread

V1 H2 — privacy claims "receipts and photos encrypted in object storage." Code grep shows zero `x-amz-server-side-encryption` headers on any `putObject`. The bucket-level default would need to be enabled on the MinIO server itself, which isn't documented. **Worst case:** California AG sub-pena, MinIO config audit, finding "Default encryption: NOT ENABLED" → false-statement enforcement.

## O2 — User files a CCPA "right to know" request

User emails `privacy@havenkeep.com` saying "tell me every category of personal information you've collected about me, and every third party you've shared it with, going back 12 months."

The privacy policy's sub-processor list is incomplete (no OpenAI). The CCPA-mandated 45-day response (extendable to 90) requires fully accurate disclosure. If the regulator-required answer omits OpenAI, that's a §1798.130 violation.

## O3 — User files a CCPA "do not sell / do not share" request

Code grep: no `do_not_sell` flag in users table. No `/api/v1/users/me/privacy-preferences` endpoint. The privacy policy says "California residents have the same rights under CCPA and we do not discriminate against users who exercise them" but provides no mechanism. CCPA §1798.135 requires a "Do Not Sell or Share My Personal Information" link on the homepage **for businesses subject to the law**. Currently no such link.

**Severity context:** if HavenKeep's gross revenue passes $25M (CCPA threshold), this is enforcement-grade. Pre-launch with no users, it's not yet active. But the policy has already promised compliance — once the first paying customer exists in California, the absence of the mechanism is provable.

## O4 — Bug-bounty researcher finds a critical and is told "there's no payout"

V1 H4 — security page promises "We offer rewards for responsible disclosure." If a researcher reports a critical SQL injection and HavenKeep declines payment, the researcher publishes the disclosure with screenshots of the broken promise. Reputational damage > the cost of paying the bounty.

## O5 — Hardcoded canonical leak (V1 H5 + this audit H5)

Googlebot indexes staging. Or, the staging social-card preview shows `og:image` pointing at production URLs that don't exist yet — every staging Slack share is a broken preview.

## O6 — Twitter / GitHub social handles are squatted (this audit C7)

A user clicks the GitHub icon expecting open-source code; lands on a typo-squatted page with malicious links. Pre-launch reputational risk is high here because the site already brands itself as "open-source friendly" via the licenses page.

---

# Verified-clean (no fix needed)

All carry forward from V1's verified-clean section:
- Caddy CSP directives (default-src, script-src, style-src, img-src, font-src, connect-src, frame-ancestors, base-uri, form-action) are appropriate for the marketing site. `strict-dynamic` on script-src, no `'unsafe-inline'` / `'unsafe-eval'` on script-src, `frame-ancestors 'none'`. HSTS `max-age=31536000; includeSubDomains; preload`. Referrer-Policy `strict-origin-when-cross-origin`. Permissions-Policy denies camera/mic/geolocation + opts out of FLoC. Verified in [caddy/havenkeep.caddyfile:113-127](caddy/havenkeep.caddyfile).
- The Caddyfile dashboard block explicitly allows `https://js.stripe.com` on script-src, `https://api.stripe.com` on connect-src, `https://js.stripe.com https://hooks.stripe.com` on frame-src — correct minimum for Stripe Elements.
- The Caddyfile explicitly forces `Content-Type: application/json` on `/.well-known/apple-app-site-association` and `/.well-known/assetlinks.json` (lines 102-111). Universal-link breakage prevention in place.
- AASA file is valid JSON, scoped only to `/gift/*` and `/referral/*`, includes `webcredentials` for Apple Sign-In keychain sharing, lists `N3RF2GHS99.app.havenkeep.mobile`. (V1 verified.)
- assetlinks.json has both `delegate_permission/common.handle_all_urls` AND `delegate_permission/common.get_login_creds`. Upload-key fingerprint is wired; Play App Signing placeholder is `REPLACE_WITH_PLAY_APP_SIGNING_SHA256` (correct pre-launch).
- robots.txt disallows `/legal/delete-account` (Ch10-W102) — prevents the deletion form from appearing in search.
- OG image coverage: 16 KNOWN_OG_SLUGS in Layout.astro, 16 PNGs in `/public/og/` (verified by `ls | wc -l`). `verify-email-change` and `support` correctly fall back to the site-wide `/og-image.png` (verified-clean for `verify-email-change`, see M1 for `support` orphan).
- Astro `output: 'static'` + `@astrojs/sitemap` + `@astrojs/rss` + content-collection-driven blog. RSS pulls from same collection as listing page. (V1 verified clean.)
- `@fontsource/inter` self-hosted (no Google Fonts request); Layout imports 5 weights at compile time.
- prefers-reduced-motion media query in Layout.astro:103-110 reduces animation/transition durations to 0.01ms for users opting out. Good a11y baseline.
- Honeypot fields (contact form `name="website"`, newsletter form `name="newsletter-website"`) are aria-hidden, tabindex=-1, autocomplete=off, positioned `left:-10000px`. Newsletter form even silently fakes success on tripped honeypot (good — bots can't tell).
- Contact form uses `credentials: 'omit'`, 15s `AbortController` timeout, same-origin POST to `${PUBLIC_API_URL}/api/v1/contact`. (V1 verified.)
- Footer + Hero + Pricing + CTA + every external `target="_blank"` link has `rel="noopener noreferrer"`. (V1 verified.)
- `apps/marketing/package.json` deps are minimal: astro, tailwind, fontsource/inter, sitemap, rss. No analytics, no Sentry, no marketing SDKs. Verified.
- Mobile router's `/gift/<code>` and `/referral/<code>` Universal-Link paths match AASA scope. (V1 verified.)
- Privacy policy's "we do not have any advertising SDKs" claim is verified by grep across `apps/mobile/pubspec.yaml` (V1 L2 verified-clean).
- bcrypt cost factor 12 used everywhere except test fixtures. (V1 verified.)
- Newsletter API has `newsletterRateLimiter` (5/hour/IP) per blog.astro comment.

---

# Findings count

- **8 Critical** — fictitious cookies page (C1), missing OpenAI from sub-processor list (C2), telemetry opt-out promised but no UI (C3), data export promised but no UI (C4), TLS pinning false claim (C5 — re-stated and broadened from V1 C2), licenses page lists React Native + Expo (C6), unverified social handles (C7), missing marketing `.env.example` + env-conditional gate (C8).
- **10 High** — blog publish-date drift across 5 posts (H1), pricing-hero "$2/mo" framing (H2), pricing-FAQ proration claim (H3 — V1 M4 bumped), pricing-FAQ + faq.astro 30d-after-cancel claim (H4 — V1 M3 bumped), canonical URL hardcode broadened scope (H5 — V1 H5), encryption framing inconsistency across 6 pages (H6 — V1 H1 broadened), missing marketing `.env.example` plus env-gate (H7), API `.env.example` drift from actual reads (H8), mobile `.env.example` missing 11 keys (H9 — V1 C4 widened), production domain stack ambiguity (H10).
- **12 Medium** — orphan support page (M1), $16B citation gap (M2), stale roadmap (M3), open job postings (M4), 400-error message echo (M5 — V1 M2), Hero AES framing (M6), pricing-FAQ free-trial implication (M7), partner Platinum 24-mo grant unattainable (M8), Caddy missing min TLS pin (M9), Caddy CSP staging-pinned API origin (M10), mobile prod-env domain (M11 — H10 sub-finding), feedback@ undocumented in privacy (M12).
- **8 Low** — privacy/terms last-updated dates fine (L1, L2), cookies last-updated stale (L3 — fix-as-part-of-C1), App Store path slug unverified (L4), partners signup-href fallback (L5), Hero "60s setup" already removed (L6 — verified clean), Testimonials labelled illustrative (L7 — verified clean), Footer flokou link (L8 — verified clean from V1).

**Total new findings:** ~38 (this audit), plus all V1 findings still apply.

**Adversarial:** 6 scenarios flagged where the regulator/researcher/user can punch through the documented promise and find code that contradicts it.

**The user's deep-audit ask is fulfilled.** The most actionable items in priority order:
1. Rewrite `cookies.astro` (C1) — regulatory-fastest fix.
2. Add OpenAI to sub-processor list (C2) — same regulatory bucket.
3. Fix the 24-month Platinum grant (M8 → escalate to C9 if you don't want to rewrite marketing) — partner-facing contract.
4. Replace React Native + Expo on licenses + careers (C6) — applicant-side credibility.
5. Fix the production-domain stack ambiguity (H10) — prevents a class of "production deploy day" surprises.
6. Regenerate all three `.env.example` files (C8 + H8 + H9) — onboarding-blocker.
7. Audit and either claim or release the GitHub + Twitter handles (C7).
8. Decide telemetry opt-out (C3) and data export (C4) — ship the screen, OR delete the privacy claim.
