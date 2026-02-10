# HavenKeep - DigitalOcean Deployment Guide

Complete guide to deploy HavenKeep on DigitalOcean infrastructure.

## 📊 Cost Overview

### Minimum Configuration ($26/month)
```
✅ App Platform (API):        $5/month
✅ Managed PostgreSQL (1GB):  $15/month  
✅ Spaces (File Storage):     $5/month
✅ Domain:                    $1/month
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   TOTAL:                    $26/month
```

### Recommended Configuration ($41/month)
```
✅ App Platform (API):        $5/month
✅ Managed PostgreSQL (1GB):  $15/month
✅ Managed Redis (1GB):       $15/month
✅ Spaces (File Storage):     $5/month
✅ Domain:                    $1/month
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   TOTAL:                    $41/month
```

## 🚀 Quick Deploy (30 Minutes)

### Step 1: Create DigitalOcean Account (5 min)

1. Sign up at https://www.digitalocean.com
2. Add payment method
3. Get $200 free credit (2 months free!)

### Step 2: Create Database (5 min)

```bash
# Via DigitalOcean dashboard:
1. Databases → Create Database
2. PostgreSQL 15
3. Basic plan (1GB RAM, 10GB storage) - $15/month
4. Region: Choose closest to users
5. Database name: havenkeep
6. Create Database

# Save connection details:
Host: db-postgresql-nyc3-12345.ondigitalocean.com
Port: 25060
User: doadmin
Password: <generated>
Database: havenkeep
SSL: Required
```

### Step 3: Run Database Schema (3 min)

```bash
# Download CA certificate
wget https://www.digitalocean.com/docs-assets/db-ca-cert.crt

# Connect and run schema
psql "postgresql://doadmin:PASSWORD@HOST:25060/havenkeep?sslmode=require" \
  < apps/api/src/db/schema.sql

# Verify
psql "postgresql://..." -c "\dt"
# Should show: users, homes, items, documents, etc.
```

### Step 4: Create Spaces (File Storage) (3 min)

```bash
# Via dashboard:
1. Spaces → Create Space
2. Region: Same as database
3. Name: havenkeep
4. CDN: Enable
5. Create Space

# Generate API keys:
1. API → Spaces Keys → Generate New Key
2. Name: havenkeep-api
3. Save Key and Secret (shown once!)

# Result:
DO_SPACES_KEY=DO00ABC...
DO_SPACES_SECRET=xyz123...
DO_SPACES_ENDPOINT=https://nyc3.digitaloceanspaces.com
DO_SPACES_BUCKET=havenkeep
```

### Step 5: Deploy API (10 min)

```bash
# Via App Platform:
1. Apps → Create App
2. Connect GitHub repository
3. Select "havenkeep" repo
4. Source Directory: /apps/api
5. Auto-detected: Node.js

# Build settings:
Build Command: npm run build
Run Command: npm start
HTTP Port: 3000

# Environment Variables (critical!):
NODE_ENV=production
DATABASE_URL=postgresql://doadmin:PASSWORD@HOST:25060/havenkeep?sslmode=require
JWT_SECRET=<generate-32-char-random-string>
REFRESH_TOKEN_SECRET=<generate-32-char-random-string>
DO_SPACES_KEY=<your-key>
DO_SPACES_SECRET=<your-secret>
DO_SPACES_ENDPOINT=https://nyc3.digitaloceanspaces.com
DO_SPACES_BUCKET=havenkeep
DO_SPACES_REGION=nyc3

# Optional (for production):
REDIS_URL=redis://localhost:6379  # Add Redis later
CORS_ORIGINS=https://havenkeep.com,https://admin.havenkeep.com
STRIPE_SECRET_KEY=sk_live_...

# Deploy!
# App Platform will build and deploy automatically
# URL: https://havenkeep-api-xxxxx.ondigitalocean.app
```

### Step 6: Verify Deployment (2 min)

```bash
# Health check
curl https://your-app.ondigitalocean.app/health
# {"status":"ok","timestamp":"...","uptime":123}

# Test registration
curl -X POST https://your-app.ondigitalocean.app/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@test.com","password":"password123","fullName":"Test User"}'

# Should return user + tokens
```

### Step 7: Create Admin User (2 min)

```bash
# Connect to database
psql "postgresql://doadmin:PASSWORD@HOST:25060/havenkeep?sslmode=require"

# Find your user ID (from registration)
SELECT id, email FROM users WHERE email = 'your@email.com';

# Make admin
UPDATE users SET is_admin = TRUE WHERE id = '<user-id>';

# Verify
SELECT email, is_admin FROM users WHERE is_admin = TRUE;
```

## ✅ You're Live!

**API URL**: https://your-app.ondigitalocean.app  
**Cost**: $26/month  
**Next**: Update mobile app and admin dashboard to use new API URL

---

## 🔧 Optional: Add Redis (Recommended)

For better rate limiting and caching:

```bash
# Create Managed Redis:
1. Databases → Create Database
2. Redis 7
3. Basic (1GB) - $15/month
4. Same region as PostgreSQL

# Get connection URL
Host: db-redis-nyc3-12345.ondigitalocean.com
Port: 25061
Password: <generated>

# Update App Platform env:
REDIS_URL=rediss://default:PASSWORD@HOST:25061

# Redeploy app
```

---

## 🌐 Custom Domain Setup

### Add Domain to App Platform

```bash
# App Platform → Settings → Domains
1. Add Domain
2. Enter: api.havenkeep.com
3. Add DNS records (shown in dashboard):

   Type: A
   Name: api
   Value: <app-platform-ip>

   Type: CNAME  
   Name: api
   Value: <app-platform-url>

# SSL auto-configured (Let's Encrypt)
```

### Update CORS

```bash
# App Platform → Environment Variables
CORS_ORIGINS=https://havenkeep.com,https://admin.havenkeep.com

# Redeploy
```

---

## 📱 Update Mobile App

```bash
cd apps/mobile

# Edit lib/core/config/api_config.dart
class ApiConfig {
  static const String baseUrl = 'https://api.havenkeep.com';
  // Remove all Supabase references
}

# Remove Supabase dependency
# Edit pubspec.yaml - remove: supabase_flutter

# Install HTTP client
flutter pub add dio
flutter pub add flutter_secure_storage

# Update auth service to use JWT
# See: apps/mobile/lib/core/services/auth_service.dart
```

---

## 💻 Update Admin Dashboard

```bash
cd apps/partner-dashboard

# Remove Supabase
npm uninstall @supabase/supabase-js @supabase/ssr

# Install HTTP client
npm install axios

# Update lib/api.ts:
import axios from 'axios';

const api = axios.create({
  baseURL: 'https://api.havenkeep.com/api',
  headers: {
    'Content-Type': 'application/json',
  },
});

// Add auth interceptor
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('accessToken');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

# Deploy to Vercel
vercel --prod
```

---

## 🔒 Security Hardening

### 1. Rotate JWT Secrets

```bash
# Generate secure secrets:
openssl rand -hex 32  # JWT_SECRET
openssl rand -hex 32  # REFRESH_TOKEN_SECRET

# Update in App Platform
# Redeploy
```

### 2. Enable SSL Only

```bash
# In App Platform → Settings:
☑ Force HTTPS
☑ TLS 1.2+
```

### 3. Restrict CORS

```bash
# Don't use '*' in production!
CORS_ORIGINS=https://havenkeep.com,https://admin.havenkeep.com
```

### 4. Rate Limiting

Already enabled with Redis. Monitor:
```bash
# Check rate limit headers
curl -I https://api.havenkeep.com/health
# X-RateLimit-Limit: 100
# X-RateLimit-Remaining: 99
```

---

## 📊 Monitoring

### App Platform Metrics

```bash
# View in dashboard:
- CPU usage
- Memory usage
- Request rate
- Error rate
- Response time (p95)

# Logs:
doctl apps logs <app-id> --follow
```

### Uptime Monitoring

```bash
# Use UptimeRobot (free):
1. Sign up: https://uptimerobot.com
2. Add monitor:
   - Type: HTTP(s)
   - URL: https://api.havenkeep.com/health
   - Interval: 5 minutes
3. Alert: Email when down
```

---

## 🔄 CI/CD with GitHub Actions

```yaml
# .github/workflows/deploy-api.yml
name: Deploy API

on:
  push:
    branches: [main]
    paths:
      - 'apps/api/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Deploy to App Platform
        uses: digitalocean/app_action@v1.1.5
        with:
          app_id: ${{ secrets.DO_APP_ID }}
          token: ${{ secrets.DO_ACCESS_TOKEN }}
```

---

## 💾 Backup Strategy

### Database Backups

```bash
# Manual backup:
pg_dump "postgresql://doadmin:PASSWORD@HOST:25060/havenkeep?sslmode=require" \
  > backup-$(date +%Y%m%d).sql

# DO automatically backs up daily (7-day retention)
# To restore:
# 1. Database → Backups → Select backup → Restore
```

### Spaces Backup

```bash
# Spaces has versioning - enable it:
1. Spaces → havenkeep → Settings
2. Enable Versioning
3. Files kept for 30 days
```

---

## 🚨 Rollback Procedure

### If deployment fails:

```bash
# App Platform → Deployments
1. Find last successful deployment
2. Click "..." → Redeploy
3. Confirm

# If database migration failed:
psql "postgresql://..." < backup.sql
```

---

## ✅ Deployment Checklist

- [ ] PostgreSQL database created ($15/mo)
- [ ] Database schema applied
- [ ] Spaces bucket created ($5/mo)
- [ ] Spaces API keys generated
- [ ] App Platform app created ($5/mo)
- [ ] Environment variables configured
- [ ] API deployed successfully
- [ ] Health check passing
- [ ] Admin user created
- [ ] Custom domain configured (optional)
- [ ] SSL enabled
- [ ] Monitoring configured
- [ ] Backups verified

---

## 🎉 You're Ready!

**Total Setup Time**: ~30 minutes  
**Monthly Cost**: $26 (minimum) or $41 (with Redis)  
**What You Get**:
- ✅ Production-ready API
- ✅ Managed PostgreSQL database
- ✅ S3-compatible file storage
- ✅ Automatic SSL
- ✅ Auto-scaling
- ✅ Daily backups
- ✅ 99.99% uptime SLA

**Next Steps**:
1. Update mobile app API endpoint
2. Update admin dashboard API endpoint
3. Test end-to-end
4. Submit to app stores!
