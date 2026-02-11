# 🚀 HavenKeep Production Deployment Guide

## Overview

This guide covers deploying the complete HavenKeep MVP (Option A features) to production.

**Features Included:**
1. ✅ Warranty Claims Tracking + ROI Display
2. ✅ Email Receipt Scanner (Gmail/Outlook OAuth + AI)
3. ✅ Enhanced Dashboard with Health Score
4. ✅ Stats/Analytics API
5. 🚧 Smart Notifications (coming next)
6. 🚧 Realtor Gift Flow (coming next)

---

## Prerequisites

### 1. Environment Setup

```bash
# Node.js & Dependencies
node --version  # Should be v18+ or v20+
npm --version   # Should be v9+

# Database
# PostgreSQL 15+ (DigitalOcean Managed Database recommended)

# Services Required
# - DigitalOcean Spaces (S3-compatible storage)
# - Stripe Account
# - OpenAI API Account
# - Google Cloud Console (for Gmail OAuth)
# - Microsoft Azure (for Outlook OAuth)
# - Firebase (for push notifications)
```

### 2. Required API Keys & Credentials

Create a `.env` file in `apps/api/`:

```env
# Database
DATABASE_URL=postgresql://user:password@host:25060/havenkeep?sslmode=require

# JWT
JWT_SECRET=your-super-secret-jwt-key-min-32-chars
JWT_REFRESH_SECRET=your-refresh-token-secret-min-32-chars

# Storage (DigitalOcean Spaces)
DO_SPACES_ENDPOINT=nyc3.digitaloceanspaces.com
DO_SPACES_BUCKET=havenkeep-prod
DO_SPACES_REGION=nyc3
DO_SPACES_ACCESS_KEY=your-access-key
DO_SPACES_SECRET_KEY=your-secret-key

# Stripe
STRIPE_SECRET_KEY=sk_live_...
STRIPE_PUBLISHABLE_KEY=pk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...

# OpenAI (for email receipt extraction)
OPENAI_API_KEY=sk-...

# Google OAuth (Gmail scanning)
GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your-client-secret
GOOGLE_REDIRECT_URI=https://api.havenkeep.com/api/v1/auth/google/callback

# Microsoft OAuth (Outlook scanning)
MICROSOFT_CLIENT_ID=your-client-id
MICROSOFT_CLIENT_SECRET=your-client-secret
MICROSOFT_REDIRECT_URI=https://api.havenkeep.com/api/v1/auth/microsoft/callback

# Email (SendGrid)
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USER=apikey
SMTP_PASSWORD=SG....
FROM_EMAIL=noreply@havenkeep.com
FROM_NAME=HavenKeep

# CORS
CORS_ORIGINS=https://havenkeep.com,https://app.havenkeep.com,https://partner.havenkeep.com

# Environment
NODE_ENV=production
PORT=3000
```

---

## Step 1: Database Migration

### A. Backup Current Database

```bash
# Connect to your database
pg_dump -h your-db-host -U doadmin -d havenkeep > backup_$(date +%Y%m%d).sql
```

### B. Run Migration

```bash
cd apps/api

# Install dependencies
npm install

# Install additional dependencies for new features
npm install googleapis axios

# Run migration
npm run migrate

# Or manually:
psql -h your-db-host -U doadmin -d havenkeep < src/db/migrations/002_enhanced_features.sql
```

### C. Verify Migration

```bash
psql -h your-db-host -U doadmin -d havenkeep

# Check new tables exist
\dt

# Should see:
# - warranty_claims
# - maintenance_schedules
# - maintenance_history
# - email_scans
# - partners
# - partner_gifts
# - partner_commissions
# - warranty_purchases
# - user_analytics
# - notification_templates
# - notification_history
# - savings_feed

# Check functions
\df

# Should see:
# - calculate_health_score
# - get_dashboard_stats
```

---

## Step 2: API Deployment

### Option A: DigitalOcean App Platform (Recommended)

#### 1. Create App

```bash
# In DigitalOcean Console:
# 1. Go to App Platform
# 2. Create App
# 3. Connect GitHub repo
# 4. Select apps/api as source directory
```

#### 2. Configure Build Settings

```yaml
# .do/app.yaml (create in project root)
name: havenkeep-api
region: nyc
services:
  - name: api
    source_dir: apps/api
    environment_slug: node-js
    build_command: npm run build
    run_command: npm start
    http_port: 3000
    instance_count: 2
    instance_size_slug: professional-xs
    envs:
      - key: NODE_ENV
        value: production
      - key: DATABASE_URL
        type: SECRET
        value: ${db.DATABASE_URL}
      - key: JWT_SECRET
        type: SECRET
      - key: OPENAI_API_KEY
        type: SECRET
      # ... add all other env vars

databases:
  - name: db
    engine: PG
    version: "15"
    production: true
    cluster_name: havenkeep-db-cluster
```

#### 3. Deploy

```bash
# Push to main branch triggers automatic deployment
git push origin main

# Or use doctl CLI
doctl apps create --spec .do/app.yaml
```

### Option B: Docker + DigitalOcean Droplet

```bash
# Build Docker image
cd apps/api
docker build -t havenkeep-api:latest .

# Push to registry
docker tag havenkeep-api:latest registry.digitalocean.com/havenkeep/api:latest
docker push registry.digitalocean.com/havenkeep/api:latest

# On droplet:
docker pull registry.digitalocean.com/havenkeep/api:latest
docker run -d \
  --name havenkeep-api \
  --env-file .env.production \
  -p 3000:3000 \
  --restart unless-stopped \
  registry.digitalocean.com/havenkeep/api:latest
```

---

## Step 3: Mobile App Deployment

### A. Update API Endpoint

```dart
// apps/mobile/lib/core/config/environment_config.dart
class EnvironmentConfig {
  static const String apiBaseUrl = 'https://api.havenkeep.com';
  // ... rest of config
}
```

### B. Build & Deploy iOS

```bash
cd apps/mobile

# Update version
# Edit pubspec.yaml: version: 1.1.0+2

# Build iOS
flutter build ios --release

# Open Xcode
open ios/Runner.xcworkspace

# In Xcode:
# 1. Product > Archive
# 2. Distribute App
# 3. Upload to App Store
# 4. Submit for review
```

### C. Build & Deploy Android

```bash
# Build Android App Bundle
flutter build appbundle --release

# Upload to Google Play Console
# 1. Go to Google Play Console
# 2. Select HavenKeep
# 3. Production > Create new release
# 4. Upload build/app/outputs/bundle/release/app-release.aab
# 5. Add release notes
# 6. Review and rollout
```

---

## Step 4: Partner Dashboard Deployment

### Option A: Vercel (Recommended)

```bash
cd apps/partner-dashboard

# Install Vercel CLI
npm install -g vercel

# Deploy
vercel --prod

# Or connect GitHub repo in Vercel dashboard
# Auto-deploys on push to main
```

### Option B: DigitalOcean App Platform

```yaml
# Add to .do/app.yaml
  - name: partner-dashboard
    source_dir: apps/partner-dashboard
    environment_slug: node-js
    build_command: npm run build
    run_command: npm start
    http_port: 3000
    envs:
      - key: NEXT_PUBLIC_API_URL
        value: https://api.havenkeep.com
      - key: NODE_ENV
        value: production
```

---

## Step 5: Configuration & Setup

### A. Google OAuth (Gmail Scanning)

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create new project "HavenKeep Production"
3. Enable Gmail API
4. Create OAuth 2.0 credentials:
   - Application type: Web application
   - Authorized redirect URIs:
     - `https://api.havenkeep.com/api/v1/auth/google/callback`
     - `https://app.havenkeep.com/oauth/google`
   - Scopes: `gmail.readonly`
5. Copy Client ID and Client Secret to .env

### B. Microsoft OAuth (Outlook Scanning)

1. Go to [Azure Portal](https://portal.azure.com)
2. Azure Active Directory > App registrations
3. New registration:
   - Name: HavenKeep Production
   - Redirect URI: `https://api.havenkeep.com/api/v1/auth/microsoft/callback`
4. API permissions:
   - Microsoft Graph > Mail.Read
5. Certificates & secrets > New client secret
6. Copy Client ID and Secret to .env

### C. OpenAI API

1. Go to [OpenAI Platform](https://platform.openai.com)
2. Create API key
3. Set spending limits ($50/month recommended)
4. Add to .env

### D. Stripe

1. Go to [Stripe Dashboard](https://dashboard.stripe.com)
2. Switch to Production mode
3. Get API keys from Developers > API keys
4. Set up webhooks:
   - Endpoint: `https://api.havenkeep.com/api/v1/webhooks/stripe`
   - Events:
     - `customer.subscription.created`
     - `customer.subscription.updated`
     - `customer.subscription.deleted`
     - `invoice.payment_succeeded`
     - `invoice.payment_failed`
5. Copy webhook secret to .env

---

## Step 6: Post-Deployment Verification

### A. Health Checks

```bash
# API health
curl https://api.havenkeep.com/health
# Expected: {"status":"ok","uptime":...}

# Database connection
curl https://api.havenkeep.com/health/db
# Expected: {"status":"ok","database":"connected"}
```

### B. Test New Endpoints

```bash
# Get access token first
TOKEN="your-jwt-token"

# Test warranty claims
curl -H "Authorization: Bearer $TOKEN" \
  https://api.havenkeep.com/api/v1/warranty-claims

# Test dashboard stats
curl -H "Authorization: Bearer $TOKEN" \
  https://api.havenkeep.com/api/v1/stats/dashboard

# Test health score
curl -H "Authorization: Bearer $TOKEN" \
  https://api.havenkeep.com/api/v1/stats/health-score
```

### C. Test Email Scanner (Manual)

```bash
# Initiate scan
curl -X POST https://api.havenkeep.com/api/v1/email-scanner/scan \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "gmail",
    "access_token": "test-token",
    "date_range_start": "2024-01-01"
  }'

# Check scan status
curl -H "Authorization: Bearer $TOKEN" \
  https://api.havenkeep.com/api/v1/email-scanner/scans/{scan_id}
```

---

## Step 7: Monitoring & Alerts

### A. Setup Monitoring Stack

```bash
# Already configured in docker-compose.yml:
# - Promtail (log collector)
# - Loki (log aggregation)
# - Grafana (visualization)

# Deploy monitoring stack
cd monitoring
docker-compose up -d
```

### B. Configure Alerts

```yaml
# alerts/rules.yml
groups:
  - name: havenkeep_alerts
    interval: 1m
    rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.05
        annotations:
          summary: "High error rate detected"

      - alert: SlowResponseTime
        expr: http_request_duration_seconds{quantile="0.95"} > 2
        annotations:
          summary: "API response time > 2s"

      - alert: DatabaseDown
        expr: up{job="postgres"} == 0
        annotations:
          summary: "Database is down"
```

### C. Setup Error Tracking (Optional but Recommended)

```bash
# Sentry
npm install @sentry/node

# In apps/api/src/index.ts
import * as Sentry from '@sentry/node';

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: 'production',
  tracesSampleRate: 0.1,
});
```

---

## Step 8: Performance Optimization

### A. Database Indexes

```sql
-- Verify critical indexes exist
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('items', 'warranty_claims', 'user_analytics')
ORDER BY tablename, indexname;

-- Add composite indexes for common queries
CREATE INDEX CONCURRENTLY idx_items_user_warranty
  ON items(user_id, warranty_end_date)
  WHERE is_archived = FALSE;

CREATE INDEX CONCURRENTLY idx_warranty_claims_user_date
  ON warranty_claims(user_id, claim_date DESC);
```

### B. API Response Caching

```typescript
// apps/api/src/middleware/cache.ts
import { Request, Response, NextFunction } from 'express';
import Redis from 'ioredis';

const redis = new Redis(process.env.REDIS_URL);

export const cache = (ttl: number) => {
  return async (req: Request, res: Response, next: NextFunction) => {
    const key = `cache:${req.user?.id}:${req.path}`;

    const cached = await redis.get(key);
    if (cached) {
      return res.json(JSON.parse(cached));
    }

    const originalSend = res.json.bind(res);
    res.json = (data: any) => {
      redis.setex(key, ttl, JSON.stringify(data));
      return originalSend(data);
    };

    next();
  };
};

// Usage:
// router.get('/stats/dashboard', cache(60), getDashboard);
```

### C. Connection Pooling

```typescript
// Already configured in apps/api/src/db/index.ts
// Verify pool settings:
const pool = new Pool({
  connectionString: config.database.url,
  max: 20,  // Maximum connections
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});
```

---

## Step 9: Security Hardening

### A. Rate Limiting

```typescript
// Already implemented in apps/api/src/middleware/rateLimiter.ts
// Verify settings:
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // Limit each IP to 100 requests per windowMs
  message: 'Too many requests, please try again later.',
});
```

### B. SSL/TLS

```bash
# DigitalOcean App Platform: Automatic
# Let's Encrypt SSL certificates auto-renewed

# For custom domains:
# 1. Add CNAME record: api.havenkeep.com -> your-app.ondigitalocean.app
# 2. In App Platform settings, add custom domain
# 3. SSL certificate auto-provisioned
```

### C. Security Headers

```typescript
// Already implemented with Helmet
// Verify in apps/api/src/index.ts:
app.use(helmet({
  contentSecurityPolicy: { ... },
  hsts: { maxAge: 31536000, includeSubDomains: true },
}));
```

---

## Step 10: Rollback Plan

### Database Rollback

```sql
-- Create rollback script
-- apps/api/src/db/migrations/002_rollback.sql

BEGIN;

-- Drop new tables in reverse order
DROP TABLE IF EXISTS savings_feed CASCADE;
DROP TABLE IF EXISTS notification_history CASCADE;
DROP TABLE IF EXISTS notification_templates CASCADE;
DROP TABLE IF EXISTS user_analytics CASCADE;
DROP TABLE IF EXISTS warranty_purchases CASCADE;
DROP TABLE IF EXISTS partner_commissions CASCADE;
DROP TABLE IF EXISTS partner_gifts CASCADE;
DROP TABLE IF EXISTS partners CASCADE;
DROP TABLE IF EXISTS email_scans CASCADE;
DROP TABLE IF EXISTS maintenance_history CASCADE;
DROP TABLE IF EXISTS maintenance_schedules CASCADE;
DROP TABLE IF EXISTS warranty_claims CASCADE;

-- Drop functions
DROP FUNCTION IF EXISTS calculate_health_score(UUID);
DROP FUNCTION IF EXISTS get_dashboard_stats(UUID);

-- Drop enums
DROP TYPE IF EXISTS notification_type;
DROP TYPE IF EXISTS warranty_purchase_status;
DROP TYPE IF EXISTS commission_type;
DROP TYPE IF EXISTS commission_status;
DROP TYPE IF EXISTS gift_status;
DROP TYPE IF EXISTS partner_tier;
DROP TYPE IF EXISTS partner_type_enum;
DROP TYPE IF EXISTS email_scan_status;

-- Remove columns from items table
ALTER TABLE items
  DROP COLUMN IF EXISTS estimated_repair_cost,
  DROP COLUMN IF EXISTS expected_lifespan_years,
  DROP COLUMN IF EXISTS installation_date,
  DROP COLUMN IF EXISTS last_maintenance_date,
  DROP COLUMN IF EXISTS next_maintenance_due;

COMMIT;
```

### Application Rollback

```bash
# If deployment fails, rollback to previous version

# DigitalOcean App Platform:
# 1. Go to App > Settings > Deployments
# 2. Select previous successful deployment
# 3. Click "Redeploy"

# Docker:
docker pull registry.digitalocean.com/havenkeep/api:previous-tag
docker stop havenkeep-api
docker rm havenkeep-api
docker run -d --name havenkeep-api ... api:previous-tag
```

---

## Step 11: Launch Checklist

### Pre-Launch

- [ ] Database migration completed successfully
- [ ] All environment variables configured
- [ ] API deployed and responding
- [ ] Mobile apps submitted and approved
- [ ] Partner dashboard deployed
- [ ] OAuth providers configured (Google, Microsoft)
- [ ] OpenAI API key with spending limits
- [ ] Stripe webhooks configured
- [ ] Monitoring stack running
- [ ] Backup strategy in place
- [ ] Load testing completed
- [ ] Security audit completed

### Day 1

- [ ] Monitor error rates (should be <1%)
- [ ] Check API response times (p95 <500ms)
- [ ] Verify email scanning works end-to-end
- [ ] Test warranty claim creation
- [ ] Verify health score calculation
- [ ] Monitor database connections
- [ ] Check log aggregation

### Week 1

- [ ] Review user analytics
- [ ] Check email scan success rate (target >70%)
- [ ] Monitor OpenAI API costs
- [ ] Review Stripe transactions
- [ ] Check mobile app crash rates (<1%)
- [ ] Gather user feedback
- [ ] Plan iteration based on data

---

## Support & Troubleshooting

### Common Issues

**1. Email scanning fails**
```bash
# Check OpenAI API key
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY"

# Check OAuth tokens are valid
# Google: https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=TOKEN
# Microsoft: https://graph.microsoft.com/v1.0/me
```

**2. High API latency**
```sql
-- Check slow queries
SELECT query, mean_exec_time, calls
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;

-- Add missing indexes
```

**3. Database connection errors**
```bash
# Check connection pool
SELECT count(*) FROM pg_stat_activity
WHERE datname = 'havenkeep';

# Should be < max_connections
```

---

## Cost Estimation

### Monthly Costs (1,000 active users)

| Service | Cost | Notes |
|---------|------|-------|
| DigitalOcean App Platform (API) | $12-24 | 2x Professional XS instances |
| DigitalOcean Database | $15-30 | Basic PostgreSQL cluster |
| DigitalOcean Spaces | $5 | 250GB storage |
| Vercel (Partner Dashboard) | $0-20 | Free tier or Pro |
| OpenAI API | $10-50 | ~1,000 email scans/month |
| Stripe | 2.9% + $0.30 | Per transaction |
| **Total** | **$42-129/mo** | + transaction fees |

**Scaling:**
- At 10,000 users: ~$200-400/mo
- At 100,000 users: ~$1,500-3,000/mo

---

## Next Steps

After successful deployment:

1. **Monitor for 48 hours** - Watch error rates, response times, user adoption
2. **Gather user feedback** - Email scanner success rate, dashboard usage
3. **Iterate on features** - Implement smart notifications next
4. **A/B test messaging** - Optimize health score gamification
5. **Partner outreach** - Start realtor program pilot

---

**Deployment Status:** ✅ Ready for Production
**Last Updated:** 2026-02-11
**Version:** 2.0.0 (MVP - Option A)
