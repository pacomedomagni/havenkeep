# Play Console — Paste-Ready Answers

Walk through every required section in https://play.google.com/console → HavenKeep → Policy → App content. The answers below match the actual app behavior (verified against the codebase).

If a section already shows a green check, skip it.

---

## Demo account credentials (for the "App access" section)

```
Email:    appreview@havenkeep.com
Password: <see ~/.secrets/havenkeep-appreview-password.txt on the dev laptop>
```

This account is provisioned with the Premium entitlement enabled server-side via the `is_app_review` flag (mirrors the `dev@havenkeep.com` seed in `apps/api/src/db/seed.ts` — pre-seeded items, homes, warranties, claims). Reviewers can exercise gated features (unlimited items, email scanner, multi-home, marketplace) without going through Play Billing sandbox. See [APP_REVIEW_NOTES.md](APP_REVIEW_NOTES.md) for the full reviewer walkthrough.

---

## A) Privacy policy

**URL:**
```
https://havenkeep.com/legal/privacy
```

(For staging review use: `https://havenkeep.kouakoudomagni.com/legal/privacy`.)

---

## B) App access

**Q: All or some functionality is restricted?**
→ **All or some functionality is restricted**

**Q: Provide instructions for testers**
```
1. Tap "Sign In" on the welcome screen.
2. Sign in with:
     Email:    appreview@havenkeep.com
     Password: <provided in App Review notes>
3. The account auto-completes onboarding and lands on the dashboard with a pre-seeded home, items, an active warranty, and a settled claim.

Premium features unlock automatically — this account has a server-side flag granting Premium, so no in-app purchase is required to test gated paths (unlimited items, email scanner, multi-home, marketplace, priority claim support).

Account deletion: Settings → Delete Account. The account is soft-deleted with a 30-day cooling-off window — fully reversible by signing back in within that window.

Web account-deletion (required by Play): https://havenkeep.com/legal/delete-account
```

---

## C) Ads

**Q: Does your app contain ads?**
→ **No, my app does not contain ads**

(Verified: no AdMob, no Unity Ads, no third-party ad SDKs in `apps/mobile/pubspec.yaml`.)

---

## D) Content rating (IARC questionnaire)

Walk through the form. Key answers:

| Question | Answer |
|---|---|
| Category | **Lifestyle** (or "Reference" if not offered) |
| Violence | None |
| Sexuality | None |
| Language | None |
| Controlled substance | None |
| Crude humor | None |
| Gambling | None |
| Horror/fear | None |
| Mature/suggestive themes | None |
| User-generated content (chat, posts) | **No** — items are private to the user; no community feed |
| Shares user location | **No** — HavenKeep does NOT use any location API |
| Personal info shared with users | **No** |
| Digital purchases | **Yes** (HavenKeep Premium subscription) |
| Internet connectivity required | Yes |

**Expected rating:** Everyone.

---

## E) Target audience and content

**Q: Target age groups**
→ **18 and over** (HavenKeep is a homeowner / renter tool — its user base is adults purchasing appliances and managing warranties)

**Q: Designed for Families?**
→ **No, this is a general audience app**

**Q: Appeals to children?**
→ **No**

---

## F) News app

**Q: Is this a news app?**
→ **No**

---

## G) COVID-19 contact-tracing and status apps

**Q: Is this a COVID-19 app?**
→ **No**

---

## H) Government apps

**Q: Is this a government app?**
→ **No**

---

## I) Financial features

**Q: Does your app contain financial features?**
→ **No**

(Subscription is via Google Play Billing — that's not a "financial feature" in Google's terms. Banking, lending, crypto, brokerage trigger this question. The marketplace surfaces third-party extended-warranty products but does not underwrite or process payments outside Play Billing.)

---

## J) Health apps

**Q: Does your app provide health-related content or features?**
→ **No** (HavenKeep is a productivity / lifestyle tool — it tracks warranties on home goods and surfaces maintenance reminders. It does not collect health data, integrate with Health Connect, or provide health advice.)

---

## K) Data safety form

This is the most extensive section. Drafted answers in [STORE_LISTING.md](STORE_LISTING.md) under "Google Play — Data Safety Form". Summary:

- **Email address** — collected, required, encrypted in transit, user can request deletion
- **Name** — collected, required, encrypted in transit, user can request deletion
- **User IDs** (server-side UUID) — collected, required, encrypted in transit
- **Photos** (item / receipt / warranty card images) — collected, optional, encrypted in transit
- **App activity** (item entries, claim filings, maintenance logs) — collected, required, encrypted in transit
- **Crash logs** (Firebase Crashlytics) — collected, optional, encrypted in transit
- **Purchase history** (subscription state only — not card numbers) — collected, required, encrypted in transit
- **Messages** (subject + sender + body of imported retailer emails) — collected, optional, **processed but not retained**: bodies hit OpenAI's vision API, the response (extracted item fields) is stored, the original body is discarded. User must explicitly connect Gmail / Outlook and can disconnect any time.
- **All data encrypted in transit** ✓ (TLS)
- **All data encrypted at rest** ✓ (SQLCipher on-device; encrypted disks server-side)
- **Users can request data deletion** ✓ (in-app one-tap with 30-day cooling-off, then permanent purge)

### Third-party data sharing — what to declare

| Recipient | What's shared | Why |
|---|---|---|
| **RevenueCat** | Subscription state (Premium / Free) and the user's HavenKeep UUID as RevenueCat `app_user_id` | Entitlement management. No card data. |
| **Firebase Cloud Messaging** | Push notification token + delivery payloads (item name + warranty expiry date in the message body) | Push notifications. Only after the user grants notification permission. |
| **OpenAI** | Receipt image bytes + extracted email body content (only when the user connects Gmail / Outlook or scans a receipt) | OCR / extraction. Configured for zero-data-retention; documented in our DPA. |
| **Apple / Google Pay** | Payment info | Subscription billing (handled by the platform, not HavenKeep). |
| **MinIO / S3** | User-uploaded receipts, warranty cards, photos | Document storage. Encrypted at rest. |

---

## L) Government apps + News + COVID

(All No. See sections F, G, H above.)

---

## M) App bundle requirements (Google Play 2026)

- **Target API level:** 35 (Android 15) — auto-met by Flutter ≥ 3.41.
- **Signed AAB** — release-signed via `apps/mobile/android/app/upload-keystore.jks`. The upload-key SHA-256 (`70:21:27:A4:…`) is wired into `apps/marketing/public/.well-known/assetlinks.json`. After Play takes over signing on first upload, copy Play's App-Signing SHA-256 from Play Console → App integrity → App signing key fingerprint and append it to `assetlinks.json` (the second slot is currently `REPLACE_WITH_PLAY_APP_SIGNING_SHA256`).
- **Release tracks** — Internal Testing → Closed Testing (if personal account, 14-day requirement) → Production.

---

## Testing track requirement (only for personal Play accounts)

**If your Play Console developer account is personal (created after 2023-11-13):** Google requires 14 consecutive days of closed testing with at least 12 opted-in testers before you can apply for production access.

**To set this up:**
1. Play Console → **Test → Closed testing → Create track**
2. Upload the AAB (release-signed)
3. Add 12 tester emails to the closed-testing list (a Google Group is easier to manage)
4. Send testers the opt-in URL Play generates
5. Wait 14 calendar days
6. Then **Test → Closed testing → Apply for production access**

**If your account is an organization:** No 14-day requirement. After completing all the App Content sections above and the Data Safety form, you can submit straight to production.

---

## Final order of operations to launch

1. ⬜ Build release AAB locally — `cd apps/mobile && flutter build appbundle --release`
2. ⬜ Upload AAB to **Internal Testing** in Play Console
3. ⬜ Once uploaded, copy the **Play App Signing SHA-256** from Play Console → App integrity → App signing key fingerprint and replace `REPLACE_WITH_PLAY_APP_SIGNING_SHA256` in `apps/marketing/public/.well-known/assetlinks.json`. Re-deploy marketing.
4. ⬜ Complete each "App content" section above (10-15 min total)
5. ⬜ Complete Data Safety form (15 min)
6. ⬜ Upload screenshots + feature graphic (1024×500) + 512×512 icon
7. ⬜ Paste store listing copy (short + full description) from [STORE_LISTING.md](STORE_LISTING.md)
8. ⬜ **(Personal accounts only)** Set up Closed testing + recruit 12 testers + wait 14 days
9. ⬜ **Production → Create release** — promote AAB from Internal/Closed to Production
10. ⬜ Wait 1–7 days for Google review
11. 🎉 Live on Play Store
