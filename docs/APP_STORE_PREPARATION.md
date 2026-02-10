# HavenKeep App Store Preparation Guide

Complete guide for submitting HavenKeep to iOS App Store and Google Play Store.

## 📱 iOS App Store

### Prerequisites
- [ ] Apple Developer account ($99/year)
- [ ] Xcode installed (latest version)
- [ ] iOS signing certificates configured
- [ ] TestFlight tested with beta users

### App Store Listing

#### App Information
- **App Name**: HavenKeep
- **Subtitle**: Track Warranties & Never Lose Coverage
- **Category**: Productivity
- **Secondary Category**: Finance
- **Bundle ID**: com.havenkeep.mobile

#### App Description
```
Never miss a warranty again. HavenKeep helps you track all your product warranties in one beautifully simple app.

✨ KEY FEATURES
• Track unlimited warranties (Premium)
• Scan barcodes for instant product details
• Upload receipts and warranty cards  
• Get reminded before warranties expire
• Organize items by room or property
• Export all data as PDF
• Works offline, syncs when online

💰 VALUE PROTECTED
Track the total value of items under warranty. See at a glance how much coverage you have.

🏠 PERFECT FOR
• Homeowners managing appliances
• Landlords tracking rental properties  
• Anyone with expensive electronics
• Peace of mind for major purchases

📊 SMART INSIGHTS
• See warranty health at a glance
• Get notified 90, 60, 30, and 14 days before expiration
• Track active vs expired warranties
• Filter by category, room, or status

🔒 PRIVACY FIRST
• Your data is encrypted and secure
• No ads, no tracking
• Export and delete your data anytime

FREE PLAN
• Track up to 10 items
• Basic warranty tracking
• Email reminders

PREMIUM ($4.99/month)
• Unlimited items
• Barcode scanning
• Receipt OCR
• PDF export
• Priority support

Start protecting your warranties today!
```

#### Keywords (100 characters max)
```
warranty,tracker,receipt,scanner,homeowner,landlord,appliance,reminder,organize,protection
```

#### Screenshots (6.7" iPhone 15 Pro Max)

**Screenshot 1: Dashboard**
- Title: "Track All Your Warranties"
- Shows: Dashboard with 6 items, $12,450 total value, 87% health

**Screenshot 2: Item List**
- Title: "Organize by Room or Category"
- Shows: Kitchen appliances list with expiration dates

**Screenshot 3: Item Detail**
- Title: "Complete Product Information"
- Shows: Refrigerator detail with warranty info, documents

**Screenshot 4: Barcode Scan**
- Title: "Instant Product Lookup"
- Shows: Barcode scanning screen with product details

**Screenshot 5: Reminders**
- Title: "Never Miss an Expiration"
- Shows: Notification screen with upcoming expirations

**Screenshot 6: Value Dashboard**
- Title: "$12,450 Protected"
- Shows: Value breakdown and warranty health

#### App Preview Video (30 seconds)
**Script**:
1. (0-5s) Open app to dashboard - "Track all your warranties in one place"
2. (5-10s) Add item via barcode scan - "Scan barcodes for instant details"
3. (10-15s) Upload receipt - "Store receipts securely"
4. (15-20s) View item detail - "See everything at a glance"
5. (20-25s) Receive notification - "Get reminded before expiration"
6. (25-30s) Dashboard with value protected - "Peace of mind for your valuables"

### App Privacy Details

**Data Collection**:
- **Contact Info**: Email (for account)
- **Identifiers**: User ID (for app functionality)
- **Purchases**: Purchase history (for Premium subscription)
- **User Content**: Photos, receipts, product data (for warranty tracking)

**Data Linked to User**: All data above
**Data Not Collected**: Location, browsing history, search history

**Data Use**:
- App Functionality
- Product Personalization
- Analytics (anonymized)

### App Review Information

**Contact**: support@havenkeep.com
**Phone**: [Your phone number]

**Demo Account** (for App Review):
```
Email: demo@havenkeep.com
Password: AppReview2024!

Note: This account has 6 sample items pre-populated for testing.
```

**Notes for Review**:
```
HavenKeep is a warranty tracking app for homeowners and renters.

Test Features:
1. Browse existing items on dashboard
2. Add new item (Kitchen > Dishwasher)
3. Upload a photo (any image works for demo)
4. View item detail
5. Check warranty expiration date

Premium features (barcode scanning, receipt OCR) require subscription.
A free trial is available for testing.

Privacy: All user data is stored securely in Supabase with encryption.
No third-party tracking or advertising.
```

### Submission Checklist
- [ ] App version incremented (1.0.0 → 1.0.1 for updates)
- [ ] Build uploaded to App Store Connect
- [ ] Screenshots added (all sizes)
- [ ] App description written
- [ ] Keywords optimized
- [ ] Privacy details filled
- [ ] Demo account created
- [ ] Support URL added (https://havenkeep.com/support)
- [ ] Marketing URL added (https://havenkeep.com)
- [ ] Age rating set (4+)
- [ ] Content rights confirmed
- [ ] Export compliance: No encryption or self-declaration

### Build and Upload

```bash
cd apps/mobile

# Update version in pubspec.yaml
# version: 1.0.0+1

# Build iOS
flutter build ios --release --no-codesign

# Open in Xcode
open ios/Runner.xcworkspace

# In Xcode:
# 1. Select "Any iOS Device"
# 2. Product → Archive
# 3. Distribute App → App Store Connect
# 4. Upload
```

### TestFlight Beta Testing

1. Add external testers (up to 10,000)
2. Collect feedback
3. Iterate and fix bugs
4. Submit for review after 2-3 weeks of testing

---

## 🤖 Google Play Store

### Prerequisites
- [ ] Google Play Console account ($25 one-time)
- [ ] Signing key created
- [ ] Privacy policy URL live
- [ ] Terms of service URL live

### Play Store Listing

#### Store Listing
- **App Name**: HavenKeep
- **Short Description** (80 characters):
```
Track warranties and never lose coverage on your valuable products
```

- **Full Description** (4000 characters):
```
Never miss a warranty again! HavenKeep helps you track all your product warranties in one beautifully simple app.

✨ KEY FEATURES

📦 Track Everything
• Manage warranties for appliances, electronics, furniture, and more
• Organize by room, property, or category
• See warranty status at a glance (active, expiring, expired)

📸 Smart Scanning
• Barcode scanning for instant product details
• Receipt OCR to extract purchase information
• Upload photos of receipts and warranty cards

🔔 Smart Reminders
• Get notified 90, 60, 30, and 14 days before expiration
• Customize reminder preferences
• Never miss important warranty deadlines

💰 Value Protection
• See total value of items under warranty
• Track warranty health percentage
• Know exactly what's protected

🏠 Perfect For
• Homeowners managing appliance warranties
• Landlords tracking multiple properties
• Anyone with expensive electronics
• Peace of mind for major purchases

📊 Insights
• Dashboard showing active vs expired warranties
• Filter and search by category, room, or date
• Export data as PDF
• Works offline, syncs when online

🔒 Privacy & Security
• End-to-end encryption
• Secure cloud backup
• No ads or tracking
• Export and delete your data anytime

💎 FREE PLAN
• Track up to 10 items
• Basic warranty tracking
• Email reminders
• Document storage

⭐ PREMIUM ($4.99/month)
• Unlimited items
• Barcode scanning
• Receipt OCR
• PDF export
• Multi-property support
• Priority support

Start protecting your warranties today!

Privacy Policy: https://havenkeep.com/legal/privacy
Terms of Service: https://havenkeep.com/legal/terms
```

#### Graphics

**Icon**: 512x512 PNG, rounded corners
**Feature Graphic**: 1024x500 PNG
**Phone Screenshots**: 8 screenshots (1080x1920 minimum)
**Tablet Screenshots**: 4 screenshots (1200x1920 minimum)

### App Content

#### Privacy Policy URL
```
https://havenkeep.com/legal/privacy
```

#### Target Audience**
- Target age group: 18+
- No ads

#### Data Safety

**Data Shared**:
- Email address (for account)
- User ID (for app functionality)
- Product data (for warranty tracking)
- Receipts and photos (user-uploaded)

**Security Practices**:
- Data encrypted in transit (TLS)
- Data encrypted at rest (AES-256)
- Users can request data deletion
- Committed to Play Families Policy

**Data Retention**:
- Account data: Until user deletes account
- Backups: 30 days after deletion

### App Access

**Demo Account**:
```
Email: demo@havenkeep.com
Password: PlayStore2024!
```

**Instructions for Testing**:
1. Log in with demo account
2. View dashboard with sample items
3. Add new item manually
4. Upload a photo
5. View warranty expiration dates

### Build and Upload

```bash
cd apps/mobile

# Create signing key (first time only)
keytool -genkey -v -keystore ~/havenkeep-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias havenkeep

# Add to android/key.properties:
# storePassword=<password>
# keyPassword=<password>
# keyAlias=havenkeep
# storeFile=~/havenkeep-release.jks

# Build app bundle
flutter build appbundle --release

# Upload to Play Console
# File: build/app/outputs/bundle/release/app-release.aab
```

### Release Tracks

1. **Internal Testing**: Team only (immediate)
2. **Closed Testing**: Invited users (1-2 weeks)
3. **Open Testing**: Public beta (2-3 weeks)
4. **Production**: Full release (after open testing)

### Content Rating

**Questionnaire**:
- Violence: None
- Sexual content: None
- Profanity: None
- Controlled substances: None
- User-generated content: No
- Shares location: No
- Realistic gambling: No

**Expected Rating**: Everyone

---

## 📋 Post-Submission Checklist

### Both Stores
- [ ] App submitted for review
- [ ] Support email monitored (support@havenkeep.com)
- [ ] Crash reporting active (Sentry)
- [ ] Analytics tracking enabled
- [ ] Marketing site updated with store links
- [ ] Social media announcements prepared

### If Rejected
- [ ] Read rejection reason carefully
- [ ] Fix issues
- [ ] Respond to reviewer notes
- [ ] Resubmit with explanation

### After Approval
- [ ] Monitor crash reports
- [ ] Respond to reviews
- [ ] Track conversion funnel
- [ ] Plan feature updates

---

## 🚀 Launch Day Timeline

**T-7 Days**: Submit to both stores
**T-3 Days**: Approval (hopefully)
**T-0 (Launch)**:
- 9am: Announce on social media
- 10am: Email beta testers
- 12pm: Post on Product Hunt
- 2pm: Share on HackerNews
- 4pm: Monitor analytics

**T+1 Day**: Review first day metrics, respond to feedback

---

## ✅ App Store Submission Status

- [ ] iOS App Store - Submitted
- [ ] Google Play Store - Submitted
- [ ] Privacy Policy - Live
- [ ] Terms of Service - Live
- [ ] Support Page - Live
- [ ] Demo Accounts - Created
- [ ] Screenshots - Generated
- [ ] App Preview Video - Recorded (iOS)

**Ready to submit**: YES ✅
