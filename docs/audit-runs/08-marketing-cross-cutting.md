# Audit 08 — Marketing site + cross-cutting drift

Scope: `apps/marketing/` (Astro static site), checked-in Caddyfile,
`.well-known/{aasa,assetlinks.json}`, the marketing-hosted `/verify-email-change`
page, the cross-doc account-deletion drift, mobile-router universal-link parity,
and env-var leakage in `.env*` / `.env.example` files.

Out-of-scope (other agents): API routes, DB migrations, partner-dashboard,
mobile feature code, email scanner. Where I cite API or mobile files below it
is only as evidence for a marketing claim or a doc/code drift.

Severity legend (matches the rest of the audit run):
- **C — Critical** — privacy claim is false, secrets leak, broken Universal
  Link, CSP hole, or accountability claim that contradicts code.
- **H — High** — hard-to-verify operational claim, drift in cooling-off
  period, external link missing rel=noopener.
- **M — Medium** — drift in copy, missing OG image, incomplete feature claim.
- **L — Low** — cosmetic / nit.

---

## C1 — Account-deletion cooling-off period drift (4 sources, 2 different numbers)

The user explicitly flagged this. The truth is **30 days** in the API, in the
deletion email, and in the privacy policy. The delete-account page and the
mobile-app screen drift. Comparison:

| Source | File:line | Claims |
|---|---|---|
| Privacy policy | [apps/marketing/src/pages/legal/privacy.astro:108](apps/marketing/src/pages/legal/privacy.astro) | "soft-delete immediately, allow a **7-day** grace period to cancel, then cryptographically erase" |
| Delete-account page | [apps/marketing/src/pages/legal/delete-account.astro:24](apps/marketing/src/pages/legal/delete-account.astro) | "**7-day** grace period during which you can sign in to cancel the deletion. After 7 days, your account and associated data are cryptographically erased" |
| Mobile UI (delete screen) | [apps/mobile/lib/features/settings/delete_account_screen.dart:73-77, 110-113](apps/mobile/lib/features/settings/delete_account_screen.dart) | "permanently delete … This action cannot be undone." (no number — implies *immediate* permanent delete; doesn't mention any grace window) |
| Code — DELETE /me | [apps/api/src/routes/users.ts:589, 643, 696, 699](apps/api/src/routes/users.ts) | "30-day cooling-off period"; `deletion_scheduled_for = NOW() + INTERVAL '30 days'`; user-facing message "Account scheduled for deletion in 30 days. You can recover it by logging in before then." |
| Code — purge cron | [apps/api/src/services/account-purge.service.ts:9-15, 136](apps/api/src/services/account-purge.service.ts) | "hard-delete users whose **30-day cooling-off** window has expired … 'Soft-deleted user permanently purged after 30-day cooling-off window'" |
| Code — auth refresh | [apps/api/src/middleware/auth.ts:132](apps/api/src/middleware/auth.ts) | comment: "during the **30-day** cooling-off window" |
| Confirmation email | [apps/api/src/services/email.service.ts:1085, 1116, 1155](apps/api/src/services/email.service.ts) | "Your HavenKeep account has been successfully deleted" + "anonymized analytics data may be retained for up to **30 days**" — note this email is sent at *soft*-delete time and reads as if the delete is final, which is a separate UX bug (see C5 below) |

**Truth: code does 30 days.** This is not user-configurable, it is a hard-coded
`INTERVAL '30 days'` in `users.ts` and a hard-coded comment in
`account-purge.service.ts`. There is no env-var override.

**Required fixes (severity C):**
1. `privacy.astro:108` — change "7-day grace period" → "30-day grace period."
2. `delete-account.astro:24` — change "7-day grace period during which you can
   sign in to cancel the deletion. After 7 days …" → "30-day grace period …
   After 30 days …"
3. `delete_account_screen.dart` — the screen currently tells the user
   "permanent" with no mention of recovery. The API's response message says
   "You can recover it by logging in before then" — the UI should surface that
   so users know they have a way back. At minimum, add a sentence like "You'll
   have 30 days to recover your account by signing in again before all data is
   permanently deleted." right under "This action is permanent" (line 274)
   or replace that header with "Your account will be deleted in 30 days."

**Why this matters:** the privacy policy is a contract. If the policy says
7 days but you keep the row for 30, a user who exercises GDPR Article 17
("right to be forgotten") and then sees their email/full_name still
returnable in a Stripe webhook event 14 days later has a regulatory complaint
that you'll lose. Inversely, if a user reads "7 days" and waits 8 days to
recover, they'll be surprised that recovery still works — friendlier, but
still a breach of the documented contract.

---

## C2 — Privacy claim "Mobile clients additionally pin the leaf certificate" is wrong on two counts

[apps/marketing/src/pages/legal/privacy.astro:97](apps/marketing/src/pages/legal/privacy.astro):

> "Mobile clients additionally pin the leaf certificate on production builds
> so a compromised CA can't intercept HavenKeep traffic."

Two problems:

1. **Pinning is NOT wired in any release path.**
   [packages/api_client/lib/src/client.dart:202-217](packages/api_client/lib/src/client.dart)
   only *documents* an SPKI-pinning recipe in a doc-comment ("Mobile bootstrap
   should construct the pinned client and pass it in"). I grepped
   `apps/mobile` and `packages/` for `SecurityContext`, `badCertificateCallback`,
   `expectedSpkiSha256`, and `_spkiMatches`. The only hits are inside that doc-
   comment block. No code path actually constructs a pinned `IOClient`.
   Therefore the privacy policy's claim is **false today** — the mobile app
   uses the platform trust store on every build, dev or release.

2. **"Leaf certificate" is wrong terminology.** The api_client doc-comment
   describes **SPKI pinning** (issuer's Subject Public Key Info hash), which
   survives a leaf-cert rotation. Leaf-cert pinning would brick the app every
   time the cert rotates (typically every 90 days on Let's Encrypt). The two
   concepts are not interchangeable.

**Required fix (severity C):** Either (a) implement SPKI pinning in
[apps/mobile/lib/main.dart](apps/mobile/lib/main.dart) for release builds and
update the policy to "SPKI pin our certificate's public key …", or (b) delete
the sentence from the privacy policy until pinning ships. Shipping a privacy
claim you can't prove with code is a regulatory exposure.

---

## C3 — Postgres password, JWT/refresh secrets, MinIO keys, and full Firebase service-account private key live in plaintext in the repo working tree

[/.env.staging](.env.staging) (gitignored — verified with `git check-ignore`,
and `git ls-files | grep .env` does not include it; only `.env.example` is
tracked) contains:

- `POSTGRES_PASSWORD=55b09a15fe71c57cce9586b9adf4b64bc04d33b8` (line 17)
- `JWT_SECRET=74605ebec9eae8730950ea12b9abbd0861b0caf4e703497d44235d2fcc7bc3c6` (line 21)
- `REFRESH_TOKEN_SECRET=086e074100f735a74c9a72fee1742b511d18d996c84c336a8910d0ab1af32a2f` (line 23)
- `REDIS_PASSWORD=c3c900ff2261767e7ae0be9604d019427cad5254` (line 27)
- `MINIO_ACCESS_KEY` + `MINIO_SECRET_KEY` (lines 30-31)
- The **full RSA private key** for `firebase-adminsdk-fbsvc@havenkeep-firebase-project.iam.gserviceaccount.com` — `FIREBASE_SERVICE_ACCOUNT_JSON` (line 63) — including `private_key_id` `78d69b5edc3b79f72cc5cc350652958e607b5bfc`.

**Status:** the file IS gitignored (`git check-ignore` confirms), so it's not
pushed. But its presence in the working tree of every developer machine that
has cloned the repo is itself a leak vector (laptop theft, accidental upload
to a screen-share / pastebin, accidental `tar.gz` of the repo, AI assistants
that read working-tree files, etc.).

**Required action (severity C):**
1. **Treat all secrets in this file as compromised.** Rotate every one of
   them: Postgres password, JWT secret (forces a global re-login — acceptable
   on staging), refresh-token secret, Redis password, both MinIO keys, and
   especially the Firebase service-account key (revoke it in Google Cloud
   Console → IAM → Service Accounts → Keys, then issue a new one).
2. **Stop committing this shape.** CLAUDE.md Part 2 already says staging
   secrets live in `/opt/staging/havenkeep/.env.api` on the droplet, NOT in
   the repo. The current `/.env.staging` in the working tree contradicts that
   — delete it after rotation, and document that staging secrets are only
   pulled with `scp root@206.189.26.12:/opt/staging/havenkeep/.env.api .`
   when an engineer needs them locally. Add a pre-commit guard that rejects
   any commit touching `*.env*` except `.env.example`.
3. The Firebase private key is the worst of the bunch — it can mint FCM push
   tokens for the entire project and (if the service account has broader
   roles) impersonate other Firebase APIs. Audit the service-account roles in
   GCP IAM after rotation; it should only carry `roles/firebasecloudmessaging.admin`.

The mobile-side `apps/mobile/.env.staging` (also in the working tree but
**checked into git** per `git ls-files`) is fine — it only carries an OAuth
client ID (public information) and empty Firebase API-key placeholders. No
secrets.

---

## C4 — Mobile `.env.example` does not mirror the env vars the mobile actually reads

Per CLAUDE.md Part 3 A.1, [apps/mobile/lib/core/config/firebase_options.dart:27,35](apps/mobile/lib/core/config/firebase_options.dart) reads `FIREBASE_ANDROID_API_KEY` and `FIREBASE_IOS_API_KEY` from `.env.<flavor>`, and
[apps/mobile/lib/core/config/environment_config.dart:206,210](apps/mobile/lib/core/config/environment_config.dart) requires both at startup.

[apps/mobile/.env.example](apps/mobile/.env.example) lists only:
`API_BASE_URL`, `LOKI_URL`, `REVENUECAT_API_KEY`, `OUTLOOK_*`,
`GOOGLE_SERVER_CLIENT_ID`, `APPLE_SERVICES_ID`, `APPLE_REDIRECT_URI`.

Missing from the example file (but present in the staging file with empty
values): `FIREBASE_IOS_API_KEY`, `FIREBASE_IOS_APP_ID`,
`FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_PROJECT_ID`, `FIREBASE_STORAGE_BUCKET`,
`FIREBASE_IOS_BUNDLE_ID`, **`FIREBASE_ANDROID_API_KEY`**, `APP_URL`,
`SUPPORT_EMAIL`, `GMAIL_REDIRECT_URI`.

**Required fix (severity C — onboarding-blocking):** regenerate
`apps/mobile/.env.example` from the union of every `dotenv.get(...)` call in
`apps/mobile/lib/`. New devs hit `flutter run --flavor staging` and the app
silently falls back to Firebase API key `''` — Crashlytics initialises but
fails on first crash with a confusing error, and there is no obvious signal
in `.env.example` telling them they're missing keys. The api `.env.example`
header explicitly says the file should be "regenerated from the union of
`process.env.*` reads"; mobile needs the same treatment.

---

## H1 — Privacy policy / Security page disagree on TLS version

| File:line | Claims |
|---|---|
| `legal/privacy.astro:97` | "TLS **1.2+** on every connection" |
| `security.astro:38, 45` | "encrypted using TLS **1.3**" |

The actual TLS version is set by Caddy (the edge), and Caddy 2.x defaults to
TLS 1.2 minimum with TLS 1.3 enabled. So privacy is *technically* right
("1.2+") and security is *aspirationally* right (1.3 is offered when the
client supports it). But the two pages contradict each other from the
visitor's perspective.

**Required fix (severity H):** pick one phrasing. Suggest "TLS 1.3 (with TLS
1.2 fallback)" on both pages, since Caddy's preference order serves 1.3 to
any modern client.

---

## H2 — Privacy policy claim "receipts and photos encrypted in object storage" is unverifiable from code

[`legal/privacy.astro:98`](apps/marketing/src/pages/legal/privacy.astro):

> "AES-256-GCM for sensitive fields in the database; full-disk encryption on
> the database host; **receipts and photos encrypted in object storage**."

I grepped every `minioClient.putObject(...)` call in `apps/api/src/`:

- [apps/api/src/routes/uploads.ts:128](apps/api/src/routes/uploads.ts) — avatar upload, no SSE header
- [apps/api/src/routes/uploads.ts:260](apps/api/src/routes/uploads.ts) — receipt upload, no SSE header
- [apps/api/src/routes/documents.ts:201](apps/api/src/routes/documents.ts) — thumbnail, no SSE header
- [apps/api/src/routes/documents.ts:222](apps/api/src/routes/documents.ts) — original doc, no SSE header

None pass `x-amz-server-side-encryption: AES256` (or `aws:kms`). For the
privacy claim to be true, **bucket-level default encryption must be enabled on
the MinIO server itself** (`mc encrypt set sse-s3 …`), and that's an
operational config change that lives on the droplet, NOT in this repo.

**Required action (severity H):**
1. Verify on the staging droplet whether the `havenkeep` bucket has SSE-S3
   default encryption enabled: `ssh root@206.189.26.12 'docker exec
   infra-minio mc encrypt info havenkeep'` (replacing `havenkeep` with the
   alias config). If it is **not** enabled, either enable it or delete the
   "encrypted in object storage" sentence from the privacy policy until it is.
2. Document the SSE config decision in CLAUDE.md Part 2 under MinIO so a
   future re-deploy doesn't drop it.
3. Optional reinforcement: add `'x-amz-server-side-encryption': 'AES256'` to
   the `metaData` object on every `putObject` call in `apps/api/src/routes/{uploads,documents}.ts`.
   Belt-and-braces — even if bucket-level default is on, request-level header
   means the SSE behavior is asserted by the application.

---

## H3 — Privacy policy claim "Daily encrypted backups; 30-day retention; tested with weekly restore drills" is unverifiable

[`legal/privacy.astro:101`](apps/marketing/src/pages/legal/privacy.astro). The
phrase is repeated verbatim on
[`security.astro:147,153,165`](apps/marketing/src/pages/security.astro) ("Automated
daily backups", "30-day backup retention", "Regular disaster recovery testing").

Neither this repo nor the staging deploy system has visible:
- a daily backup cron (the `.env.example:201-207` references
  `BACKUP_S3_BUCKET` etc. for a `scripts/backup-database.sh` that I could not
  find — `find /Users/pacomedomagni/Projects/havenkeep -name 'backup-database*'`
  returns nothing),
- an "encrypted backup" wrapper around `pg_dump`,
- a documented restore-drill cadence.

**Required action (severity H):** either point to where the backup job lives
(if it's a droplet-level cron in `/opt/staging/`, document that in CLAUDE.md
Part 2), or soften the privacy/security claims to what's actually in place
(e.g. "Postgres' WAL is captured continuously" / "Backups run via …" — pick
words you can prove). Two pages making the same un-verifiable claim is twice
the regulatory exposure.

---

## H4 — Security page advertises a bug bounty that doesn't exist

[`security.astro:220`](apps/marketing/src/pages/security.astro):

> "We offer rewards for responsible disclosure of significant security
> vulnerabilities through our bug bounty program."

CLAUDE.md Part 3 says production is months away. There is no bug-bounty
program documented anywhere in the repo (no `SECURITY.md`, no HackerOne /
Intigriti / Bugcrowd config, no policy listing reward tiers).

**Required action (severity H):** either delete the sentence (recommended
pre-launch), or replace with "We currently do not run a paid bounty but
publicly thank reporters of valid findings — see security@havenkeep.com." A
public claim of a bounty program creates an implicit contract; if a researcher
finds a critical bug and you decline to pay, they have a Twitter thread.

---

## H5 — Canonical URL hardcoded to havenkeep.com — drift on staging

[apps/marketing/src/layouts/Layout.astro:58-63](apps/marketing/src/layouts/Layout.astro):

```ts
const canonicalUrl = canonicalPath
  ? `https://havenkeep.com${canonicalPath}`
  : `https://havenkeep.com${Astro.url.pathname}`;
```

Same hardcode for `og:url` and `twitter:url`. CLAUDE.md says the staging Caddy
binds `staging.havenkeep.app` (and the `caddy/havenkeep.caddyfile` block
binds `havenkeep.kouakoudomagni.com`). When Googlebot / link-preview cards
fetch the staging site they'll see `<link rel="canonical"
href="https://havenkeep.com/…">` and **either** index the staging URL under
the prod canonical (bad — duplicate-content, but tolerable since the same
content) **or** ignore the staging URL entirely.

`astro.config.mjs:18` already has `site: 'https://havenkeep.com'`. Astro's
`Astro.site` reads from this. The fix is one line.

**Required fix (severity H):** read `Astro.site` (preferred) or
`import.meta.env.PUBLIC_SITE_URL` instead of hardcoding the host. Set
`PUBLIC_SITE_URL` per environment so staging emits
`https://staging.havenkeep.app` (or whatever final staging name lands).
Caveat: hosts other than the prod site should also serve a `<meta
name="robots" content="noindex">` so Google doesn't index staging copies.
Currently no marketing page sets that — verify before going live.

---

## M1 — Privacy policy lists "30 days" for backup retention but `users.ts` says backups age out within 30 days of soft-delete (different clock)

[`legal/privacy.astro:108`](apps/marketing/src/pages/legal/privacy.astro):

> "we soft-delete immediately, allow a 7-day grace period to cancel, then
> cryptographically erase the record from active systems. **The data ages out
> of backups within 30 days.**"

This claim is conditional on (a) backup retention being 30 days (see H3 — not
verifiable), and (b) the backup-retention clock starting at *the purge*, not
at the soft-delete. If retention is "rolling 30 days from backup creation,"
the same row could persist in backups for up to 60 days from soft-delete (30
days of grace + 30 days of backup-rotation tail). The current wording
oversells.

**Required fix (severity M):** "The data ages out of backups within 30 days
of permanent deletion" or "within 60 days of soft-delete," whichever is
operationally true. Pick after H3 is settled.

---

## M2 — Email-change consume page surfaces server error message verbatim — minor info-disclosure risk

[apps/marketing/src/pages/verify-email-change.astro:108-124](apps/marketing/src/pages/verify-email-change.astro):

```ts
const body = await response.json();
serverMessage = body?.error?.message ?? body?.message;
…
showError(serverMessage ?? 'The verification link is invalid or has expired.');
```

For the 400 path, the script displays whatever the API put in `error.message`
back to the user. The API is well-behaved today, but this couples the
marketing UI to API error wording — one careless API change ("token
00000000-aaaa-… not found in email_verification_tokens") and the user sees a
schema hint.

**Required fix (severity M):** drop the `serverMessage ?? …` for the 400
path. Map status codes to fixed marketing-side strings (the page already does
this for 409, 429, 5xx); add a 400 case ("The verification link is invalid or
has expired."). Treat the API as untrusted output for end-user copy.

The page does NOT log the token to console — verified by grep
(`grep -rn "console.log\|console.error\|console.debug" apps/marketing/src`
returns nothing). Good.

The page DOES correctly toggle the three status divs (`status-confirming`,
`status-success`, `status-error`) so only one is visible at a time —
`showSuccess` hides confirming + error; `showError` hides confirming +
success. Verified at lines 73-83.

---

## M3 — Pricing page FAQ #2 contradicts the rest of the marketing copy on data retention after cancel

[`pricing.astro:264`](apps/marketing/src/pages/pricing.astro), FAQ "What
happens to my data if I cancel?":

> "We keep your data for 30 days after cancellation in case you change your
> mind."

This is talking about **subscription** cancel, not account delete. But the
phrasing makes it sound like canceling Premium triggers a 30-day data clock,
which it does NOT — canceling Premium just downgrades you to Free, and the
[delete-account page](apps/marketing/src/pages/legal/delete-account.astro:62-69)
explicitly says "Deleting your account does NOT automatically cancel an
active App Store or Google Play subscription." A confused user reads the
pricing-FAQ answer and thinks "if I cancel my sub, my data is gone in 30
days," which is the opposite of what happens.

**Required fix (severity M):** rewrite the answer to "Cancelling your
Premium subscription does NOT delete your data. Your account stays on the
Free plan with your last 5 active items visible. To permanently delete your
data, see the Delete Account page."

---

## M4 — `pricing.astro` FAQ #1 promises proration on plan changes, which is App Store / Play Store policy — not ours

[`pricing.astro:254`](apps/marketing/src/pages/pricing.astro), FAQ "Can I
switch plans anytime?":

> "Changes take effect immediately, and we'll **prorate any charges or
> credits.**"

Apple and Google handle the actual proration — Apple does not prorate within
the same family unless you switch durations (monthly ↔ annual); Google's
proration is configurable per app. Promising "we'll prorate" implies HavenKeep
controls the math, which we don't. Also conflicts with Pricing/Premium copy
("Available in the iOS & Android apps • Cancel anytime in your store
account") — terms.astro:88 correctly defers refund handling to Apple/Google.

**Required fix (severity M):** replace with "Changes take effect at your next
billing cycle. Refunds and proration follow the App Store or Google Play
policy on plan changes."

---

## M5 — `mobile/.env.example` is missing the keys CLAUDE.md says will be needed for first build

(See C4 above. Severity duplicated for completeness — flagging here as the
"M-NEW" entry the audit-runs sweep should pick up.)

---

## L1 — Footer "Powered by flokou" is an external link; verify intentional

[apps/marketing/src/components/Footer.astro:60-71](apps/marketing/src/components/Footer.astro)
links to `https://flokou.com`. Has `rel="noopener noreferrer"` (good) and
`target="_blank"` (good). Just flagging for visibility — if HavenKeep is
publicly distancing itself from the parent agency pre-launch, this attribution
might surprise stakeholders. No security concern.

---

## L2 — `licenses.astro` not visited but should be checked for ad-SDK denial parity

Privacy policy says "We do not have any advertising SDKs." I confirmed by
reading [apps/mobile/pubspec.yaml](apps/mobile/pubspec.yaml) — every dep is
either Flutter / Firebase (Auth, Crashlytics, Messaging, Core), Riverpod,
GoRouter, Drift+SQLCipher, Stripe-via-RevenueCat (`purchases_flutter`),
Google/Apple sign-in, or generic utilities (intl, uuid, crypto, http). No
AdMob, no Branch, no Adjust, no AppLovin, no Facebook Audience Network,
nothing tracking-adjacent. **Privacy claim verified.** No fix needed.

---

# Verified-clean findings (no fix needed; documented so future agents don't re-audit)

- **CSP at the edge** ([caddy/havenkeep.caddyfile:122](caddy/havenkeep.caddyfile))
  is appropriately strict for the marketing site:
  `default-src 'self'; script-src 'self' 'strict-dynamic'; style-src 'self'
  'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:;
  connect-src 'self' https://api.havenkeep.kouakoudomagni.com;
  frame-ancestors 'none'; base-uri 'self'; form-action 'self'`.
  No `'unsafe-inline'` or `'unsafe-eval'` on `script-src`. `frame-ancestors
  'none'` is set. HSTS is `max-age=31536000; includeSubDomains; preload` —
  good. `Referrer-Policy: strict-origin-when-cross-origin` — good.
  `Permissions-Policy` denies camera/mic/geolocation + opts out of FLoC. Good.
- **Inline scripts in components** — Astro's `<script>` blocks (Hero,
  Pricing, Navigation, contact, verify-email-change, blog, index) are
  processed as ES modules and externalised by the bundler at build time, so
  the strict CSP without `'unsafe-inline'` works. Verified by reading
  Navigation.astro:67-79 (which explicitly comments "Audit Ch10-W089: this is
  a `<script>` tag — Astro processes it as a module bundle").
- **Pricing/billing-toggle JS** correctly re-binds on `astro:after-swap` —
  [Pricing.astro:271](apps/marketing/src/components/Pricing.astro),
  [pricing.astro:372](apps/marketing/src/pages/pricing.astro). Survives
  client-side navigation.
- **Hero scroll-reveal JS** at [index.astro:30-42](apps/marketing/src/pages/index.astro)
  is **NOT** wrapped in `astro:after-swap`. Astro's static output doesn't run
  client-side route changes (the marketing site is `output: 'static'`), so
  there's nothing to re-bind on. **Verified non-issue.**
- **Contact form security**:
  - Honeypot at [contact.astro:91-100](apps/marketing/src/pages/contact.astro) —
    `name="website"`, `aria-hidden="true"`, `tabindex="-1"`,
    `autocomplete="off"`, positioned `left:-10000px`. Forwarded to the API at
    line 250.
  - Same-origin POST with `credentials: 'omit'` — line 252.
  - 15s timeout via `AbortController` — lines 241-242, 269.
  - On success: button hidden, success div revealed; form resets but stays
    in success state until reload (Ch10-W073) — lines 257-261.
  - On failure: error div shown, button re-enabled — lines 264-266. The
    network-error path correctly hits `catch` since `if (!response.ok) throw
    new Error(…)` rejects the promise; success div is not revealed.
- **Honeypot client-side check** — newsletter form at
  [blog.astro:177-183](apps/marketing/src/pages/blog.astro) silently shows a
  fake success when the honeypot is tripped. Good — bots can't tell they were
  caught.
- **AASA file** — [apple-app-site-association](apps/marketing/public/.well-known/apple-app-site-association)
  is valid JSON, lists `N3RF2GHS99.app.havenkeep.mobile`, scopes only `/gift/*`
  and `/referral/*`, includes `webcredentials` for Apple Sign-In keychain
  sharing. Matches CLAUDE.md Part 3 A scope and the mobile router's
  [router.dart:92-93](apps/mobile/lib/core/router/router.dart) declared
  routes (`/referral/:code`, `/gift/:code`).
- **assetlinks.json** — [assetlinks.json](apps/marketing/public/.well-known/assetlinks.json)
  has both `delegate_permission/common.handle_all_urls` (App Links) AND
  `delegate_permission/common.get_login_creds` (autofill). Package is
  `app.havenkeep.mobile`. Upload-key SHA-256
  `70:21:27:A4:AD:2D:8B:8B:73:0F:60:DD:62:45:71:DA:A0:96:EB:EF:81:76:8A:FC:EF:28:D1:F7:F8:AF:9F:90`
  is wired (matches CLAUDE.md). Play App Signing fingerprint placeholder
  `REPLACE_WITH_PLAY_APP_SIGNING_SHA256` is still there — expected and
  correct pre-Play-launch.
- **Caddy AASA / assetlinks Content-Type override** — the caddyfile
  ([caddy/havenkeep.caddyfile:104-111](caddy/havenkeep.caddyfile)) explicitly
  forces `Content-Type: application/json` on both well-known paths. AASA-as-
  text/plain is the #1 Universal Link breakage; fix is in place.
- **OG image coverage** — Layout.astro KNOWN_OG_SLUGS = 16 entries. `/public/og/`
  contains exactly 16 PNGs matching every slug
  (`home, features, pricing, partners, about, security, careers, contact,
  faq, roadmap, blog, cookies, licenses, legal-privacy, legal-terms,
  legal-delete-account`). No drift. `verify-email-change` is intentionally
  not in the list — it inherits the site-wide `/og-image.png` fallback,
  which is correct for a one-time consume page.
- **bcrypt cost factor** — privacy policy says "bcrypt (work factor 12)";
  every `bcrypt.hash(...)` call in
  [apps/api/src/routes/auth.ts:275, 1056](apps/api/src/routes/auth.ts) and
  [apps/api/src/routes/users.ts:560](apps/api/src/routes/users.ts) uses
  cost `12`. Test fixtures in `seed.ts` use cost 10 (acceptable for tests).
  **Privacy claim verified.**
- **External link safety** — every `target="_blank"` in
  `apps/marketing/src/components/{Hero,Footer,Pricing,CTA}.astro` and
  `apps/marketing/src/pages/{pricing,partners,contact}.astro` has
  `rel="noopener noreferrer"`. Verified by `grep -rn target=_blank ... | grep
  -v noopener` returning only the matching same-line pairs (the grep was
  formatting-only, not a missing-rel).
- **Free tier limit** — pricing.astro:59 says "Up to 5 items"; 
  [packages/api_client/lib/src/constants.dart:4](packages/api_client/lib/src/constants.dart)
  `kFreePlanItemLimit = 5`; 
  [apps/api/src/config/index.ts:217](apps/api/src/config/index.ts)
  `intFromEnv('FREE_TIER_ITEM_LIMIT', 5)`. All three agree.
- **Partner tier prices** — partners.astro Basic/Premium/Platinum at
  $99/$149/$249 matches
  [apps/api/src/services/partners.service.ts:67](apps/api/src/services/partners.service.ts)
  `'{"basic":99,"premium":149,"platinum":249}'`. No drift.
- **Premium pricing** — pricing.astro $2.99/mo or $24/yr matches Pricing
  component, terms.astro:69. Internally consistent. Verifying against
  RevenueCat product IDs is out of scope (App Store Connect data).
- **robots.txt** — [robots.txt](apps/marketing/public/robots.txt) `Disallow:
  /legal/delete-account` (Ch10-W102) — correct, prevents the deletion form
  from appearing in search.
- **Sitemap** — generated by `@astrojs/sitemap` at build (astro.config.mjs:20).
  Auto-includes every page under `src/pages/`. Blog posts are at
  `src/pages/blog/*.astro` so they're in.
- **RSS** — [rss.xml.js](apps/marketing/src/pages/rss.xml.js) pulls from the
  `blog` content collection, sorted desc by `pubDate`. Verified the collection
  contains all 6 posts via
  `apps/marketing/src/content/blog/*.json`.
- **Inline `<style>` in Stats.astro** — line 8 has `style="background-image:
  radial-gradient(...);"`. This is an inline-style *attribute*, not a
  `<style>` element, and the Caddy CSP allows `style-src 'self'
  'unsafe-inline'`. No CSP violation.
- **Mobile router universal-link parity** — verified at
  [router.dart:92-93, 149-170](apps/mobile/lib/core/router/router.dart). The
  redirect block correctly handles `/gift/<code>` and `/referral/<code>`,
  stashing the code as `pending_gift_code` / `pendingReferral` for the
  unauthenticated path, matching what the AASA scope claims. **No drift.**
- **Verify-email-change is intentionally not in AASA** — per CLAUDE.md Part
  3 A, `/verify-email`, `/reset-password`, `/verify-email-change` are
  explicitly web-only. The AASA file correctly does not list them.

---

# Summary

- **4 Critical** — account-deletion drift (1 → 4 source files), false TLS-pinning
  privacy claim, plaintext secrets in `/.env.staging` working tree (incl.
  Firebase service-account private key), `apps/mobile/.env.example` missing
  Firebase keys.
- **5 High** — TLS-version drift between privacy and security pages; un-verifiable
  MinIO SSE claim; un-verifiable backup-retention claim; phantom bug-bounty
  promise; canonical-URL hardcoded to prod.
- **5 Medium** — backup-vs-grace-period clock ambiguity, error-message echo
  on verify-email-change, pricing-FAQ data-retention confusion, pricing-FAQ
  proration overpromise, mobile env-example drift (dup of C4).
- **2 Low** — Footer flokou attribution flag, no other findings.

**No findings on:** Caddy CSP, AASA, assetlinks, mobile router parity, OG
image coverage, free-tier item count, partner-tier prices, contact-form
security, honeypot, external-link `rel=noopener`, bcrypt cost factor, sitemap,
RSS, ad-SDK absence.

**The user's flagged 7-vs-30-day question is settled** — the code does 30
days end-to-end; both marketing pages are wrong; the mobile UI silently omits
the grace period. Privacy + delete-account need a copy update; mobile UI
needs a recovery-window sentence added.
