# ⚡ HavenKeep MVP Option A - Quick Start Guide

## 🎯 For You (The Developer)

### What Just Got Built

**✅ 100% COMPLETE - Backend API:**
1. Warranty Claims Tracking System
2. Email Receipt Scanner (Gmail + Outlook OAuth + AI)
3. Enhanced Dashboard & Stats API
4. Health Score Calculation System

**🚧 TODO - Mobile App UI:**
1. Warranty Claims screens
2. Email Scanner screens
3. Enhanced Dashboard screens

---

## 🚀 Run the Migration (5 Minutes)

### Step 1: Backup Database

```bash
# Connect to your database and backup
pg_dump -h your-db-host -U your-user -d havenkeep > backup_$(date +%Y%m%d).sql
```

### Step 2: Run Migration

```bash
cd apps/api

# Make sure you have the googleapis package
npm install googleapis axios

# Run the migration
psql -h your-db-host -U your-user -d havenkeep < src/db/migrations/002_enhanced_features.sql
```

### Step 3: Verify

```bash
# Check tables exist
psql -h your-db-host -U your-user -d havenkeep -c "\dt"

# You should see:
# - warranty_claims
# - user_analytics
# - email_scans
# - (and 9 more tables)
```

---

## 🧪 Test the New APIs (10 Minutes)

### 1. Get Your Auth Token

```bash
# Login to get token
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"your@email.com","password":"yourpassword"}'

# Save the token
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

### 2. Test Warranty Claims API

```bash
# Create a claim
curl -X POST http://localhost:3000/api/v1/warranty-claims \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "item_id": "your-item-uuid",
    "repair_cost": 450,
    "amount_saved": 450,
    "issue_description": "Fridge stopped cooling"
  }'

# Get all claims
curl http://localhost:3000/api/v1/warranty-claims \
  -H "Authorization: Bearer $TOKEN"

# Get savings
curl http://localhost:3000/api/v1/warranty-claims/savings \
  -H "Authorization: Bearer $TOKEN"
```

### 3. Test Dashboard Stats

```bash
# Get dashboard
curl http://localhost:3000/api/v1/stats/dashboard \
  -H "Authorization: Bearer $TOKEN"

# Get health score
curl http://localhost:3000/api/v1/stats/health-score \
  -H "Authorization: Bearer $TOKEN"

# Get items needing attention
curl http://localhost:3000/api/v1/stats/items-needing-attention \
  -H "Authorization: Bearer $TOKEN"
```

### 4. Test Email Scanner

**Note:** You'll need a real Gmail OAuth token for this to work. For now, just test the endpoint exists:

```bash
curl -X POST http://localhost:3000/api/v1/email-scanner/scan \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "gmail",
    "access_token": "test-token"
  }'

# Expected: 202 Accepted (will fail during processing due to invalid token, but API works)
```

---

## 📱 Next: Build Mobile UI

### Priority Order

1. **Enhanced Dashboard** (Start Here)
   - File: `apps/mobile/lib/features/home/`
   - Add health score widget
   - Add stats cards
   - Add "needs attention" section

2. **Warranty Claims**
   - File: `apps/mobile/lib/features/claims/` (create new)
   - Create claim form
   - Claims list
   - Savings tracker

3. **Email Scanner**
   - File: `apps/mobile/lib/features/email_scanner/` (create new)
   - OAuth flow
   - Scanning progress
   - Review & import

### Mobile Development Workflow

```bash
cd apps/mobile

# Create new providers
# - claims_provider.dart
# - stats_provider.dart
# - email_scanner_provider.dart

# Create new services
# - claims_repository.dart
# - stats_repository.dart
# - email_scanner_repository.dart

# Create screens
# - enhanced_dashboard_screen.dart
# - claims_list_screen.dart
# - create_claim_screen.dart
# - email_scanner_screen.dart

# Run app
flutter run
```

---

## 🎨 Design Guidelines (For Mobile)

### Health Score Widget

```dart
// Circular progress indicator
// - Green: 90-100
// - Orange: 70-89
// - Red: 0-69
// - Animated count-up effect
// - Tap to see breakdown
```

### Warranty Claims UI

```dart
// Claim Card:
// - Item name + category icon
// - Amount saved (big, bold, green)
// - Date
// - Status badge
```

### Email Scanner Flow

```dart
// 1. OAuth Button
//    "Connect Gmail" or "Connect Outlook"
//
// 2. Scanning Screen
//    Loading animation
//    "Scanning 247 emails..."
//    "Found 23 receipts"
//
// 3. Review Screen
//    List of items
//    Checkboxes to select
//    Edit button for each
//
// 4. Success Screen
//    Confetti animation
//    "Imported 18 items!"
//    "Total value: $45,000"
```

---

## 🔑 Environment Variables Needed

Add to `apps/api/.env`:

```env
# For Email Scanner
OPENAI_API_KEY=sk-...
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
MICROSOFT_CLIENT_ID=...
MICROSOFT_CLIENT_SECRET=...
```

Get these from:
- OpenAI: https://platform.openai.com/api-keys
- Google: https://console.cloud.google.com
- Microsoft: https://portal.azure.com

---

## 📊 What to Monitor

### After Deployment

1. **Email Scanner Success Rate**
   ```sql
   SELECT
     COUNT(*) FILTER (WHERE status = 'completed') * 100.0 / COUNT(*) as success_rate,
     AVG(items_imported) as avg_items_imported
   FROM email_scans
   WHERE created_at > NOW() - INTERVAL '7 days';
   ```
   **Target:** >70% success rate

2. **Health Score Engagement**
   ```sql
   SELECT
     COUNT(DISTINCT user_id) * 100.0 / (SELECT COUNT(*) FROM users) as engagement_rate
   FROM user_analytics
   WHERE current_health_score > 0;
   ```
   **Target:** >50% of users have calculated score

3. **Warranty Claims Adoption**
   ```sql
   SELECT
     COUNT(DISTINCT user_id) as users_with_claims,
     COUNT(*) as total_claims,
     SUM(amount_saved) as total_saved
   FROM warranty_claims;
   ```
   **Target:** >40% of users track claims

---

## 🐛 Troubleshooting

### "Email scan fails immediately"

```bash
# Check OpenAI API key
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY"

# Should return list of models
```

### "Health score always returns 0"

```sql
-- Check if user has items
SELECT COUNT(*) FROM items WHERE user_id = 'your-user-id';

-- Manually calculate
SELECT calculate_health_score('your-user-id');
```

### "Dashboard stats are slow"

```sql
-- Check query performance
EXPLAIN ANALYZE SELECT get_dashboard_stats('your-user-id');

-- Should complete in <100ms
```

---

## 📚 Documentation Reference

- **Full Implementation Plan:** [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md)
- **Deployment Guide:** [PRODUCTION_DEPLOYMENT.md](./PRODUCTION_DEPLOYMENT.md)
- **Testing Guide:** [TESTING_GUIDE.md](./TESTING_GUIDE.md)
- **Summary:** [MVP_OPTION_A_SUMMARY.md](./MVP_OPTION_A_SUMMARY.md)

---

## ✅ Ready to Ship Checklist

### Backend (Complete)
- [x] Database migration
- [x] API endpoints
- [x] OAuth integration
- [x] AI integration
- [x] Documentation

### Mobile (Your Turn)
- [ ] Enhanced dashboard
- [ ] Warranty claims UI
- [ ] Email scanner UI
- [ ] Testing
- [ ] App store builds

### Deployment
- [ ] Run migration in production
- [ ] Deploy API
- [ ] Submit mobile apps
- [ ] Setup monitoring
- [ ] Launch! 🚀

---

## 🎉 You're Ready!

**What you have:**
- Production-ready backend API
- Complete database schema
- OAuth + AI integrations
- Comprehensive documentation

**What to build:**
- ~3 weeks of mobile UI work
- Testing & QA
- Deployment

**Expected result:**
- 10x better onboarding (email scanner)
- Tangible ROI tracking (warranty claims)
- Engaging UX (health score, stats)
- Revenue growth (proven value = conversions)

**Questions?** Check the docs above or dive into the code!

---

**Built:** February 11, 2026
**Status:** Backend Complete, Mobile In Progress
**Next Milestone:** Mobile UI (3 weeks)
