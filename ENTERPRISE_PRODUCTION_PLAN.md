# HavenKeep: Enterprise Production Readiness Plan

**Goal**: Launch-ready SaaS platform with marketing site, admin dashboard, and production infrastructure

**Timeline**: 4-6 weeks
**Date**: 2026-02-09

---

## 🎯 Three Core Deliverables

### 1. Marketing Landing Page (SPA)
**Tech Stack**: Next.js 15 + Tailwind CSS + Framer Motion
**Purpose**: Convert visitors to signups
**Deliverables**:
- Hero section with value proposition
- Features showcase
- Pricing page (Free + Premium tiers)
- Trust signals (testimonials, stats)
- FAQ section
- Blog/Resources (SEO)
- Contact/Support

### 2. Admin Dashboard
**Tech Stack**: Partner Dashboard (existing Next.js app)
**Purpose**: Manage users, monitor system, analytics
**Deliverables**:
- User management (CRUD, suspend, delete)
- System analytics (signups, DAU, retention)
- Support ticket system
- Database admin tools
- Monitoring dashboards
- Feature flags management

### 3. Production Infrastructure
**Purpose**: Scalable, secure, monitored production deployment
**Deliverables**:
- CI/CD pipelines (GitHub Actions)
- Environment management (dev/staging/prod)
- Database migrations & backups
- Monitoring & alerting
- Security hardening
- Performance optimization
- Documentation

---

## 📦 Phase 1: Marketing Landing Page (Week 1-2)

### 1.1 Project Setup ✨ NEW
```bash
apps/marketing/
├── src/
│   ├── app/
│   │   ├── page.tsx                 # Homepage
│   │   ├── pricing/page.tsx
│   │   ├── features/page.tsx
│   │   ├── about/page.tsx
│   │   ├── blog/
│   │   │   ├── page.tsx
│   │   │   └── [slug]/page.tsx
│   │   └── contact/page.tsx
│   ├── components/
│   │   ├── Hero.tsx
│   │   ├── Features.tsx
│   │   ├── Pricing.tsx
│   │   ├── Testimonials.tsx
│   │   ├── FAQ.tsx
│   │   ├── CTA.tsx
│   │   └── Navigation.tsx
│   ├── lib/
│   │   └── analytics.ts
│   └── styles/
│       └── globals.css
├── public/
│   ├── images/
│   ├── screenshots/
│   └── logo.svg
├── next.config.js
├── tailwind.config.ts
└── package.json
```

**Key Pages**:
1. **Homepage** (`/`)
   - Hero: "Never lose a warranty again"
   - Value props: Track, Organize, Claim
   - Screenshot showcase
   - Social proof (10,000+ items tracked)
   - CTA: "Start Free" + "Try Demo"

2. **Features** (`/features`)
   - Barcode scanning
   - Receipt OCR
   - Warranty reminders
   - Multi-device sync
   - Export capabilities
   - Premium features

3. **Pricing** (`/pricing`)
   - Free tier: 10 items, basic features
   - Premium: $4.99/mo, unlimited items, advanced features
   - Enterprise: Custom pricing
   - Feature comparison table
   - FAQ

4. **Blog** (`/blog`)
   - SEO-optimized articles
   - "How to organize warranties"
   - "Top 10 warranty tips"
   - Product updates

---

### 1.2 Tech Stack

**Framework**: Next.js 15 (App Router)
```json
{
  "dependencies": {
    "next": "^15.0.0",
    "react": "^19.0.0",
    "react-dom": "^19.0.0",
    "tailwindcss": "^3.4.0",
    "framer-motion": "^11.0.0",
    "lucide-react": "^0.300.0",
    "@radix-ui/react-accordion": "^1.1.0",
    "@vercel/analytics": "^1.0.0",
    "next-themes": "^0.2.0"
  }
}
```

**Styling**: Tailwind CSS + shadcn/ui components
**Animations**: Framer Motion (subtle, utility-first)
**Analytics**: Vercel Analytics + Plausible (privacy-friendly)
**Forms**: React Hook Form + Zod validation
**Email**: Resend for transactional emails

---

### 1.3 Key Components

#### Hero Section
```tsx
<Hero
  title="Your warranties. Protected."
  subtitle="Track all your warranties in one place. Never lose a receipt again."
  primaryCTA="Start Free"
  secondaryCTA="Try Interactive Demo"
  screenshot="/screenshots/dashboard.png"
  stats={[
    { label: "Items Tracked", value: "10,000+" },
    { label: "Active Users", value: "1,200+" },
    { label: "Money Saved", value: "$500K+" }
  ]}
/>
```

#### Features Grid
```tsx
<Features
  items={[
    {
      icon: <Scan />,
      title: "Instant Barcode Scanning",
      description: "Add items in seconds with our smart scanner"
    },
    {
      icon: <Receipt />,
      title: "Receipt OCR",
      description: "Snap a photo, we'll extract the details"
    },
    {
      icon: <Bell />,
      title: "Smart Reminders",
      description: "Never miss an expiration date"
    }
  ]}
/>
```

#### Pricing Cards
```tsx
<Pricing
  tiers={[
    {
      name: "Free",
      price: "$0",
      features: [
        "Up to 10 items",
        "Basic warranty tracking",
        "Mobile app",
        "Email support"
      ],
      cta: "Get Started"
    },
    {
      name: "Premium",
      price: "$4.99/mo",
      features: [
        "Unlimited items",
        "Receipt scanning",
        "Priority reminders",
        "Export to PDF",
        "Priority support"
      ],
      cta: "Start Free Trial",
      popular: true
    }
  ]}
/>
```

---

## 📦 Phase 2: Admin Dashboard (Week 2-3)

### 2.1 Extend Partner Dashboard

**Current State**:
```
apps/partner-dashboard/
├── src/
│   └── app/
│       └── (Needs implementation)
```

**New Structure**:
```
apps/partner-dashboard/
├── src/
│   ├── app/
│   │   ├── (auth)/
│   │   │   ├── login/page.tsx
│   │   │   └── layout.tsx
│   │   ├── (dashboard)/
│   │   │   ├── page.tsx              # Overview
│   │   │   ├── users/
│   │   │   │   ├── page.tsx          # User list
│   │   │   │   └── [id]/page.tsx     # User detail
│   │   │   ├── analytics/page.tsx
│   │   │   ├── support/page.tsx
│   │   │   ├── settings/page.tsx
│   │   │   └── layout.tsx
│   │   └── api/
│   │       ├── users/route.ts
│   │       ├── analytics/route.ts
│   │       └── support/route.ts
│   ├── components/
│   │   ├── UserTable.tsx
│   │   ├── AnalyticsChart.tsx
│   │   ├── StatsCard.tsx
│   │   └── Sidebar.tsx
│   ├── lib/
│   │   ├── supabase-admin.ts        # Admin client
│   │   └── permissions.ts
│   └── middleware.ts
├── tailwind.config.ts
└── package.json
```

---

### 2.2 Core Admin Features

#### 2.2.1 User Management
**Features**:
- List all users (paginated, searchable)
- View user details (items, activity, billing)
- Suspend/delete users
- Reset passwords
- View user sessions
- Impersonate user (for support)

**UI**:
```tsx
<UserTable
  columns={[
    "Email",
    "Name",
    "Items Count",
    "Premium Status",
    "Signup Date",
    "Last Active",
    "Actions"
  ]}
  actions={[
    { label: "View", icon: Eye },
    { label: "Suspend", icon: Ban, destructive: true },
    { label: "Delete", icon: Trash, destructive: true }
  ]}
/>
```

**Backend** (Supabase RLS):
```sql
-- Admin role check
CREATE POLICY "Admins can view all users"
ON auth.users
FOR SELECT
USING (
  auth.jwt() ->> 'role' = 'admin'
);
```

---

#### 2.2.2 Analytics Dashboard
**Metrics**:
- **User Metrics**:
  - Total users (all time)
  - Daily Active Users (DAU)
  - Monthly Active Users (MAU)
  - Retention rate (D1, D7, D30)
  - Churn rate

- **Item Metrics**:
  - Total items tracked
  - Items per user (avg)
  - Most popular categories
  - Warranty health distribution

- **Revenue Metrics**:
  - MRR (Monthly Recurring Revenue)
  - ARR (Annual Recurring Revenue)
  - Premium conversion rate
  - LTV (Lifetime Value)

**Charts**:
```tsx
<AnalyticsDashboard
  charts={[
    {
      type: "line",
      title: "Daily Signups",
      data: dailySignups,
      timeRange: "30d"
    },
    {
      type: "bar",
      title: "Items by Category",
      data: categoryDistribution
    },
    {
      type: "pie",
      title: "Free vs Premium",
      data: userTiers
    }
  ]}
/>
```

**Tech**: Recharts or Tremor for charts

---

#### 2.2.3 Support Ticket System
**Features**:
- View all support tickets
- Respond to tickets
- Assign to team members
- Close/resolve tickets
- Search & filter

**Integration**: Intercom or custom Supabase table

---

#### 2.2.4 Feature Flags
**Purpose**: Control feature rollout
```tsx
<FeatureFlagManager
  flags={[
    {
      name: "receipt_scanning",
      enabled: true,
      rollout: 100,
      description: "OCR receipt scanning"
    },
    {
      name: "barcode_lookup",
      enabled: true,
      rollout: 50,
      description: "Barcode product lookup"
    }
  ]}
/>
```

**Backend**: LaunchDarkly or custom table in Supabase

---

## 📦 Phase 3: Production Infrastructure (Week 3-4)

### 3.1 CI/CD Pipeline (GitHub Actions)

**Workflows**:
```
.github/workflows/
├── mobile-ci.yml          # Flutter tests, build
├── web-ci.yml             # Next.js tests, build
├── deploy-staging.yml     # Auto-deploy to staging
├── deploy-production.yml  # Manual production deploy
└── database-migrate.yml   # Run migrations
```

**Example**: `mobile-ci.yml`
```yaml
name: Mobile CI

on:
  push:
    branches: [main, develop]
    paths:
      - 'apps/mobile/**'
      - 'packages/shared_models/**'

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.19.0'

      - name: Install dependencies
        run: |
          cd apps/mobile
          flutter pub get

      - name: Run tests
        run: |
          cd apps/mobile
          flutter test --coverage

      - name: Check coverage
        run: |
          cd apps/mobile
          # Fail if coverage < 80%
          ./scripts/check_coverage.sh 80

  build:
    runs-on: macos-latest
    needs: test
    steps:
      - name: Build iOS
        run: flutter build ios --release --no-codesign

      - name: Build Android
        run: flutter build apk --release
```

---

### 3.2 Environment Management

**Environments**:
1. **Development** - Local development
2. **Staging** - Pre-production testing
3. **Production** - Live users

**Supabase Projects**:
```
havenkeep-dev        → Staging
havenkeep-prod       → Production
```

**Environment Variables**:
```bash
# .env.staging
SUPABASE_URL=https://staging.havenkeep.com
SUPABASE_ANON_KEY=...
STRIPE_PUBLISHABLE_KEY=pk_test_...
SENTRY_DSN=...
LOKI_URL=...

# .env.production
SUPABASE_URL=https://api.havenkeep.com
SUPABASE_ANON_KEY=...
STRIPE_PUBLISHABLE_KEY=pk_live_...
SENTRY_DSN=...
LOKI_URL=...
```

---

### 3.3 Database Management

#### Migrations
**Tool**: Supabase Migrations
```bash
supabase/migrations/
├── 20240101_initial_schema.sql
├── 20240115_add_premium_features.sql
├── 20240201_add_analytics_tables.sql
└── 20240209_add_admin_roles.sql
```

**Migration Script**:
```bash
#!/bin/bash
# scripts/migrate.sh

ENV=$1 # dev, staging, prod

if [ "$ENV" = "prod" ]; then
  echo "⚠️  Running PRODUCTION migration"
  read -p "Are you sure? (yes/no): " confirm
  if [ "$confirm" != "yes" ]; then
    exit 1
  fi
fi

supabase db push --project-ref $PROJECT_REF
```

#### Backups
**Strategy**:
- **Automated**: Daily backups (Supabase built-in)
- **Manual**: Before each migration
- **Retention**: 30 days for daily, 1 year for weekly
- **Testing**: Monthly restore tests

---

### 3.4 Monitoring & Alerting

#### Application Monitoring
**Tool**: Sentry (already integrated)
- Error tracking
- Performance monitoring
- Release tracking

#### Infrastructure Monitoring
**Tool**: Grafana + Loki (already set up)
- Log aggregation
- Query performance
- API latency
- User activity

#### Uptime Monitoring
**Tool**: UptimeRobot or Better Uptime
- API endpoint checks (every 5 min)
- Mobile app status
- Database health
- Alert channels: Email, Slack

**Alerts**:
```yaml
alerts:
  - name: API Down
    condition: uptime < 99%
    channels: [email, slack]
    severity: critical

  - name: High Error Rate
    condition: error_rate > 5%
    channels: [email]
    severity: high

  - name: Slow Queries
    condition: avg_query_time > 500ms
    channels: [slack]
    severity: medium
```

---

### 3.5 Security Hardening

#### 3.5.1 Authentication & Authorization
- [x] Supabase Auth (already implemented)
- [ ] Rate limiting (Supabase Edge Functions)
- [ ] CAPTCHA on signup (Turnstile)
- [ ] 2FA (Supabase Auth)
- [ ] Session management (auto-logout)

#### 3.5.2 API Security
```typescript
// Rate limiting middleware
import { Ratelimit } from "@upstash/ratelimit"

const ratelimit = new Ratelimit({
  redis: redis,
  limiter: Ratelimit.slidingWindow(10, "10 s"),
})

export async function middleware(req: NextRequest) {
  const ip = req.ip ?? "127.0.0.1"
  const { success } = await ratelimit.limit(ip)

  if (!success) {
    return new Response("Rate limit exceeded", { status: 429 })
  }
}
```

#### 3.5.3 Data Security
- [x] Row Level Security (already implemented)
- [ ] Encryption at rest (Supabase default)
- [ ] Encryption in transit (HTTPS)
- [ ] PII anonymization in logs
- [ ] GDPR compliance (data export/delete)

---

### 3.6 Performance Optimization

#### Mobile App
- [ ] Image optimization (WebP, lazy loading)
- [ ] Bundle size reduction (<10 MB)
- [ ] Database query optimization (indexes)
- [ ] Offline caching strategy
- [ ] Network request batching

#### Web Apps
- [ ] Next.js Image optimization
- [ ] Code splitting
- [ ] CDN for static assets (Vercel)
- [ ] Database connection pooling
- [ ] API response caching

**Target Metrics**:
- Mobile app launch: <2 seconds
- Dashboard load: <1 second
- API response: <200ms (p95)
- Lighthouse score: >90

---

## 📦 Phase 4: Documentation & Launch Prep (Week 4)

### 4.1 Documentation

#### User Documentation
```
docs/user/
├── getting-started.md
├── adding-items.md
├── warranty-tracking.md
├── premium-features.md
└── faq.md
```

#### Developer Documentation
```
docs/developer/
├── architecture.md
├── api-reference.md
├── database-schema.md
├── deployment.md
└── contributing.md
```

#### Operations Runbook
```
docs/ops/
├── deployment-checklist.md
├── incident-response.md
├── backup-restore.md
└── scaling-guide.md
```

---

### 4.2 Pre-Launch Checklist

#### Technical
- [ ] All tests passing (85%+ coverage)
- [ ] Staging environment matches production
- [ ] Database migrations tested
- [ ] Backup & restore tested
- [ ] Monitoring & alerts configured
- [ ] Rate limiting enabled
- [ ] Security audit passed
- [ ] Performance benchmarks met

#### Business
- [ ] Pricing finalized
- [ ] Terms of Service
- [ ] Privacy Policy
- [ ] GDPR compliance
- [ ] App Store listings ready
- [ ] Marketing site live
- [ ] Support email configured
- [ ] Analytics tracking enabled

#### Marketing
- [ ] Landing page live
- [ ] Blog posts ready
- [ ] Social media accounts
- [ ] Press kit prepared
- [ ] Launch email drafted
- [ ] Product Hunt submission

---

## 🚀 Launch Strategy

### Soft Launch (Week 5)
- Internal beta testing (team + friends)
- Fix critical bugs
- Gather feedback
- Refine onboarding

### Public Launch (Week 6)
- **Day 1**: Launch on Product Hunt
- **Day 2-3**: Twitter/X announcement
- **Day 4-7**: Reach out to tech bloggers
- **Ongoing**: Content marketing, SEO

---

## 📊 Success Metrics

### Week 1-4 (Build)
- [ ] Marketing site deployed
- [ ] Admin dashboard functional
- [ ] Production infrastructure ready
- [ ] Mobile app in TestFlight/Beta

### Month 1 (Launch)
- Target: 500 signups
- Target: 50 premium conversions
- Target: 99.9% uptime
- Target: <5% churn

### Month 3 (Growth)
- Target: 2,000 users
- Target: 200 premium subscribers
- Target: $1,000 MRR
- Target: 4.5+ App Store rating

### Month 6 (Scale)
- Target: 10,000 users
- Target: 1,000 premium subscribers
- Target: $5,000 MRR
- Target: Product-market fit

---

## 🛠️ Tech Stack Summary

| Component | Technology |
|-----------|------------|
| **Mobile App** | Flutter 3.19 |
| **Marketing Site** | Next.js 15 + Tailwind |
| **Admin Dashboard** | Next.js 15 + Shadcn/UI |
| **Backend** | Supabase (PostgreSQL, Auth, Storage) |
| **Edge Functions** | Supabase Edge Functions |
| **Monitoring** | Sentry + Grafana + Loki |
| **Analytics** | Vercel Analytics + Plausible |
| **Email** | Resend |
| **Payments** | Stripe (already integrated) |
| **Hosting** | Vercel (web), App Store + Play Store (mobile) |
| **CI/CD** | GitHub Actions |
| **Domain** | havenkeep.com |

---

## 💰 Estimated Costs (Monthly)

| Service | Cost |
|---------|------|
| Supabase (Pro) | $25 |
| Vercel (Pro) | $20 |
| Sentry (Team) | $26 |
| Plausible (optional) | $9 |
| Domain + SSL | $2 |
| **Total** | **~$82/mo** |

**Scales with users** (additional costs for storage, bandwidth)

---

## ✅ Next Steps

Want me to start implementing?

1. **Marketing Landing Page** (High priority)
   - Set up Next.js project
   - Build hero, features, pricing pages
   - Deploy to Vercel

2. **Admin Dashboard** (High priority)
   - Extend partner-dashboard
   - User management
   - Analytics views

3. **Production Infrastructure** (Critical)
   - GitHub Actions CI/CD
   - Environment setup
   - Monitoring configuration

**Which should I start with?**
