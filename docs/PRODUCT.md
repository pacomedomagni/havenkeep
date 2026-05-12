# HavenKeep Product Spec

This document describes what HavenKeep is and who it is for. **It describes only what is actually built.** Surfaces that were once spec'd as shipped but aren't — and v1 scope cuts — live in [DEFERRED.md](./DEFERRED.md), not here. Speculative roadmap ideas live on the marketing site's `/roadmap` page. App copy, marketing, and the partner agreement should not imply anything that isn't in this file.

For *how it is built*, see [ARCHITECTURE.md](./ARCHITECTURE.md). For *how to run it*, see [the root README](../README.md).

---

## 1. The one-line pitch

HavenKeep is a home asset and warranty tracker that pays attention so you don't have to. You log the appliance, the receipt, the warranty length once. We remind you before things expire, surface required maintenance to keep coverage valid, and help you file claims when things break.

The bet: Americans waste roughly $16B/year on warranties they forgot they had. The vast majority of that loss is logistical, not financial — people would file the claim if they remembered the warranty existed and could find the receipt. HavenKeep is the system that remembers and finds.

---

## 2. Who it is for

### 2.1 Primary user — the homeowner

The person who buys appliances and major systems for their home. They:

- Know they should keep receipts but don't.
- Have a junk drawer with three crumpled warranty cards in it.
- Will dutifully take a photo of the new fridge box on delivery day and never think about it again until the fridge breaks 13 months later — exactly one month after the manufacturer warranty expired.
- Are not interested in spreadsheets, tagging systems, or filling out 30 fields per item.

The homeowner mental model HavenKeep optimises for: **"I just want to know that I'm covered, and I want someone to tell me when I'm not."**

Free plan caps usage at 5 items so a curious user can try it without a paywall slap. Premium ($2.99/mo or $24/yr) unlocks unlimited items, receipt OCR, PDF/CSV export, and customisable reminders. The premium pitch is the 14× ROI: $24/yr to avoid losing $340/yr on forgotten warranties.

### 2.2 Secondary users — partners

Realtors, builders, contractors, and property managers who hand keys to homebuyers and want to stay in the homebuyer's life past closing. They:

- Are looking for a closing gift that isn't a fruit basket.
- Pay per gift sent ($99 / $149 / $249 by tier — Basic / Premium / Platinum), no monthly fee, no contract.
- Earn a 10–20% commission (by tier) on each gift they send.

Partners get a dashboard ([apps/partner-dashboard](../apps/partner-dashboard)) with gift-creation flows, real-time commission tracking, Stripe Connect onboarding, payout requests, and 1099-NEC handling via Stripe.

### 2.3 Tertiary users — the business

Admin tooling lives in the same dashboard at `/admin/*`. Admins approve / reject partner applications, suspend or hard-delete user accounts, monitor audit logs, view system health, and track conversion / signup / DAU metrics. The audit log is hash-chained so even an admin can't tamper with the history without leaving a verifiable break.

---

## 3. The five core jobs

### 3.1 Track every household asset

Add anything that has a warranty: appliances, electronics, HVAC systems, roofing, plumbing, lawn equipment, even furniture. 43 categories shipped (`enums.dart` `ItemCategory`). Each item carries: name, brand, model number, serial number, category, room, purchase date, store, price, warranty length (months), warranty type (manufacturer/extended/store/home_warranty), warranty provider, notes, and barcode.

Four ways to add an item:

1. **Quick-add** — 3×3 grid of common categories (fridge, washer, dryer, dishwasher, microwave, oven, HVAC, water heater, "other"). Tap a tile, fill in brand + purchase date + warranty duration, save. Defaults pulled from `category_defaults` (mig 067/090) so a fridge defaults to 12 months, a roof to 25 years.
2. **Barcode scan** — `mobile_scanner` opens the camera. The scanned barcode hits `/api/v1/barcode-lookup`, which queries an external product database and pre-fills brand + product name + product image.
3. **Receipt scan** — Camera capture → multipart POST to `/api/v1/receipt-scan` → OpenAI Vision extracts merchant, total, date, line items, category guess. Confidence threshold of 0.85 + DKIM-passing email needed for auto-import; lower confidence parks the receipt in a review queue.
4. **Manual entry** — The 3-step wizard for power users. Step 1: name + category + brand. Step 2: purchase date + warranty length. Step 3: optional details (price, store, room, notes, model/serial, barcode). Draft autosaves to SharedPreferences with 24h TTL so a backgrounded form survives.

Items belong to a `Home`. A user can have multiple homes (a primary residence, a rental, a parent's house they help manage). The dashboard's home picker switches the entire app's view: items, maintenance, claims all filter to the current home.

### 3.2 Never miss an expiry

The notification system is what justifies the app's existence. Three layers:

- **Expiry reminder** — one reminder per item, fired at `first_reminder_days` days before expiry (default 30, range 1–365). User-configurable per-account in [`NotificationPreferences`](../packages/shared_models/lib/src/notification_preferences.dart). The cron job in [`apps/api/src/index.ts`](../apps/api/src/index.ts) wakes daily at 09:00 UTC and queries items whose `warranty_end_date` is exactly the configured number of days out for each user. Multi-milestone cascades (90/60/30/14/7) are on the roadmap — not yet shipped.
- **Daily digest** — opt-in. Groups every reminder into a single 09:00 push so the user doesn't get five separate notifications when three appliances expire the same week.
- **Quiet hours** — opt-in. Suppresses local notifications during the window (defaults 22:00–08:00).

Push delivery is FCM on Android, APNs on iOS. Notification rows are written to `notification_history` and shown in the in-app inbox at `/notifications`. Unread count is badged on the bottom nav.

### 3.3 Make the receipt findable when you need it

A warranty without a receipt is half a warranty. HavenKeep stores receipts and warranty cards as `Document` rows linked to an item:

- Upload from camera, gallery, or file picker.
- Image compression on the client (max 1600px); PDF passes through unchanged.
- Stored in MinIO (bucket-level encryption at rest); presigned URL on read.
- Document type tagged: receipt / warranty_card / manual / invoice / other.
- Total document-storage cap, enforced server-side: Free 200 MB, Premium 2 GB.

The "Share Claim" sheet generates a **claim-summary PDF** (item details + warranty status + a list of the documents you have on file). Attach that PDF — plus the actual receipt/warranty-card files from the item's Documents tab — when you forward a claim to the manufacturer or insurer. (Embedding the document files into a single combined PDF is a planned enhancement — see [DEFERRED.md](../docs/DEFERRED.md).)

### 3.4 Surface required maintenance

For categories where missing maintenance voids the warranty (HVAC filter changes, water heater anode rod, garage door spring), HavenKeep ships a maintenance schedule per category and reminds the user.

- **Catalog schedules** seeded server-side in `maintenance_schedules`. Each task has `frequency_months`, `priority`, `is_required_for_warranty`, optional `how_to_url` and `video_url`.
- **Per-item customisation** lets a user override the cadence (every 3 months → every 6 months) or opt out entirely. **Stored on the device** (SharedPreferences) for v1 — overrides and snoozes don't yet sync across devices or survive a reinstall. Server-side persistence is a planned enhancement — see [DEFERRED.md](../docs/DEFERRED.md).
- **History** is logged via `MaintenanceHistory` rows. The dashboard's `View all` link opens the paginated history with calendar + list toggles.
- **Bulk-mark-done** — power users with a Saturday cleaning routine can multi-select due tasks and check them off in one tap.

The maintenance dashboard ([`maintenance_screen.dart`](../apps/mobile/lib/features/maintenance/maintenance_screen.dart)) shows tasks grouped by item with overdue / due / coming-up chips, a 7/30/90-day window filter, snooze options, and a savings-feed strip showing what other users have prevented by doing maintenance.

### 3.5 File claims and track what they saved

When something does break:

- Open the item, tap "File a claim", capture issue description, repair cost, amount saved, status (filed / in_review / approved / denied / settled / closed).
- Status transitions are tracked in `warranty_claim_state_history` (mig 097: immutable trigger; CASCADE delete from parent claim is allowed).
- The dashboard's claims list ([`claims_list_screen.dart`](../apps/mobile/lib/features/warranty_claims/claims_list_screen.dart)) shows total saved across every claim — the running counter that tells the user "you've saved $X by remembering."
- The community-savings feed ([`/api/v1/warranty-claims/feed`](../apps/api/src/routes/warranty-claims.ts)) shows anonymised "$220 saved on a fridge in Austin, TX" entries — social proof that the system works.

---

## 4. The two flagship flows

These two flows are what HavenKeep is, end-to-end. Everything else supports them.

### 4.1 Email scanner — finding warranties you forgot you had

The hardest part of warranty tracking is the cold start. A new user might own 30 things with active warranties, but logging them one by one is a Saturday afternoon. The email scanner cuts that to a tap.

**Setup**:
1. User taps "Connect Gmail" or "Connect Outlook" in the email scanner screen.
2. The app launches `flutter_web_auth_2` against `accounts.google.com/o/oauth2/v2/auth` (or Microsoft's equivalent) with a 32-byte base64-url state parameter and read-only scopes.
3. On callback, the auth code is forwarded to `/api/v1/email-scanner/scan`. The API exchanges it for refresh + access tokens server-side using `client_secret`.
4. Refresh token is encrypted AES-256-GCM (mig 038) and stored. Granted scope is recorded so a future scope downgrade is detected.

**Scan**:
1. The API queries the inbox for messages matching purchase-confirmation patterns (subject regex + sender allowlist `TRUSTED_RETAILER_DOMAINS`).
2. Each candidate is parsed: DKIM check (`Authentication-Results` header must have `dkim=pass`), HTML body fed to OpenAI Vision with a prompt that returns `{ merchant, date, total, items[], category_guess, confidence }`.
3. Auto-import gate: confidence ≥ 0.85 AND DKIM pass AND merchant on the trusted-retailer allowlist.
4. Anything that doesn't auto-import lands in the email-scanner review queue. The user opens the queue, sees parsed receipts side-by-side with the original email body, and one-tap-accepts each one.
5. OpenAI cost is capped per-user-per-day via `OPENAI_DAILY_CAP_MICROS` (queried from the `openai_user_daily_cost` view before each call).

**Privacy**: read-only scope only. We do not send mail, modify the inbox, change folders, or read messages outside the purchase-confirmation pattern. The user can revoke at any time from Google/Microsoft account settings; the app deletes our copy when they remove the integration.

### 4.2 Partner program — closing gifts and commission

Realtors hand keys to homebuyers. That's the moment HavenKeep wants to be present.

**Partner side**:
1. Realtor signs up at the partner dashboard, completes the 2-step onboarding (company name + partner type + license number + service areas).
2. Application is `pending` until an admin approves at `/admin/partners`. (Mig 071: `partner_status` enum is `pending | active | rejected`. Mig 092: invariant CHECK keeps `is_active` and `status` aligned.)
3. Approved partner connects Stripe Connect Express. Stripe collects banking + tax info; HavenKeep never sees raw financial data.
4. Realtor opens the gift form, enters homebuyer name + email + closing date + premium duration (3/6/12 months) + custom message. Submits.

**Server side (3-phase flow)**:
1. **Reserve** — INSERT a `partner_gifts` row with `status='pending_payment'`, generated activation code (16 hex with dashes, hashed before storage), reserved outside the Stripe transaction so a Stripe failure doesn't poison the connection.
2. **Charge** — `stripe.paymentIntents.create({ amount, customer, payment_method, confirm: true, off_session: true })`. Tier-based amounts: $99 (Basic), $149 (Premium), $249 (Platinum). The `payment_method` is passed explicitly because Stripe's default-PM resolution is unreliable.
3. **Promote** — UPDATE the gift row to `status='created'`, INSERT a `partner_commissions` row with `status='pending'`. If the promote fails, the API issues a refund-compensation step so the partner isn't charged for a gift that doesn't exist.

**Homebuyer side**:
1. They get an email with a branded landing page (partner's logo, brand color, custom message) and an activation link.
2. The activation link is a universal/deep link: `havenkeep.com/gift/<code>` → `havenkeep://gift/<code>`. Tapping opens the app to the activation screen with the code pre-filled.
3. Activation requires the email the gift was sent to (closes the enumeration oracle — guessing a code without the email gets a generic error).
4. Activation is rate-limited (5/hr per `(activation_code_hash, ip)`, 15-min lockout on the 6th attempt).
5. Successful activation extends `users.plan_expires_at` by `premium_months`, stacking on any existing expiry.

**Commission and payout**:
1. The commission row sits at `pending` for 30 days (`COMMISSION_AUTO_APPROVE_HOLD_DAYS=30`) — the refund-protection window. A `charge.refunded` webhook within 30 days triggers a clawback (sibling reversal row with negative amount).
2. After 30 days, the daily cron promotes `pending` → `approved`.
3. Partner taps "Request payout" in the dashboard. The API calls `stripe.transfers.create` against the partner's Connect account and updates the commission to `paid` with the Stripe Transfer ID.
4. Stripe issues 1099-NEC each January for partners who earn $600+ in a year. The dashboard's "Tax documents" button opens the Stripe Express dashboard (`stripe.accounts.createLoginLink`).

Commission is earned on the **gifts a partner sends** — the per-gift commission rate is set by tier (see §5.2). A "lifetime commission on extended-warranty purchases by the partner's referred users" was previously described here; that depends on an extended-warranty marketplace that isn't built — see [DEFERRED.md](../docs/DEFERRED.md). It should not appear in marketing or the partner agreement.

---

## 5. Pricing and plans

### 5.1 Consumer

| Plan | Price | Items | OCR | Export | Support |
|---|---|---|---|---|---|
| **Free** | $0 forever | Up to 5 | — | — | Community |
| **Premium** | $2.99/mo or $24/yr (33% annual savings) | Unlimited | AI receipt scanning | CSV + PDF + per-item share | Priority |

Premium is sold via App Store IAP, Play Billing, or web (Stripe). RevenueCat unifies subscription state across the three platforms — the API treats RevenueCat as the source of truth via webhook (`INITIAL_PURCHASE` / `RENEWAL` / `EXPIRATION` / `TRANSFER`). Cancellation runs through the platform — App Store, Google Play, or Stripe — per their published policies. We don't operate a separate web refund flow.

Partner gifts grant Premium for a partner-chosen window between 1 and 12 months (validator: [`partners.validator.ts`](../apps/api/src/validators/partners.validator.ts) `premiumMonths: 1..12`; dashboard UI exposes 3 / 6 / 12 in the gift composer). The grant stacks on any existing subscription — a user already on Premium who redeems a gift gets the gift period added to their expiry, not replacing it.

### 5.2 Partner

| Tier | Per-gift | Commission per gift |
|---|---|---|
| **Basic** | $99 | 10% |
| **Premium** | $149 | 15% |
| **Platinum** | $249 | 20% |

No monthly fee, no contract. Tier upgrades happen automatically based on quarterly gift volume — no paperwork. Volume thresholds are published in the partner agreement.

Premium-grant length is the same 1–12-month window across all three tiers — the difference between tiers is the price per gift and the commission rate, not the grant length. A longer-grant differentiator for Platinum is on the roadmap (it would need both a validator bump and a UI option).

The numbers above come from `apps/api/src/services/partners.service.ts` (`TIER_PRICE_PER_GIFT_USD`, `TIER_COMMISSION_RATES`). The marketing site reads them from the same place to avoid drift between the public price and the price at gift creation.

---

## 6. The trust contract

HavenKeep stores a lot of personal data: email, photos of receipts, warranty cards, addresses, the contents of OAuth-connected inboxes. The product is unusable without that level of trust, so the security model has to be visible, not just real. The marketing site's `/security` and `/legal/privacy` pages describe what is below.

### 6.1 What we collect and why

- **Account**: email, display name, password hash (bcrypt) or OAuth subject id.
- **Asset data**: items, warranties, receipts, photos, maintenance schedules, claim history. Stored encrypted at rest.
- **Email scanner OAuth tokens**: read-only scope. Refresh token AES-256-GCM-encrypted with key rotation. Revocable by the user at any time.
- **Subscription data**: transaction id, product, renewal status from Apple / Google / Stripe / RevenueCat. We never see card numbers.
- **Telemetry**: minimal device context (OS, app version, free memory) on crashes via Crashlytics. First-party usage events ("item created", "reminder dismissed") linked to the account, opt-out in Settings.
- **Push token**: stored to deliver reminders. Deleted on sign-out or account deletion.

### 6.2 What we never do

- Sell data to advertisers or data brokers. (No advertising SDKs anywhere.)
- Read messages outside the purchase-confirmation pattern when the email scanner is connected.
- Send mail, modify the inbox, or change folders.
- Share warranty data with manufacturers or retailers.

### 6.3 What deletion actually does

- **In-app**: Settings → Delete Account. Soft-delete is immediate; cooling-off window is 30 days during which sign-in cancels the deletion and routes the user to [`RecoverAccountScreen`](../apps/mobile/lib/features/onboarding/recover_account_screen.dart). At day 25 a single grace-reminder email goes out via [`grace-reminder.service.ts`](../apps/api/src/services/grace-reminder.service.ts) so a user who clicked Delete in frustration has a clear chance to recover. After day 30, [`account-purge.service.ts`](../apps/api/src/services/account-purge.service.ts) cryptographically erases the row from active systems.
- **By email**: required by Google Play. Email `support@havenkeep.com` from the address on the account; processed within 5 business days.
- **What's deleted**: profile, items, receipts, warranty records, documents, maintenance reminders, OAuth tokens (revoked at the provider too), push tokens, partner relationships.
- **What survives**: anonymised usage events older than 30 days that have already been aggregated into product analytics; audit-log entries we're legally required to retain. Neither contains personal data after deletion.
- **Subscriptions**: deletion does NOT cancel App Store / Play Store subscriptions. Apple and Google manage those; we don't have permission to cancel on the user's behalf. The delete-account page tells the user how to cancel in their store account.

---

## 7. Notifications, reminders, and other tactical details

### 7.1 Expiry reminder

One reminder per item, fired at `first_reminder_days` days before `warranty_end_date`. Default is 30 days; user-configurable per account (range 1–365). Persisted server-side in the `notification_preferences` table and mirrored locally in `NotificationPrefsLocal`.

The cron job that mints reminders runs daily at 09:00 UTC under advisory lock `NOTIFICATION_EXPIRATION` (`93422874`) so two replicas can't double-fire. It queries items whose `warranty_end_date` is exactly each user's configured lead-time out, inserts `notification_history` rows, and pushes via FCM/APNs.

A multi-milestone cascade (90/60/30/14/7) is on the roadmap. When that ships, this section will describe per-user milestone toggles and the schema change that comes with them.

### 7.2 Quiet hours

Local-only setting. The mobile app suppresses local notification scheduling within the window. Server-side push delivery still happens (we don't want to drop reminders entirely), but the OS will queue them.

### 7.3 Maintenance reminders

Mounted on `next_maintenance_due` per item per schedule. Computed from `last_maintenance_date + frequency_months` and capped at "every 12 months" so a 25-year roof inspection doesn't disappear.

### 7.4 Auto-archive

Items with `warranty_end_date` more than 90 days in the past are auto-archived (removed from main lists, retained in `Settings → Archived Warranties`). Toggle in Settings → Warranties → Auto-Archive Expired. The cron sweep runs daily.

### 7.5 Milestone moments

The dashboard shows a one-shot celebration banner at meaningful counts: 25 warranties protected, 100 warranties tracked, 1 year with HavenKeep, $10K+ value protected. Dismissed banners are persisted in SharedPreferences (`milestones_seen` set) so they don't reappear.

### 7.6 Recent activity

The dashboard's "Recent Activity" card hydrates from the user's audit-log projection (`/audit/logs/me`). Top 5 events with friendly labels: "Added an item", "Filed a warranty claim", "Logged maintenance", "Updated a claim". Heavier audit inspection lives in admin tooling.

---

## 8. Multi-home and multi-tenancy

A user can register multiple `Home` records and switch between them. Every item, claim, maintenance schedule, and document is scoped to a home via `home_id`. The mobile app's `currentHomeProvider` cascades through `itemsProvider`, `maintenanceProvider`, `warrantyClaimsProvider` so the entire app reflects the active home.

Use cases:
- Primary residence + vacation home.
- Helping an aging parent track their home.
- A landlord with a small portfolio (large portfolios should use the partner-as-property-manager flow instead).

Home creation isn't capped by plan today. The free-plan gate is the 5-item limit (`FREE_PLAN_ITEM_LIMIT` in `apps/api/src/config/index.ts`); both Free and Premium can register multiple homes. A per-plan home cap would need an API-level check in `apps/api/src/routes/homes.ts` plus mobile gating before it could be advertised.

---

## 9. Offline-first

The mobile app must work in places with no signal: a basement, a cabin, the back of an HVAC closet. So:

- **Reads** come from the local Drift database first, then the API in the background. Most screens render instantly even on cold start.
- **Writes** queue in `OfflineQueue` and replay when connectivity returns.
- **Idempotency keys** are minted at enqueue time. A re-sent in-flight queue entry hits the API's `request_idempotency` table and collapses server-side.
- **Conflict UI**: when an offline edit collides with a server-side edit (409), the offending entry is parked in `sync_conflicts`. The Settings → Sync Conflicts screen shows local vs server side-by-side and lets the user pick a winner.
- **Failed sync banner** on the dashboard shows the count of failed entries with a "Retry All" action.

The offline path is also the demo-mode path: a developer toggle (5-tap on the version label in About) replaces all data with local fixtures and disables network calls.

---

## 10. Things HavenKeep is not

To keep the product focused, here is what HavenKeep deliberately does NOT do:

- **It is not a smart-home dashboard.** No HomeKit, no Matter, no thermostat readings.
- **It is not a home-inventory app for insurance.** Some overlap (we have photos and receipts), but we don't generate insurance-specific reports or integrate with policy providers. (Yet — it's a roadmap candidate.)
- **It is not a marketplace.** We don't sell appliances, repairs, or services. We refer to manufacturers/retailers via affiliate-tracked links where appropriate.
- **It is not a budget tracker.** We track purchase price for warranty value, not for spending categorisation.
- **It is not a CRM for partners.** We give partners gift + commission tooling. Their full client relationship lives in their existing CRM.
- **It is not for business assets.** B2B asset management is a fundamentally different product. Free + Premium + Partner is the entire surface; there is no Enterprise tier.

---

## 11. Roadmap (deferred, not committed)

These ideas are on the marketing site's `/roadmap` page. They live in product backlog, not the codebase:

- **Insurance-ready reports** — generate a one-page PDF for a homeowner's insurance agent listing every appliance with serial number, purchase date, and replacement value.
- **Group homes** — a household with two adults sharing one HavenKeep account. Currently a user is one person; a "household" abstraction would let both spouses contribute items without sharing one login.
- **Warranty marketplace** — quote + purchase extended warranties directly from the app for items where the user's manufacturer warranty is about to expire. Heavy compliance lift; not yet started.
- **Smart maintenance** — pull weather + filter-replacement data from manufacturer APIs to predict when service is actually needed (not just scheduled).
- **Family sharing** — read-only access for a spouse / aging parent / contractor.

None of the above is built. Don't promise them in customer conversations.
