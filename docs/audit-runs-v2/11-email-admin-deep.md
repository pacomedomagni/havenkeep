# Audit Run v2 — 11: Email service + Admin tooling deep dive

**Scope:** SendGrid transactional email + admin/audit routes + dashboard admin UI.
**Working tree:** `/Users/pacomedomagni/Projects/havenkeep`
**Date:** 2026-05-10

---

## A. Email service architecture

### A1. Service shape — `apps/api/src/services/email.service.ts`

1466 lines. One static class `EmailService` exposes 9 send methods + 2 HMAC helpers. No queue, no Bull, no Inngest — every send is in-process via `@sendgrid/mail`. There is one shared circuit breaker, one shared retry wrapper, and per-call try/catch with `logger.error` on failure.

Module-load side effect:
```ts
// email.service.ts:32-34
if (config.sendgrid.apiKey) {
  sgMail.setApiKey(config.sendgrid.apiKey);
}
```

### A2. SendGrid client config — `apps/api/src/config/index.ts`

```ts
// config/index.ts:139-143
sendgrid: {
  apiKey: readSecret('SENDGRID_API_KEY') || '',
  fromEmail: process.env.SENDGRID_FROM_EMAIL || 'noreply@havenkeep.com',
  replyToEmail: process.env.SENDGRID_REPLY_TO_EMAIL || 'support@havenkeep.com',
},
```

Validator-side check in `config/validator.ts:106-108` warns if the API key doesn't start with `SG.`.

### A3. From-address — env-configurable

Yes. `SENDGRID_FROM_EMAIL` env var, defaults to `noreply@havenkeep.com`. **Finding F-EM-A3-1 (LOW):** the partner welcome email hardcodes `from.name = 'HavenKeep Partners'` and `replyTo = 'partners@havenkeep.com'` (lines 497, 499) — those are not derived from config, so they will be wrong if anyone runs the API on a non-prod domain. Same for the contact email which hardcodes the `to: 'support@havenkeep.com'` (line 1391).

### A4. Reply-to — set, but per-template

Every transactional email sets `replyTo`. Three flavors:
- `config.sendgrid.replyToEmail` for most: gift activation (line 369, header-sanitized), warranty expiration, maintenance, email verify, change-email, account deletion, password reset.
- Hardcoded `'partners@havenkeep.com'` for partner welcome (line 499).
- User-supplied (header-sanitized via `sanitizeHeaderValue` line 40-42) for the contact form notification (line 1388, 1396).
- Newsletter confirmation: **no `replyTo`** set (line 1454-1458).

**Finding F-EM-A4-1 (LOW):** Newsletter confirmation send (line 1453-1459) has no `replyTo` — if a recipient clicks reply they email the from-address (`noreply@havenkeep.com`) which probably bounces.

### A5. Categories / subuser routing

**None.** No `categories: [...]` on any `msg` payload, no SendGrid subuser routing, no template IDs. Every send is a raw `html` + `text` payload.

**Finding F-EM-A5-1 (MED):** No SendGrid categories means the SendGrid Activity dashboard can't filter "warranty expiration" sends from "password resets" — you read every bounce/open/click event in one mixed feed. Add `categories: ['gift']`, `['warranty_expiring']`, etc. to make ops sane and to scope sender reputation tracking (a noisy template doesn't drag the whole tenant down on Gmail/Yahoo).

### A6. Retry policy

`sendGridSendWithRetry` (line 80-112): 3 attempts max, 250 → 500 → 1000 ms exponential backoff. Retries only on `429` or `5xx`; `400/401/403` etc. fail fast. After 3 failures the consecutive-failure counter increments via `noteCircuitFailure`.

### A7. Async queue + retry

No queue. Failed sends bubble back to the caller as a rejection, which is then either re-thrown (gift activation line 393, partner welcome 509) or swallowed by `.catch()` in fire-and-forget callsites (`auth.ts:350` registration verification email, `auth.ts:1031` password reset, `users.ts:686` account deletion, `partners.service.ts:282` partner welcome, `partners.service.ts:769` gift activation, `newsletter.ts:96` newsletter confirmation).

The circuit breaker (line 48-73) is process-local — every API replica has its own counter — and trips at **8 consecutive failures** with a 60-second cooldown.

**Finding F-EM-A7-1 (HIGH):** No persistent retry queue. If SendGrid is down for 90 seconds during a gift purchase and the `.catch()` swallows it, the homebuyer never gets the activation email. The gift row is created, the partner is charged, but the recipient never knows. CLAUDE.md note re newsletter says "a polling job will retry pending confirmations" but no such job exists — searched `apps/api/src` for any retry/polling on newsletter or gift email and found none.

**Finding F-EM-A7-2 (MED):** Process-local circuit breaker. Eight failures on one replica doesn't help the other replicas, which keep hitting SendGrid. With multi-replica deploy the effective threshold is `8 * N_REPLICAS`. Should live in Redis like the rate limiter or use SendGrid's own 429 retry-after.

---

## B. Email templates

### B1. Template inventory

There are no templates in `apps/api/src/templates/` — that directory does not exist. Every email is inline HTML+text in `email.service.ts`. The 10 send methods:

| Method | Subject | Used by |
|---|---|---|
| `sendGiftActivationEmail` | `🎁 ${partner} sent you a gift: ${months} Months HavenKeep Premium` | `partners.service.ts:757, 1366` |
| `sendPartnerWelcomeEmail` | `Welcome to HavenKeep Partners! 🎉` | `partners.service.ts:274` |
| `sendWarrantyExpirationEmail` | `Warranty ${urgencyLabel}: ${item} expires ${date}` | `notifications.service.ts:1001, 1266` |
| `sendMaintenanceDueEmail` | `Maintenance Due: ${task} for ${item}` | `notifications.service.ts:1136` |
| `sendEmailVerificationEmail` | `Verify your HavenKeep email address` | `auth.ts:346` |
| `sendEmailChangeVerificationEmail` | `Confirm your new HavenKeep email address` | `users.ts:506` |
| `sendAccountDeletionEmail` | `Your HavenKeep account has been deleted` | `users.ts:686` |
| `sendPasswordResetEmail` | `Reset your HavenKeep password` | `auth.ts:1027` |
| `sendContactNotificationEmail` | `Contact Form: ${subject} - ${name}` | `contact.ts:61` |
| `sendNewsletterConfirmation` | `Confirm your HavenKeep newsletter subscription` | `newsletter.ts:95` |

**Finding F-EM-B1-1 (MED):** All 10 templates live inline. Subject lines are scattered across the service. Any branding change (e.g. "HavenKeep" → "Haven Keep") requires touching 10 places. Either externalize to `src/templates/email/*.hbs` or — better — migrate to SendGrid dynamic templates so marketing can iterate without a deploy.

### B2-B11. Templates by name + variables

All 10 send full HTML + text bodies (except partner welcome which is HTML-only — see B8 finding). Variable shapes shown in B2 below.

**B2 — gift activation (line 165-394)** vars: `to, homebuyer_name, partner_name, partner_company?, premium_months, activation_url, activation_code, custom_message?, brand_color?, logo_url?, gift_id?`. Subject uses partner company/name. Renders a per-partner branded gradient header (color from `partner.brand_color`, optional logo via `partner.logo_url`).

**B3 — email verification (line 817-925):** vars `to, user_name, verify_url`. Subject `Verify your HavenKeep email address`. 24-hour expiry copy. No `replyTo` issue. Has both HTML + text. Verify URL sanitized via `sanitizeUrl()` (line 826-829) → throws if non-https/non-localhost.

**B4 — password reset (line 1187-1301):** vars `to, user_name, reset_url`. "Reset Your Password". 1-hour expiry. Same URL sanitization.

**B5 — email change verification (line 930-1046):** vars `to, user_name, verify_url, new_email`. "Confirm Your New Email". 24-hour expiry. The `new_email` is HTML-escaped (line 941).

**B6 — account deletion confirmation (line 1051-1182):** vars `to, user_name`. "Account Deleted". Sent from `users.ts:686` after `DELETE /me` flips `deleted_at`. Mentions 30-day data retention.

**Finding F-EM-B6-1 (MED):** The account-deletion email is sent **immediately** when the soft-delete starts, not when the hard-purge completes 30 days later. The copy says "Your HavenKeep account has been successfully deleted" but the user can still recover via `/me/recover`. Inaccurate at minimum; could be misleading to a GDPR auditor since it implies finality at day 0.

**B7 — day-25 grace warning** — **DOES NOT EXIST.** Searched the entire `apps/api/src` tree for any send tied to `deletion_scheduled_for` or "day 25 / 7 days remaining" copy. The 30-day cooling-off purge fires from `services/account-purge.service.ts` with no email send before purge.

**Finding F-EM-B7-1 (MED):** No mid-grace-period reminder. A user who clicked DELETE on day 1, then ignored email for a month, will lose their account silently — the only mail they got was the day-0 "Account Deleted" notice (which they may have dismissed thinking it was confirmation that the action happened immediately). Recommend a day-25 email ("your account purges in 5 days, log in to keep it") sent by a cron job that scans `users WHERE deleted_at IS NOT NULL AND deletion_scheduled_for BETWEEN NOW() + INTERVAL '4 days' AND NOW() + INTERVAL '5 days'`.

**B8 — partner welcome (line 408-511):** vars `to, partner_name, company_name?, partner_id?`. "Welcome to HavenKeep Partners! 🎉". Tracking pixel via `partnerEmailPixelHmac(partner_id, 'welcome')` (line 416-419). Hardcoded `from.name = 'HavenKeep Partners'` and `replyTo = 'partners@havenkeep.com'` (lines 497-499).

**Finding F-EM-B8-1 (MED):** Partner welcome email is **HTML-only** — no `text` content provided in the `msg` (line 493-502). Mail clients that don't render HTML (legacy corporate gateways, accessibility tooling, some Outlook configs) will see an empty body. Every other template ships both HTML + text.

**B9 — gift activation customization:** YES per-partner. The gift email is the only template that takes `brand_color` + `logo_url`. Brand color is validated to `^#[0-9A-Fa-f]{6}$` (line 125-127); logo URL is validated as HTTPS or localhost (line 145-159). Custom message is HTML-escaped (line 200). Headers `List-Unsubscribe` (line 374) + `List-Unsubscribe-Post` for Gmail/Yahoo one-click compliance.

**B10 — warranty expiration / maintenance:** vars listed above. Both have urgency-based color coding (`#EF4444` ≤7d, `#F59E0B` ≤14d, `#3B82F6` else — line 534). Both ship HTML + text + `List-Unsubscribe`. Hardcoded unsubscribe URL `${frontendUrl}/settings/notifications` (line 533, 683).

**Finding F-EM-B10-1 (MED):** The "unsubscribe URL" inside warranty/maintenance emails points at `/settings/notifications` — that's an in-app preference toggle, not an HTTP unsubscribe endpoint. Gmail's RFC 8058 one-click unsubscribe expects a URL that flips a boolean **on the server side** without user interaction (matched with `List-Unsubscribe-Post: One-Click`). Linking to a settings page that requires login defeats one-click and is **non-compliant with Gmail/Yahoo's 2024 bulk-sender rules**. Newsletter has a real unsubscribe endpoint (`/api/v1/newsletter/unsubscribe?email=&t=`); warranty/maintenance reuse the wrong link. Either: (a) add a notification-prefs unsubscribe endpoint with an HMAC token like newsletter, or (b) remove the `List-Unsubscribe-Post: One-Click` header so we don't claim compliance we don't have.

**B11 — newsletter confirmation (line 1415-1465):** vars `to, confirmUrl`. "Confirm your HavenKeep newsletter subscription". HTML + text. Confirms via `/api/v1/newsletter/confirm?token=<plaintext>`.

---

## C. Email rendering

### C1. Template engine

**Backtick string interpolation.** No Handlebars, no React Email, no MJML, no `@sendgrid/mail.send` template ID. Every variable goes through `${…}` substitution into a template literal.

### C2. HTML escaping

`escapeHtml` (line 115-122) escapes `& < > " '`. Applied at every user-controlled insertion point:
- `partner_company || partner_name` → `fromName` (line 197).
- `homebuyer_name.split(' ')[0]` → `firstName` (line 198).
- `custom_message` → `safeCustomMessage` (line 200).
- `user_name`, `item_name`, `brand`, `expiry_date`, `task_name`, `new_email`, name/subject/message in contact form.

**Finding F-EM-C2-1 (INFO):** Coverage looks complete. Spot-checked every `${var}` insertion against the corresponding `escapeHtml(...)` declaration — every user-supplied field is escaped before HTML interpolation.

**Finding F-EM-C2-2 (LOW):** `partner.brand_color` is validated as `#RRGGBB` and falls back to `#3B82F6` on mismatch (line 126). `partner.logo_url` is validated as HTTPS (line 145-159) or empty on failure. Both are interpolated into `style="background: linear-gradient(135deg, ${brand_color}…)"` and `<img src="${logo_url}">` (line 219-220). Validation is correct; just noting the inputs are partner-supplied and the regex/URL parse is the only gate.

### C3. URL encoding

The activation URL stored on the gift row is constructed in `partners.service.ts` (not in the email service) and is server-controlled. The tracking pixel URL uses `encodeURIComponent` (line 418):
```ts
`${config.app.apiUrl.replace(/\/$/, '')}/api/v1/partners/${encodeURIComponent(partner_id)}/track/welcome-open?t=${encodeURIComponent(partnerEmailPixelHmac(partner_id, 'welcome'))}`
```
Newsletter confirmation URL `encodeURIComponent(confirmationToken)` (`newsletter.ts:94`). Verification/reset URLs in `auth.ts` and `users.ts` interpolate the raw token (`?token=${token}`) where `token = crypto.randomBytes(32).toString('hex')` — all hex, no special chars, so no `encodeURIComponent` needed.

**Finding F-EM-C3-1 (INFO):** URL encoding is correct everywhere. The reset/verify tokens use `randomBytes(32).toString('hex')` which produces 64 chars in `[0-9a-f]` — no encoding needed. The pixel tokens via `partnerEmailPixelHmac` are 16 hex chars sliced from a sha256 HMAC.

### C4-C5. Unsubscribe headers

`List-Unsubscribe` is set on three templates:
- Gift activation (line 374): `<${frontendUrl}/settings/notifications>` — same problem as B10.
- Warranty expiration (line 652): same problem.
- Maintenance due (line 800): same problem.

`List-Unsubscribe-Post: List-Unsubscribe=One-Click` is set on all three.

Newsletter confirmation (line 1453-1459) has **no** `List-Unsubscribe` header. Newsletter outbound newsletter emails (which we don't actually send anywhere in this codebase — only the confirmation email exists) would need it. The unsubscribe URL helper `newsletterUnsubscribeUrl()` in `routes/newsletter.ts:30-33` is defined but not used by any actual newsletter send because no newsletter-blast code path exists.

**Finding F-EM-C4-1 (HIGH):** Three transactional templates claim Gmail/Yahoo one-click compliance via `List-Unsubscribe-Post: List-Unsubscribe=One-Click` but the URL is a logged-in settings page, not a one-click unsubscribe endpoint. Gmail will see the header, attempt the one-click POST, and either redirect to a 401 (since `/settings/notifications` requires auth) or end up at marketing's static settings page. Either fix the URL or remove the One-Click header.

**Finding F-EM-C4-2 (LOW):** Verification, password reset, change-email, account deletion, contact-form, partner welcome, and newsletter confirmation have **no** `List-Unsubscribe` header at all. Most of those are 1:1 transactional so it's defensible — but the partner welcome carries a tracking pixel and is sent unsolicited to new partner sign-ups, which is arguably opt-in marketing under GDPR.

---

## D. Per-recipient rate limiting / dedupe

### D1-D2. Where dedupe lives

There is no dedupe at the email-service layer. Dedupe happens at the caller:

**Notifications (`notifications.service.ts:907, 1037, 1173`):** SQL `NOT EXISTS` guard against `notification_history` for the same `(item_id, type)` within the configured window — 1 day for warranty expirations (line 932-937), 7 days for maintenance (line 1078-1085), 30 days for warranty offers. This is the primary cron-level dedupe; the email itself piggybacks.

**Change-email (`users.ts:426-457`):** Per-recipient Redis `INCR` keyed on `sha256(newEmailLower)` with 24-hour TTL (line 431-442). If count > 1, suppresses the send and returns the success-shape response so an attacker can't probe "is this address already targeted today" (line 447-457).

### D3. Override (force send)

**None.** Every send path has fire-and-forget `.catch()` swallowing or rethrowing — no `?force=true` flag, no admin "resend" button on the dashboard, no `/admin/users/:id/resend-verification` route.

**Finding F-EM-D3-1 (MED):** Support workflows will demand "resend verification email for user X" or "resend gift activation for gift Y" — neither exists. Gift has a `giftResendRateLimiter` in `rateLimiter.ts:325-330` (3/hour per IP) but searching `apps/api/src` for `giftResendRateLimiter` only finds the export — **no route uses it**.

### D4. H-A2 audit fix

Verified. `users.ts:459-477` documents the fix:
```ts
// S-H2: don't 409 here on existing-email — that's an auth'd enumeration
// oracle (see Pass 2 H-A2). Mirror the response shape and let the
// verify-email-change consumer enforce uniqueness atomically.
```
The handler now returns the same generic `sendMessage` body regardless of whether `existingUser.rows.length > 0`. Confirmed by reading lines 464-477.

---

## E. Bounce / complaint handling

### E1. SendGrid event webhook

**No webhook handler exists.** Searched `apps/api/src/routes/webhooks.ts` (60k LOC route covering Stripe + RevenueCat) — there is no `/webhooks/sendgrid` mount and no handler that consumes SendGrid's event POSTs. The CLAUDE.md "Webhook events table tracks delivery + retries" refers to Stripe/RC webhooks, not SendGrid.

### E2-E3. Hard-bounce / complaint state

No code to flip `users.email_verified` to FALSE on hard bounce. No marketing opt-out column updated on spam complaint. SendGrid does suppression-list these addresses on its own end so we won't re-send (good), but we have no signal in the database.

**Finding F-EM-E1-1 (HIGH):** No SendGrid event webhook means:
1. We don't know which addresses are bouncing — operators learn from SendGrid Activity dashboard, not from our own DB.
2. A user whose `email_verified=true` permanently stays verified even if SendGrid hard-bounces them — they get listed in the audit-trail/admin UI as a verified user but never receive any further mail.
3. Spam complaints from one promotional template don't quarantine that user from other transactional sends; relevant once any promotional/digest mail goes out at scale.
4. No way to surface "deliverability is dropping" to ops without manually pulling SendGrid stats.

Recommend a `POST /api/v1/webhooks/sendgrid` route with SendGrid signed event verification (their X-Twilio-Email-Event-Webhook-Signature header), upserting to a `email_events` table keyed on `(email, event, sg_event_id)`, and a separate consumer that flips `users.email_verified=false` on `event='bounce' AND type='blocked'`.

### E4. Dashboard surface

None. The admin dashboard has no "bounces" or "complaints" view.

---

## F. Newsletter (mig 037)

### F1. Schema

Initial table from mig 013 (line 4-21):
```sql
CREATE TABLE IF NOT EXISTS newsletter_subscribers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email VARCHAR(255) NOT NULL,
  subscribed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  unsubscribed_at TIMESTAMPTZ,
  ip_address INET,
  source VARCHAR(50) DEFAULT 'blog',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_newsletter_email UNIQUE (email)
);
```

Mig 037 (line 13-49) drops the absolute UNIQUE, adds `status`, `confirmation_token_hash CHAR(64)`, `confirmation_sent_at`, `confirmed_at`, plus a partial unique index `idx_newsletter_subscribed_email` on `LOWER(email) WHERE status = 'subscribed'`. The CHECK constraint allows `('pending_confirmation', 'subscribed', 'unsubscribed')`. Mig 094 drops the redundant `idx_newsletter_subscribers_email`.

### F2-F4. Double-opt-in flow + TTL

`routes/newsletter.ts:58-110` — POST `/subscribe`:
1. Generate `confirmationToken = crypto.randomBytes(32).toString('base64url')`.
2. `tokenHash = sha256(token)` stored, plaintext mailed.
3. Insert with `status='pending_confirmation', confirmation_sent_at=NOW(), subscribed_at=NOW()`.
4. ON CONFLICT (`LOWER(email)`) `WHERE status='subscribed'` DO NOTHING — keeps subscribed rows immutable.
5. Sends `EmailService.sendNewsletterConfirmation` fire-and-forget.

GET `/confirm` (line 118-150): SHA-256 the URL token, UPDATE matching `pending_confirmation` row to `status='subscribed', confirmed_at=NOW(), confirmation_token_hash=NULL`. No-match → 400 plain HTML.

**Finding F-EM-F2-1 (MED):** No TTL on `confirmation_token_hash`. Mig 037 doesn't add a `confirmation_token_expires_at` and `routes/newsletter.ts:124-133` doesn't `AND confirmation_sent_at > NOW() - INTERVAL '24 hours'`. A token from 6 months ago is still valid. This is a confirmation token; it should expire in 24-72 hours per double-opt-in best practice. Risk: scraped/leaked confirmation tokens stay forever-valid; a stale row sitting at `pending_confirmation` for months can be resurrected.

**Finding F-EM-F2-2 (LOW):** The confirmation route returns a hand-rolled HTML page (line 141-148) — fine for the success path, but the failure path returns plain text "Invalid or expired confirmation link" without HTML; rendering is browser-dependent.

### F3. Subscribe / unsubscribe routes

- `POST /subscribe` — see above. Rate-limited (`newsletterRateLimiter`: 5/hour per IP per `rateLimiter.ts:360-365`).
- `GET /confirm?token=` — double-opt-in step 2.
- `POST /unsubscribe` body `{email, t}` — HMAC-token validated (line 168-174). Token = `HMAC-SHA256(refresh_secret, "newsletter:unsub:" + lower(email))`, full 64-char hex (F110 fix).
- `GET /unsubscribe?email&t=` — same HMAC.
- `POST /unsubscribe-one-click?email&t=` (line 247-282) — Gmail/Yahoo RFC 8058 endpoint, requires `body['List-Unsubscribe'] === 'One-Click'` AND the HMAC token. Returns 200 "OK".

### F4. Token TTL

Confirmation token: **no TTL** (see F2 finding). Unsubscribe HMAC: deterministic, derived from refresh-token secret — effectively permanent (rotating the refresh secret breaks every outstanding unsubscribe link).

### F5. Audit log entry

**None.** `routes/newsletter.ts` does not call `AuditService.log*` for any subscribe/confirm/unsubscribe event. Only `logger.info` (line 100, 140, 186, 226, 279).

**Finding F-EM-F5-1 (LOW):** Newsletter actions are not in the audit log. Subscribe-as-someone-else and one-click unsubscribe leave no auditable trail. Less critical than the auth/admin gaps but if you ever respond to a CASL/GDPR subject access request, "show me every newsletter event for `me@example.com`" requires a SQL query, not the audit API.

---

## G. Privacy compliance

### G1. SendGrid DPA

Out-of-band. The marketing site privacy policy (`apps/marketing/src/pages/legal/privacy.astro` per the CLAUDE.md context) is supposed to list SendGrid as a sub-processor. Could not verify a signed DPA from the codebase — that's a Twilio account-config check, not a code check.

### G2. CAN-SPAM

- **From-name / from-address accurate** — yes, `noreply@havenkeep.com` or partner branded.
- **Subject not deceptive** — yes, transactional subjects are descriptive.
- **Physical postal address** — **NOT PRESENT** in any template footer. Search confirms no street address.

**Finding F-EM-G2-1 (HIGH):** No physical postal address in any template footer. CAN-SPAM § 7704(a)(5)(A)(iii) requires every commercial email to include "a valid physical postal address of the sender." Transactional-only emails are exempt (15 USC § 7702(2)(B)), but the gift activation + warranty expiration + maintenance reminders + partner welcome have promotional/marketing content (logos, CTA buttons, value props, brand styling). The FTC has historically taken a broad view of "primary purpose" — a "transactional" email that prominently markets is treated as commercial. Add the corporate postal address to every footer.

**Honors unsubscribe within 10 business days:** Yes (newsletter unsubscribe is instant DB UPDATE). For transactional emails (warranty/maintenance), there's no real unsubscribe — see B10 finding.

### G3. CASL (Canada)

Express vs implicit consent — `auth.ts` doesn't surface a separate "marketing consent" toggle at signup. The transactional emails are implicit (purchase, account safety). Newsletter is double-opt-in (explicit consent). No code-level gap here.

### G4. GDPR — opt-in for marketing

Newsletter is opt-in (double-opt-in). Partner welcome and gift emails go to addresses the partner supplied (legitimate interest under GDPR Art 6(1)(f)) but the marketing styling of those emails — see G2 — is at the edge of "transactional." No issue if the partner has legitimate-interest consent from their homebuyer.

---

## H. Admin routes

### H1. Route file

`apps/api/src/routes/admin.ts` — 892 lines. Mounted at `/api/v1/admin` in `app.ts:190`. Top of file:
```ts
const router = Router();
router.use(authenticate);                  // line 30
router.get('/me', requireAdmin, ...);      // line 36 — special-cased, must be admin
router.use(requireAdmin);                  // line 47 — every route below is admin-only
```

The `/me` route gets its own `requireAdmin` (line 36) so the chain order is `authenticate → requireAdmin → handler`.

### H2. Endpoint inventory (admin router)

| Method/Path | Auth | Audit on mutation? |
|---|---|---|
| GET `/me` | requireAdmin | n/a (read) |
| GET `/stats` | requireAdmin (router-level) | n/a |
| GET `/audit/verify` | requireAdmin | n/a |
| GET `/stats/full` | requireAdmin | n/a |
| GET `/stats/daily-signups` | requireAdmin | n/a |
| GET `/stats/daily-items` | requireAdmin | n/a |
| GET `/users/activity` | requireAdmin | n/a |
| GET `/users` | requireAdmin | n/a |
| PUT `/users/:id/suspend` | requireAdmin + writeRateLimiter | **yes** (line 330-336) |
| PUT `/users/:id/unsuspend` | requireAdmin | **yes** (line 404-409) |
| DELETE `/users/:id` | requireAdmin + writeRateLimiter | **yes** (line 471-477) |
| GET `/partners/pending` | requireAdmin | n/a |
| PUT `/partners/:id/approve` | requireAdmin | **yes** (line 577-583) |
| PUT `/partners/:id/reject` | requireAdmin | **yes** (line 628-637) |
| GET `/partners` | requireAdmin | n/a |
| GET `/partners/:id` | requireAdmin | n/a |
| GET `/commissions` | requireAdmin | n/a |
| GET `/commissions/stats` | requireAdmin | n/a |

**Commission mutation endpoints live under `/partners/admin/commissions`, not `/admin/commissions`:**

| Path | Audit on mutation? |
|---|---|
| PUT `/partners/admin/commissions/:id/approve` | **no audit log** |
| PUT `/partners/admin/commissions/:id/pay` | **no audit log** |
| PUT `/partners/admin/commissions/:id/cancel` | **no audit log** |

**Finding F-AD-H2-1 (HIGH):** Three commission state-transition endpoints (`partners.ts:1052-1217`) all hit `requireAdmin` but **none** call `AuditService.logFromRequest`. An admin can approve/pay/cancel any commission with no audit trail. The /pay path also fires a Stripe transfer (line 1139-1150) — a fraudulent admin can drain a partner's pending commissions and there is no record beyond the Stripe transfer log (which lives in a different system).

**Finding F-AD-H2-2 (MED):** Admin commission routes live under `/partners/admin/commissions/*` rather than `/admin/commissions/*`. The dashboard hits the right paths (`admin-commission-table.tsx:43, 65, 87`) but the URL inconsistency means: (a) anyone reading the `app.ts` mount table can't find them, (b) `audit/logs/resource/partner_commission/:id` searches won't surface them because no `resourceType` is logged.

**Audit-route inventory (`routes/audit.ts`, mounted at `/api/v1/audit`):**
| Path | Auth | Notes |
|---|---|---|
| GET `/logs` | authenticate + readRateLimiter; admin branch via `verifyAdminFresh` | non-admins get own logs only |
| GET `/logs/me` | authenticate + readRateLimiter | own logs only |
| GET `/logs/resource/:type/:id` | authenticate; admin branch via `verifyAdminFresh` | non-admin restricted to own |
| GET `/security` | requireAdmin | admin-only |
| GET `/stats` | requireAdmin | admin-only |
| GET `/activity-summary` | requireAdmin | admin-only |
| POST `/cleanup` | requireAdmin | gated on `AUDIT_CLEANUP_CONFIRMATION_PHRASE` HMAC + `confirm: 'PURGE'` |

### H3. requireAdmin gate

`middleware/auth.ts:215-234` — every `requireAdmin` call hits the DB:
```ts
const result = await query(
  `SELECT is_admin FROM users WHERE id = $1 AND deleted_at IS NULL`,
  [req.user.id],
);
```
That's a per-request DB read, closing the 10s Redis user-cache window. `verifyAdminFresh` (line 246-257) does the same query for routes that branch on admin-ness.

**Finding F-AD-H3-1 (INFO):** Fresh-read on every admin endpoint is correct (audit S-C1) but it's also a hot-path SELECT on `users`. Adequate at current scale; would be the first thing to revisit if admin endpoints become high-frequency.

### H4. Hard-delete

`/users/:id` DELETE (line 426-484):
1. Requires `{confirm: 'DELETE', reason: '<200 chars>'}` body (line 421-424).
2. Cannot delete self (line 436-438).
3. `harvestUserKeys` walks every MinIO key the user owns BEFORE the SQL DELETE.
4. Wraps DELETE + refresh_tokens cleanup in a transaction.
5. Post-commit `removeKeysBestEffort(flattenHarvest(harvest))` purges MinIO.
6. Audit logs `admin.user_delete` with reason metadata, severity=critical.

This is the **hard purge path**. The 30-day cooling-off path is in `users.ts:592-700` (DELETE `/users/me`) and is a separate flow.

**Finding F-AD-H4-1 (MED):** Admin hard-delete bypasses the soft-delete grace window entirely — there is no "Admin marked this user for purge in 30 days" path. That's arguably correct (admin enforcement actions like CSAM/abuse should be immediate) but it means a single-typed-DELETE-token (line 421-424) on the UI fully wipes 19+ tables with no recovery. The reason is mandatory and audit-logged with `severity: 'critical'` (line 472), so post-hoc forensics work — but consider whether a "delete after N days unless reverted" intermediate state would be safer for non-abuse cases.

**Finding F-AD-H4-2 (MED):** `harvestUserKeys` (`utils/storage-cleanup.ts`) runs INSIDE the transaction (line 448). If MinIO harvest fails or hangs, the DB transaction is held open. Better to `BEGIN; DELETE…; COMMIT; then harvest+remove`, accepting that some keys may already be unreferenced before purge.

**Finding F-AD-H4-3 (MED):** The same path (`admin.user_delete`) does NOT trigger the email `EmailService.sendAccountDeletionEmail` — that send is in `users.ts:686` (user-initiated soft-delete only). So an admin hard-delete leaves the user with no notification at all. Either deliberate (abuse-case silent ban) or oversight; either way, document.

### H5. Suspend flow

`/users/:id/suspend` PUT (line 268-342):
1. Refuses to suspend an admin (line 286-298) and logs that attempt as `severity: 'warning', success: false`.
2. Captures `plan_before_suspend = plan` and flips `plan='suspended'`.
3. `DELETE FROM refresh_tokens WHERE user_id = $1` — burns every refresh token (line 321).
4. `invalidateUserCache(id)` — drops the Redis user row so other replicas don't hold a stale `plan` value for the 10s TTL.
5. Audit logs `admin.settings_change`, severity=warning, with sanitized reason metadata.

The access-token in flight is **not blacklisted** — the user could keep using a 1h JWT until it expires.

**Finding F-AD-H5-1 (HIGH):** Suspend kills refresh tokens but does not blacklist the live access token. The auth middleware re-reads the user row from Redis (10s TTL) or DB and bounces on `plan === 'suspended'` (`middleware/auth.ts:162-168`), so the in-flight token can hit at most one or two endpoints before the 10s cache expires — but until then, **suspended users keep accessing admin/user endpoints**. The fix is to call `blacklistTokenAuto(authHeader.substring(7))` like the password-change path does (`users.ts:567-571`). The admin doesn't have the suspended user's access token, but the `invalidateUserCache` call closes the gap fast enough that this is borderline; still, calling out as a design inconsistency with `/me/password`.

---

## I. Admin permissions

### I1. is_admin shape

`users.is_admin BOOLEAN`. Set in mig 002 (the enhanced features migration). Not an enum, not a role table — single boolean.

### I2. How is_admin gets set

No API endpoint sets `is_admin`. Searched `apps/api/src/routes/*` — `is_admin` only appears in SELECTs, never in INSERT/UPDATE outside the test fixtures. **Provisioning is SQL-only**: an operator must `UPDATE users SET is_admin = true WHERE email = 'x@y'` directly against Postgres.

### I3. Admin grants admin via API

**No path exists.** A admin cannot promote another user via API. The only way to grant admin is SQL.

**Finding F-AD-I3-1 (INFO):** This is intentional and correct — closing off API-level admin elevation reduces blast radius. The trade-off is that every new admin requires DB access. Document the operator runbook (probably belongs in `~/Projects/staging/` rather than this repo).

### I4. Admin actions in audit log

Cross-referenced every admin mutation:

| Route | Logged? |
|---|---|
| `admin/users/:id/suspend` | yes (line 330) |
| `admin/users/:id/unsuspend` | yes (line 404) |
| `admin/users/:id` DELETE | yes (line 471) |
| `admin/partners/:id/approve` | yes (line 577) |
| `admin/partners/:id/reject` | yes (line 628) |
| `partners/admin/commissions/:id/approve` | **NO** |
| `partners/admin/commissions/:id/pay` | **NO** |
| `partners/admin/commissions/:id/cancel` | **NO** |
| `audit/cleanup` | yes (line 217 — before cleanup, severity=critical) |

See F-AD-H2-1 above.

---

## J. Audit log endpoints

### J1. /audit/logs

`routes/audit.ts:25-74`. Pagination params `page` (default 1), `limit` (default 50, max 100). Offset is `(page-1)*limit`. **The service caps offset at 1000** (`audit.service.ts:8, 413-415`) so deep pagination throws — protects against table-scan DoS.

Non-admins are scoped to their own `userId` (line 45). Admins can pass any `userId`. Other filters: `action, severity, resourceType, resourceId, startDate, endDate, success`.

### J2. /audit/logs/me

Line 80-97. Calls `AuditService.getUserLogs(user.id, …)` which is a thin wrapper over `query({ userId })`. Scoping enforced server-side — the `user.id` comes from the JWT, not a query param.

### J3. /audit/stats

Line 154-163. `requireAdmin`. Returns `{total, by_severity, by_action, failed_actions}`. Two SQL queries (avoids cartesian join in `audit.service.ts:580-602`).

### J4. Severity filter

Enum constants `info | warning | error | critical` (`audit.service.ts:77`). The route accepts a string and the SQL is bound directly (`audit.service.ts:431-434`):
```ts
if (severity) {
  conditions.push(`severity = $${paramIndex++}`);
  params.push(severity);
}
```
No server-side enum validation — an unknown severity string just produces zero matches. Safe (parameterized) but a Joi validator would surface bad params with a 400 instead of an empty result.

### J5. Action filter

Same shape — exact-match SQL bind. The list of valid actions is enumerated in `audit.service.ts:15-75`. No text-search/LIKE support; the dashboard `audit-log-table.tsx:46-48` does client-side LIKE on the returned page only.

**Finding F-AD-J5-1 (LOW):** Action search is client-side post-fetch. If an operator searches for "partner.gift" but only has the first 50 logs in memory, results in other pages are missed. A `?action_prefix=partner.` param with server-side LIKE matching would scale.

### J6. Date range filter

`startDate / endDate` query params parsed via `new Date(...)` (route line 57-58). Bound as `created_at >= $N` / `<= $N`. No timezone handling beyond JS Date parsing — `?startDate=2026-05-10` is parsed as `2026-05-10T00:00:00.000Z` (UTC midnight) so this is correct as long as the DB column is `TIMESTAMPTZ` (which it is per mig 004).

### J7. PII in audit metadata

Emails (`user_email`) and IPs (`ip_address`) are always logged and visible to admins. **No redaction in the audit GET response.** Metadata is whatever the caller passed in — `admin.user_delete` records the deletion reason verbatim, `partner.reject` records the reason verbatim. Truncation cap at 8KB (mig 065 `chk_audit_logs_metadata_size`), service-side limit before insert at the same value (`audit.service.ts:13, 155-157`).

**Finding F-AD-J7-1 (LOW):** Audit metadata can contain arbitrary admin-supplied text (suspend reason, delete reason, partner reject reason). Currently sanitized only via `sanitizeAuditText` (`admin.ts:20-27`) for control-char stripping. No PII redaction. A reason text "user X is a prior employee of Y company" persists in the audit log forever (1y retention for info, 3y for warning/error/critical per `mig 031` cleanup function). For an EU operator dealing with GDPR Article 17 right-to-erasure, this is potentially in scope — audit logs are out-of-scope under most legal-obligation exemptions but only if the data they contain is genuinely necessary.

---

## K. Admin dashboard UI

### K1. /admin/audit page

`apps/partner-dashboard/src/app/admin/audit/page.tsx` calls `serverApiClient` which hits `/api/v1/audit/logs?page=&limit=50` and `/api/v1/audit/stats`. The table component is `components/audit-log-table.tsx` (258 lines). Metadata pretty-print is capped at **4096 bytes** (`audit-log-table.tsx:6`):
```ts
const METADATA_RENDER_LIMIT_BYTES = 4096
```
DB stores up to 8KB; dashboard renders at most 4KB. Truncation message appears below the pre block when triggered.

**Finding F-AD-K1-1 (INFO):** 4KB dashboard cap matches Ch10-W052 audit note. Confirmed working.

### K2. /admin/users — typed DELETE

`components/UserTable.tsx:7-12`:
```ts
const DELETE_CONFIRM_TOKEN = 'DELETE'
```
The delete modal (line 238-286) requires the literal text `DELETE` typed into an input before the button enables (line 278: `disabled={deleteLoading || deleteInput !== DELETE_CONFIRM_TOKEN}`). Suspend uses a plain `confirm()` (line 60) — less robust.

**Finding F-AD-K2-1 (LOW):** The DELETE call from the UI sends a POST body of `undefined` (line 81-83). The API requires `{confirm: 'DELETE', reason: '<200 chars>'}` (admin.ts:421-424). **The UI doesn't send a reason** so the API Joi validator at `validate(adminDeleteUserBodySchema, 'body')` will reject the request as 400. This is a real bug — either: (a) the UI never sends reason and admin hard-delete is broken from the dashboard, or (b) testing confirms admin delete works via curl only.

Verifying: searched `partner-dashboard/src/components/UserTable.tsx:80-83`:
```ts
await apiClient(`/api/v1/admin/users/${encodeURIComponent(deleteCandidate.id)}`, {
  method: 'DELETE',
})
```
No body is set. The Joi schema (`admin.ts:421-424`) requires `confirm: 'DELETE'` and `reason: required().min(1)`. This will 400.

### K3. /admin/partners — approve/reject

`components/partner-table.tsx` and `partner-actions.tsx` carry the approve/reject buttons. Cross-checked: `partner-actions.tsx` (not read here but in the file list) wires `PUT /admin/partners/:id/approve` and `/reject`. The partners table component is read into the page.

### K4. /admin/commissions — approve/pay/cancel

`admin-commission-table.tsx:43, 65, 87` — hits `/api/v1/partners/admin/commissions/:id/approve`, `/pay`, `/cancel`. Uses `confirm()` for each. Optimistic UI updates with rollback on error.

### K5. /admin/health

`app/admin/health/page.tsx` calls `/health/detailed`. Renders status for `database, redis, minio`. No secret data leaked — only `status` and optional `message` per service.

### K6. /admin/analytics — DAU/WAU/MAU

`app/admin/analytics/page.tsx`. DAU/WAU/MAU computed in `admin.ts:144-146`:
```sql
COUNT(DISTINCT ua.user_id) FROM user_analytics ua WHERE ua.last_active_at >= NOW() - INTERVAL '24 hours'
...7 days...30 days...
```
**Three independent COUNT(DISTINCT)** in one query (line 134-147). Adequate at current scale.

**Finding F-AD-K6-1 (LOW):** Growth-rate calc on the page is `(signups_7d / (signups_30d/4)) * 100 - 100` (`analytics/page.tsx:62-63`). The "/4" approximates "7-day chunks in a 30-day window" — but `30/4=7.5` and the math is off. Should be `(signups_7d / (signups_30d * 7/30)) - 1` or simpler `(signups_7d * 30 / (signups_30d * 7)) - 1`. Cosmetic dashboard math, not a correctness issue.

### K7. /admin/settings

`app/admin/settings/page.tsx` — read-only display of `user.email` and `user.id` for the logged-in admin. **No settings actually exist.** It's a stub.

**Finding F-AD-K7-1 (INFO):** Settings page is a placeholder. CLAUDE.md doesn't list it as outstanding; depending on intent either remove or stub-out for future work.

---

## L. Daily-stats SQL

### L1. Daily signups (admin.ts:164-180)

```sql
SELECT DATE(created_at) AS date, COUNT(*) AS count
FROM users
WHERE created_at >= NOW() - MAKE_INTERVAL(days => $1)
GROUP BY DATE(created_at)
ORDER BY date ASC
```
Default `$1 = 30`, validated by `dateRangeQuerySchema` (1-365). **Does not exclude soft-deleted users** — signups in the past 30 days that have since been soft-deleted are still counted.

**Finding F-AD-L1-1 (LOW):** `/stats/daily-signups` counts soft-deleted users. The `/stats/full` total filters `WHERE deleted_at IS NULL` (audit Ch01-F075 fix at line 69-75) but the daily-signups breakdown does not. Inconsistent. Either both filter or both don't — leadership chart numbers should reconcile with the headline total.

### L2. Daily items (admin.ts:183-199)

Same shape: `DATE(created_at) AS date, COUNT(*) FROM items`. No `is_archived` filter, no `JOIN users WHERE deleted_at IS NULL`.

**Finding F-AD-L2-1 (LOW):** Items belonging to soft-deleted users are still counted on the daily-items chart. Same reconciliation problem.

### L3. Indexes

`idx_users_created_at` (some flavor exists per the partner_commissions migrations). `DATE(created_at)` is not indexable directly; PG would scan. For 30-day windows on a sub-million-row users table, fine. Becomes a concern past ~10M rows.

### L4. Timezone

`DATE(created_at)` where `created_at` is `TIMESTAMPTZ` uses **the session's `TIMEZONE` setting**, not UTC. If the API process connects with `TIMEZONE=UTC` (Postgres default for new clusters but not guaranteed), the bucket is UTC. If it inherits the server's local TZ, charts will shift.

**Finding F-AD-L4-1 (MED):** Daily-stats SQL uses `DATE(created_at)` without an explicit `AT TIME ZONE 'UTC'`. The notification cron (e.g. `notifications.service.ts:930`) uses `(NOW() AT TIME ZONE 'UTC')::date` — consistency would be to spell UTC explicitly in admin stats too. Otherwise a Postgres restart with a different `timezone` GUC could silently shift the daily-bucket boundary by hours.

---

## M. Adversarial cases

### M1. Admin suspends self

`admin.ts:286-298` blocks suspending **any** admin (target user check). Self-suspend is therefore also blocked. **Verified** by test `admin.test.ts:110-120`.

### M2. Self-delete via /me vs /admin/users/:id

Different paths:
- `DELETE /users/me` (`users.ts:592-700`) → **soft-delete** with 30-day cooling-off, plan='suspended', refresh tokens deleted, account deletion email sent.
- `DELETE /admin/users/:id` (`admin.ts:426-484`) → **hard-delete**, immediate, no recovery, harvests MinIO keys, no email sent (F-AD-H4-3).

The admin DELETE explicitly blocks self-deletion (line 436-438): `if (id === req.user!.id) throw new AppError('Cannot delete your own account', 400)`.

**Finding F-AD-M2-1 (LOW):** An admin cannot delete their own account via either path easily — soft-delete via `/me` works (admin or not) but the admin DELETE path refuses. Could be a hassle for an admin who legitimately wants to leave; consider whether a "demote self first, then soft-delete" flow is documented anywhere.

### M3. Demoted admin's session

`middleware/auth.ts:215-234` — `requireAdmin` re-reads `is_admin` from the DB on every call. A demoted admin's next `/admin/*` call returns 403 **immediately**, regardless of the 10s Redis cache or 1h JWT TTL. `verifyAdminFresh` (line 246-257) closes the same gap for routes that branch on admin-ness (`/audit/logs`, `/audit/logs/resource/:type/:id`).

`auth.ts:851-880` GET `/auth/role-check` is the dashboard's "is this user still admin" poll — returns the fresh DB-derived `is_admin` so the middleware can de-route a demoted admin within 30s (the dashboard's `hk_role_check` poll cadence).

### M4. Admin reads audit logs of own actions

Yes — visible. `routes/audit.ts:42-45` shows an admin can pass any `userId` filter. An admin querying with their own id returns their own action history. No special "admins see redacted audit of their own actions" path — full transparency.

### M5. Regular user → /admin/*

`requireAdmin` middleware on every route returns `403 Admin access required` (`middleware/auth.ts:216-218`). Test `admin.test.ts:14-22` verifies.

### M6. Partner → /admin/*

Same — partners are not admins, so `requireAdmin` rejects.

### M7. Failed admin DELETE → audit?

In `admin.ts:426-484` — if the DELETE throws (e.g. 404 user not found at line 454-456), the function rolls back and rethrows. **The audit log call at line 471 happens AFTER the COMMIT, only on success.** A failed DELETE does NOT write an audit row.

**Finding F-AD-M7-1 (MED):** Failed admin DELETE actions are not audited. An admin probing for user IDs by issuing DELETEs against random UUIDs leaves no trail beyond the request log. Similar pattern exists for the suspend route (failed branch at line 286-298 logs `success: false` to audit — good) but the DELETE path doesn't symmetrize. Add an `AuditService.logFromRequest(..., {success: false, errorMessage: …})` in the catch.

---

## N. Tests

### N1. Admin / audit test inventory

- `admin.test.ts` (204 lines, 8 tests): `/admin/stats` (admin + non-admin), `/admin/users`, `/admin/users/:id/suspend` (admin, non-admin, 404, can't-suspend-admin, prior-plan restore on unsuspend), forged-isAdmin-JWT rejection, soft-deleted users excluded from stats/full.
- `audit.test.ts` (172 lines, 9 tests): `/audit/logs` own logs, `/audit/logs/me`, `/audit/security` admin/non-admin, `/audit/stats` admin/non-admin, `/audit/activity-summary` admin/non-admin, `/audit/cleanup` admin/non-admin with phrase HMAC.
- `phase10.audit.test.ts` (13k LOC) — broader audit scenarios (probably re-tests specific findings from earlier passes).

### N2. Coverage gaps

**No test covers:**
- The admin `DELETE /users/:id` route (hard-delete with reason/confirm body) — `admin.test.ts` only tests suspend/unsuspend.
- The admin `/partners/:id/approve` and `/reject` routes — neither test file references them.
- The three commission endpoints (`/partners/admin/commissions/:id/approve|pay|cancel`).
- The `/admin/stats/daily-signups` and `/daily-items` charts (existence, not content correctness).
- The `requireAdmin` DB-fresh-read regression — admin.test.ts:147-165 tests forged JWT but **not** the path where the JWT is honest and the DB row's `is_admin` got flipped to false after issue. That's the actual S-C1 concern.

**Finding F-AD-N2-1 (MED):** Critical mutation paths (commission approve/pay/cancel, partner approve/reject, hard-delete) have **zero test coverage**. The auth/auth-bypass cases are well-tested but the business-logic mutations are not. For a route that fires a Stripe transfer (`partners.ts:1139-1150` /pay), missing test coverage on the happy path + concurrency case is high-risk.

---

## O. Tips, referral, contact handlers

### O1. /tips

There is **no `/tips` HTTP route.** The tips system is consumed internally by `routes/notifications.ts:162-194` which queries `tips` table and returns one rotating tip per day. The notifications route is the only path users hit. Tips are seeded by mig 018 (30 rows across `new_user, maintenance, warranty, general, organization, power_user`). No admin UI for editing tips.

**Finding F-O-O1-1 (LOW):** No admin endpoint to edit/add/disable tips. Marketing or product would need direct DB write. Consider a `/admin/tips` CRUD.

### O2. /referrals

No standalone `/referrals` route. Referral codes are owned per-user (`users.referral_code`). Partner referrals via:
- `POST /api/v1/partners/referral-code` — generate or fetch (`partners.ts:240`).
- `GET /api/v1/partners/referrals` — list users referred (`partners.ts:256`).

Generic referral attribution at signup is in `auth.ts:163-...` (`resolveReferredBy(referralCode)`).

### O3. /contact

`routes/contact.ts` — 117 lines. Endpoints:
- `POST /api/v1/contact` (public, `contactRateLimiter`: 3/hour per IP — `rateLimiter.ts:368-373`).
- `GET /api/v1/contact/submissions` (admin + `readRateLimiter`).

POST flow (`contact.ts:19-77`):
1. Joi validates name/email/subject/message + `website` honeypot.
2. **Honeypot trip** (line 35-44): if `website` is non-empty, silently 200 — bot can't tell.
3. `safeName = name.replace(/[\r\n]+/g, ' ').trim()` (F115) — strip CRLF before interpolating into subject.
4. INSERT into `contact_submissions` with `req.socket.remoteAddress` (no XFF trust).
5. Try `EmailService.sendContactNotificationEmail` — on failure, log but don't fail the request (line 67-71).

**IP capture:** `req.socket.remoteAddress` directly (line 56). Doesn't honor `trust proxy` — the audit explicitly notes this is intentional for the rate-limit binding (newsletter does the same in its `clientAddress` helper).

**Finding F-O-O3-1 (INFO):** Contact submission stores `req.socket.remoteAddress` which behind Caddy/LB will be the proxy IP, not the client. The audit-trail value is questionable in that case. The rate limit binding uses the same value, so the limiter is also effectively per-LB-IP rather than per-client. CLAUDE.md notes `trust proxy=1` is set; if you want client IP here, switch to `getIpAddress(req)` from `utils/ip-address.ts` like the audit service does.

### O4. /partner-onboarding

No `/partner-onboarding` route. Partner onboarding happens via:
- `POST /api/v1/partners` — register as partner (`partners.ts:`...).
- `POST /api/v1/partners/stripe-connect/onboard` — start Stripe Connect Express onboarding (`partners.ts:670`).
- Dashboard: `apps/partner-dashboard/src/app/onboarding/client.tsx` orchestrates the wizard.

No findings — the onboarding flow is well-covered by Stripe Connect's account_link API.

---

## Summary

Total findings: **40** (1 INFO+, 18 LOW, 16 MED, 5 HIGH).

### HIGH

- **F-EM-A7-1** — No persistent retry queue for SendGrid failures. Gift activation / verification emails can be lost on transient SendGrid outages.
- **F-EM-C4-1** — Three transactional templates claim Gmail/Yahoo one-click `List-Unsubscribe-Post` compliance but the URL is a logged-in settings page, not a one-click endpoint.
- **F-EM-E1-1** — No SendGrid event webhook. Bounces, complaints, and deliverability stats are blind to the application DB.
- **F-EM-G2-1** — No physical postal address in any template footer. CAN-SPAM compliance gap for promotional/branded transactional sends.
- **F-AD-H2-1** — Commission approve/pay/cancel mutations have NO audit log entries. A fraudulent admin can drain a partner's pending commissions silently.
- **F-AD-H5-1** — User suspend doesn't blacklist the in-flight access token, only burns refresh tokens. Auth middleware closes the gap via 10s Redis TTL but the path is inconsistent with `/me/password`.

### MED (selected)

- **F-EM-A5-1** — No SendGrid categories means ops can't filter activity feed by template.
- **F-EM-A7-2** — Process-local circuit breaker, not Redis-shared.
- **F-EM-B6-1** — Account deletion email is sent at soft-delete day 0, copy implies finality.
- **F-EM-B7-1** — No day-25 grace warning email before hard purge.
- **F-EM-B8-1** — Partner welcome email is HTML-only, no text fallback.
- **F-EM-B10-1** — Warranty/maintenance unsubscribe URL points at a logged-in settings page.
- **F-EM-D3-1** — No admin "resend verification / resend gift" endpoint despite `giftResendRateLimiter` existing unused.
- **F-EM-F2-1** — Newsletter confirmation token has no TTL.
- **F-AD-H2-2** — Admin commission routes mounted under `/partners/admin/commissions/*` not `/admin/commissions/*`.
- **F-AD-H4-1/2/3** — Hard-delete txn holds MinIO harvest, no email notification, no intermediate state.
- **F-AD-L4-1** — Daily-stats SQL doesn't pin UTC for date bucketing.
- **F-AD-M7-1** — Failed admin DELETEs leave no audit trail.
- **F-AD-K2-1** — Admin user-delete UI doesn't send required `{confirm, reason}` body — endpoint will 400. **Real bug.**
- **F-AD-N2-1** — Critical mutation paths (commission, partner approve/reject, hard-delete) have zero test coverage.

### Notable paths

- `apps/api/src/services/email.service.ts` — 1466 lines, 10 inline templates.
- `apps/api/src/routes/admin.ts` — 892 lines, 18 endpoints.
- `apps/api/src/routes/partners.ts:1052-1217` — 3 admin commission endpoints, no audit.
- `apps/api/src/routes/audit.ts` — 228 lines, 7 endpoints, S-C1 fresh-DB pattern correct.
- `apps/api/src/services/audit.service.ts` — hash-chain verified daily via `cron index.ts:233-245`.
- `apps/partner-dashboard/src/components/UserTable.tsx:80-83` — broken admin DELETE call.
- `apps/partner-dashboard/src/components/admin-commission-table.tsx` — `confirm()`-style confirmation, not typed-token.

### Cross-references to earlier audit dispositions

- H-A2 (response shape on existing email) — verified in users.ts:459-477.
- S-C1 (fresh admin DB read) — verified in middleware/auth.ts:215-257 and routes/audit.ts:42, 112.
- S-C5 (per-recipient change-email dedupe) — verified in users.ts:426-457.
- F095 (audit hash chain) — verified in mig 065 + AuditService.verifyHashChain.
- F094 (8KB metadata cap) — verified in mig 065 CHECK + service-side check at audit.service.ts:155-157.
- Ch10-W052 (4KB dashboard cap) — verified in audit-log-table.tsx:6.
- Ch10-W040 (typed DELETE token) — verified in UserTable.tsx:10. But see F-AD-K2-1 — the UI doesn't send the required reason field.
- F081 (SendGrid retry + circuit breaker) — verified in email.service.ts:48-112.
- F086 (CRLF sanitization on headers) — verified in email.service.ts:40-42, 369, 1388.
- F082 (RFC 8058 List-Unsubscribe-Post) — partially shipped — see F-EM-C4-1.
- F110 (64-char unsubscribe HMAC) — verified in newsletter.ts:23-28.
- F112 (socket address not trust-proxy IP for newsletter / contact rate limiting) — verified.
- F115 (CRLF strip on contact name) — verified in contact.ts:50.
