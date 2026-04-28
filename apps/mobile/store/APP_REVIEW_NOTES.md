# App Review Notes — HavenKeep

These notes are for Apple App Review (App Store Connect → App Review Information → Notes) and Google Play Review (Play Console → Test on real devices). Copy-paste the relevant section into each console.

---

## 🔑 Demo Account Credentials

```
Email:    appreview@havenkeep.com
Password: <set when seeding via APP_REVIEW_PASSWORD env var>
```

The account is provisioned with the Premium entitlement so reviewers can exercise gated features (unlimited items, email-receipt scanner, multi-home, marketplace, priority claim support) without going through a sandbox subscription flow.

It starts on a populated dashboard: one home with 8 items across categories (refrigerator, dishwasher, HVAC, washer, TV, computer, microwave, lawn mower), one active warranty claim, one settled claim with a $450 saved-amount, and a maintenance schedule with two upcoming tasks.

To rotate the password, re-run the seed against production with a new `APP_REVIEW_PASSWORD` value. The seed lives in `apps/api/src/db/seed.ts`; the production version of it provisions the App Review account specifically.

---

## 📋 What HavenKeep Is

HavenKeep is a personal warranty manager for homeowners and renters. It tracks every appliance, electronic, and big-ticket purchase covered by a warranty, reminds users before warranties expire, and helps them file claims when something breaks.

The app is **not** a financial product, not insurance, not a marketplace operator — we don't underwrite, sell, or service warranties. We surface what's already in the box (or in the user's email inbox) and help them act on it before it's too late.

---

## 🗺️ How to Navigate (5-Minute Tour)

1. **Sign in** with the demo credentials above.
2. **Dashboard** loads with savings tally, items needing attention, and recent activity.
3. **Bottom navigation:**
   - **Home** — dashboard, total savings, items needing attention
   - **Items** — full library across rooms; tap any to see warranty terms, attached docs, claim history
   - **Add (+)** — manual entry, camera receipt scan, or "Import from email"
   - **Search** — search by item name, brand, room
   - **Settings** — account, notification preferences, multi-home, delete account, sign out

---

## 🧪 Critical Flows to Test

### Item library + warranty detail
Bottom nav → **Items**. Tap the "Refrigerator (Whirlpool WRF555SDFZ)" entry.
- Warranty terms (purchase date, warranty end date, type)
- Attached receipt + warranty card images
- Claim history
- Maintenance log with last-cleaned-coils date

### Receipt scanner (camera or image import)
**Add (+) → Scan Receipt**.
- Reviewer can use the seeded demo image at `assets/images/receipts/demo-receipt.png` from the device photo library
- HavenKeep extracts product name, store, price, and warranty period
- Re-running the same scan returns the cached response (no second OpenAI charge — `Idempotency-Key` enforced server-side)

### Email receipt import (Premium feature)
**Add (+) → Import from Email**.
- Reviewer connects Gmail or Outlook with read-only OAuth scope
- HavenKeep queries trusted retailer senders only (Amazon, Best Buy, Home Depot, etc. — list in `apps/api/src/services/email-scanner.service.ts`)
- Mid-scan **Cancel** button works: aborts and refunds the user's daily quota
- Disconnect any time: Settings → Connected Accounts → Disconnect. Tokens are deleted server-side.
- Low-confidence matches go to a **Review** queue; user approves or rejects each before it's added.

### Warranty reminder
Settings → Notification Preferences. Toggle "Warranty reminders". Toggle the "First reminder" interval (default 30 days before expiry).

### Filing a warranty claim
Items → "Refrigerator (Whirlpool)" → **File Claim**.
- Enter repair cost, amount saved, optional notes
- Status flow: filed → in_review → approved → settled → closed
- Reviewer can advance the demo claim through any single transition

### Account Deletion (required by both stores)
Settings → **Delete Account**. Confirms via password.
- Soft-deletes the user with a 30-day cooling-off window
- During cooling-off, signing back in restores the account verbatim
- After 30 days, a server cron permanently purges all rows
- Web fallback (Play Store policy): https://havenkeep.com/legal/delete-account

---

## 🔒 Privacy & Safety

- **No advertising, no third-party tracking, no data sales.** `NSPrivacyTracking=false` in the manifest. No IDFA, no ad networks.
- **Local data encryption** via SQLCipher (AES-256) on a per-user database file. Switching accounts opens a new encrypted file.
- **Email-receipt scanning is opt-in and read-only.** OAuth tokens are encrypted at rest with our own KMS key (separate from JWT secret); disconnecting deletes them. Only retailer senders are queried — we do not read personal correspondence.
- **OpenAI is configured for zero-data-retention.** Receipt images and email bodies are sent for OCR / extraction; the response is stored, the original payload is discarded. Documented in our DPA.
- **Account deletion** is in-app one-tap with a 30-day cooling-off recovery window, then permanent purge.

Privacy policy: https://havenkeep.com/legal/privacy
Terms: https://havenkeep.com/legal/terms
Cookies: https://havenkeep.com/cookies
Security: https://havenkeep.com/security
Account deletion (web): https://havenkeep.com/legal/delete-account
Support: https://havenkeep.com/support

---

## ⚠️ Disclosures (relevant to App Review)

- **No HealthKit / Health Connect integration** — HavenKeep does not read or write health data
- **No location access** — the app does not request or use any location API
- **Camera + Photos** — used for in-app receipt and warranty card capture; permissions strings explain the use
- **Microphone access** — not requested
- **Contacts access** — not requested
- **Push notifications are optional** — declining at the prompt does not break any flow; reminders fall back to email if the user has email-notifications enabled
- **In-App Purchases** — HavenKeep Premium subscription via RevenueCat (App Store / Play Billing). Monthly + annual SKUs.
- **Sign in with Apple** — implemented per App Store guideline 4.8 (offered alongside Google Sign-In)
- **Export Compliance** — uses standard HTTPS/TLS only and SQLCipher (AES-256) for at-rest local encryption. Exempt under §740.17(b)(1)(iv). Already declared via `ITSAppUsesNonExemptEncryption=false`.
- **Background modes** — Remote notifications only (APNs). No background fetch, no background location.

---

## 🤝 Third-Party Services

| Service | Purpose | Data Shared |
|---|---|---|
| **Firebase Auth** (not used) | — | — (HavenKeep uses its own JWT auth, not Firebase Auth) |
| **Firebase Cloud Messaging** | Push notifications | FCM token + delivery payloads (item name + warranty expiry) |
| **Firebase Crashlytics** | Crash reporting | Crash traces with install-id (NOT user-id) |
| **RevenueCat** | Subscription entitlement management | User's HavenKeep UUID (as `app_user_id`) + subscription state. No card data. |
| **OpenAI** | OCR for receipt scans + email-receipt extraction | Receipt image bytes / email body content. Zero-retention configured. |
| **Apple / Google Pay** | Subscription billing | Payment info (handled by the platform — HavenKeep never sees card numbers) |
| **MinIO / S3** | Document storage | User-uploaded receipts, warranty cards, manuals. Encrypted at rest. |

---

## 📞 Support & Contact for App Review Team

- **Email:** support@havenkeep.com
- **Response SLA:** within 1 business day during App Review

If you encounter an issue that blocks review, please email and reference "App Store / Play Store Review" in the subject line so it routes correctly.

---

## 🐛 Known Quirks (not bugs, just to save time)

- **Demo account is provisioned in our production database** specifically for App Review. It carries an `is_app_review` server-side flag that grants the Premium entitlement at the auth middleware level (no RevenueCat subscription is created or charged). This is the only difference from a normal user account — every other code path runs identically.
- **First login may take 2–3 seconds** while the dashboard hydrates from the per-user encrypted SQLite cache. This is normal cold-cache behavior.
- **Receipt scanner has a per-user daily cap** (set in `config.receipt.dailyCallCap`) to prevent runaway OpenAI spend. The demo account's cap is raised so reviewers can exercise the flow end-to-end without hitting it.
- **Email scanner requires Gmail or Outlook OAuth** — Apple reviewers commonly skip this flow because it asks for a Google login, which Apple's review accounts can't always perform. The flow is exercised on Google Play review with a real Gmail account; on App Store review you can verify the entry-point UI without completing the OAuth handshake.
- **Universal Links** — `havenkeep.com/gift/<code>` and `/referral/<code>` should open the app on iOS. The AASA file at `https://havenkeep.com/.well-known/apple-app-site-association` is signed with Apple Team ID `N3RF2GHS99` and bundle ID `app.havenkeep.mobile`. If reviewer's device hasn't installed the app via TestFlight, the link falls back to the marketing site.
- **Time-zone display** uses the device's local time zone for warranty-expiry strings; the underlying date math runs in UTC server-side.
