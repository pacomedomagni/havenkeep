# HavenKeep Deployment Guide

**Complete guide to deploying HavenKeep to production**

---

## 🎯 Overview

HavenKeep consists of 4 deployable components:
1. **Marketing Site** (Astro) → Cloudflare Pages
2. **Admin Dashboard** (Next.js) → Vercel
3. **Mobile App** (Flutter) → App Store + Play Store
4. **Backend** (Supabase) → Managed service

---

## 📋 Pre-Deployment Checklist

### 1. Accounts & Services
- [ ] Cloudflare account (marketing site)
- [ ] Vercel account (admin dashboard)
- [ ] Supabase account (backend)
- [ ] UptimeRobot account (monitoring)
- [ ] GitHub account (CI/CD)
- [ ] Apple Developer account (iOS)
- [ ] Google Play Console account (Android)

### 2. Environment Variables

Create `.env.production` in project root:
```bash
# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_service_key
SUPABASE_PROJECT_REF=your_project_ref

# Cloudflare
CLOUDFLARE_API_TOKEN=your_token

# Vercel
VERCEL_TOKEN=your_token

# Monitoring
SENTRY_DSN=https://your_sentry_dsn
LOKI_URL=https://your_loki_instance

# Stripe (Premium)
STRIPE_PUBLISHABLE_KEY=pk_live_...
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

### 3. DNS Configuration

Point your domain to deployment services:

**Cloudflare DNS** (if using Cloudflare):
```
Type: CNAME
Name: @
Target: havenkeep.pages.dev
Proxied: Yes

Type: CNAME
Name: www
Target: havenkeep.pages.dev
Proxied: Yes

Type: CNAME
Name: admin
Target: your-vercel-deployment.vercel.app
Proxied: Yes
```

---

## 🚀 Deployment Steps

### 1. Deploy Marketing Site (Cloudflare Pages)

**Option A: Automated (via GitHub)**
1. Push to `main` branch
2. GitHub Actions automatically builds and deploys
3. Check workflow status: github.com/your-org/havenkeep/actions

**Option B: Manual Deploy**
```bash
cd apps/marketing
npm install
npm run build
npx wrangler pages deploy dist --project-name=havenkeep --branch=main
```

**Verify**:
- Visit https://havenkeep.com
- Check Lighthouse score (should be 100/100)
- Test all links work

---

### 2. Deploy Admin Dashboard (Vercel)

**Option A: Automated**
1. Connect Vercel to GitHub repo
2. Configure environment variables in Vercel dashboard
3. Push to `main` triggers auto-deploy

**Option B: Manual**
```bash
cd apps/partner-dashboard
npm install

# Set environment variables
export NEXT_PUBLIC_SUPABASE_URL=your_url
export NEXT_PUBLIC_SUPABASE_ANON_KEY=your_key

# Deploy
npx vercel deploy --prod
```

**Configure Custom Domain** in Vercel:
- Add domain: admin.havenkeep.com
- Vercel auto-provisions SSL

**Verify**:
- Visit https://admin.havenkeep.com
- Test login with admin account
- Check user management works

---

### 3. Database Setup (Supabase)

**Create Production Project**:
1. Go to https://supabase.com/dashboard
2. Create new project: `havenkeep-prod`
3. Set strong database password
4. Note down: URL, anon key, service role key

**Run Migrations**:
```bash
# Install Supabase CLI
npm install -g supabase

# Login
supabase login

# Link to project
supabase link --project-ref your_project_ref

# Run migrations
supabase db push
```

**Verify**:
```bash
# Check tables exist
supabase db dump --schema public

# Test RLS policies
# Try accessing data as non-admin user
```

---

### 4. Mobile App Deployment

#### iOS (TestFlight → App Store)

**Prerequisites**:
- Apple Developer account ($99/year)
- Xcode installed
- iOS signing certificates

**Steps**:
```bash
cd apps/mobile

# Update version in pubspec.yaml
# version: 1.0.0+1

# Build iOS
flutter build ios --release

# Open Xcode
open ios/Runner.xcworkspace

# In Xcode:
# 1. Select "Any iOS Device"
# 2. Product → Archive
# 3. Distribute App → App Store Connect
# 4. Upload
```

**TestFlight**:
1. Go to App Store Connect
2. Add build to TestFlight
3. Add external testers
4. Submit for beta review

#### Android (Play Store)

**Prerequisites**:
- Google Play Console account ($25 one-time)
- Signing key

**Create Signing Key**:
```bash
keytool -genkey -v -keystore ~/havenkeep-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias havenkeep
```

**Configure Signing**:
Create `apps/mobile/android/key.properties`:
```
storePassword=your_store_password
keyPassword=your_key_password
keyAlias=havenkeep
storeFile=/path/to/havenkeep-key.jks
```

**Build & Upload**:
```bash
cd apps/mobile

# Build app bundle
flutter build appbundle --release

# Upload to Play Console
# (Use Play Console web interface)
```

---

## 🔧 GitHub Secrets Configuration

Add these secrets in GitHub repo settings:

```
Settings → Secrets and variables → Actions → New repository secret
```

**Required Secrets**:
- `CLOUDFLARE_API_TOKEN`
- `VERCEL_TOKEN`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_PROJECT_REF`
- `SUPABASE_ACCESS_TOKEN`

---

## 📊 Monitoring Setup

### 1. UptimeRobot

1. Create account: https://uptimerobot.com
2. Add monitors:
   - https://havenkeep.com (5 min interval)
   - https://admin.havenkeep.com (5 min interval)
   - Your Supabase API endpoint
3. Configure alerts:
   - Email: support@havenkeep.com
   - Slack: #alerts channel

### 2. Sentry (Error Tracking)

1. Create project: https://sentry.io
2. Get DSN from project settings
3. Add to `.env.production`
4. Verify errors are reported

### 3. Grafana + Loki (Logs)

**Option A: Grafana Cloud** (easier)
1. Sign up: https://grafana.com/products/cloud/
2. Create Loki data source
3. Import dashboard from `monitoring/grafana-dashboard.json`

**Option B: Self-hosted** (cheaper)
```bash
# Use Docker Compose
docker-compose -f monitoring/docker-compose.yml up -d
```

---

## ✅ Post-Deployment Verification

Run through this checklist after deployment:

### Marketing Site
- [ ] https://havenkeep.com loads
- [ ] All pages work (features, pricing, about)
- [ ] Signup link goes to correct URL
- [ ] Mobile responsive
- [ ] Lighthouse score > 90

### Admin Dashboard
- [ ] https://admin.havenkeep.com loads
- [ ] Can login with admin account
- [ ] Non-admin users blocked
- [ ] Can view user list
- [ ] Analytics load correctly

### Mobile App
- [ ] App opens without crashes
- [ ] Can create account
- [ ] Can add first item
- [ ] Celebration shows
- [ ] Offline mode works
- [ ] Push notifications work

### Backend
- [ ] Can sign up new user
- [ ] Can login
- [ ] RLS prevents unauthorized access
- [ ] Database backups enabled
- [ ] API responds < 200ms

### Monitoring
- [ ] UptimeRobot sending heartbeats
- [ ] Sentry receiving errors
- [ ] Grafana dashboards showing data
- [ ] Alerts configured and tested

---

## 🆘 Rollback Procedure

If deployment fails:

### Marketing Site
```bash
# Rollback to previous deployment in Cloudflare Pages dashboard
# OR re-deploy previous commit:
git checkout <previous-commit>
cd apps/marketing
npm run build
npx wrangler pages deploy dist
```

### Admin Dashboard
```bash
# Rollback in Vercel dashboard:
# Deployments → Previous deployment → Promote to Production
```

### Database
```bash
# Restore from backup
supabase db dump --file=backup.sql
psql -h db.your-project.supabase.co -U postgres -d postgres -f backups/backup-YYYYMMDD.sql
```

---

## 📞 Support Contacts

**Deployment Issues**:
- Cloudflare: https://dash.cloudflare.com/
- Vercel: https://vercel.com/support
- Supabase: https://supabase.com/support

**Monitoring**:
- UptimeRobot: support@uptimerobot.com
- Sentry: support@sentry.io

---

## 🎯 Launch Day Checklist

**T-1 Week**:
- [ ] All components deployed to staging
- [ ] Beta testing complete
- [ ] Critical bugs fixed
- [ ] Performance tested
- [ ] Security audit done

**T-1 Day**:
- [ ] Deploy to production
- [ ] Verify all systems operational
- [ ] Monitoring configured and working
- [ ] Support email set up
- [ ] Team briefed on launch plan

**Launch Day**:
- [ ] Marketing site live
- [ ] Mobile app in stores
- [ ] Product Hunt submission
- [ ] Social media announcements
- [ ] Monitor dashboards continuously
- [ ] Team on standby for issues

**T+1 Day**:
- [ ] Review metrics (signups, errors, uptime)
- [ ] Respond to user feedback
- [ ] Fix any critical bugs
- [ ] Send thank you to beta testers

---

**Good luck with your launch!** 🚀
