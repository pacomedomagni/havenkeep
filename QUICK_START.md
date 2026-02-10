# HavenKeep - Quick Start Guide

## 🚀 Deploy to DigitalOcean in 30 Minutes

### Step 1: Create Database (5 min)
```bash
1. Sign up at digitalocean.com ($200 free credit!)
2. Databases → Create Database → PostgreSQL 15
3. Basic (1GB) - $15/month
4. Save connection URL
```

### Step 2: Setup Schema (3 min)
```bash
psql "postgresql://USER:PASS@HOST:25060/havenkeep?sslmode=require" \
  < apps/api/src/db/schema.sql
```

### Step 3: Create Spaces (3 min)
```bash
1. Spaces → Create Space → havenkeep
2. API → Generate Spaces Keys
3. Save key + secret
```

### Step 4: Deploy API (10 min)
```bash
1. Apps → Create App → Connect GitHub
2. Source: /apps/api
3. Add environment variables:
   NODE_ENV=production
   DATABASE_URL=postgresql://...
   JWT_SECRET=<random-32-chars>
   REFRESH_TOKEN_SECRET=<random-32-chars>
   DO_SPACES_KEY=...
   DO_SPACES_SECRET=...
4. Deploy!
```

### Step 5: Create Admin (2 min)
```bash
psql "postgresql://..." -c \
  "UPDATE users SET is_admin = TRUE WHERE email = 'you@email.com';"
```

### Step 6: Test (2 min)
```bash
curl https://your-app.ondigitalocean.app/health
# {"status":"ok"}
```

## ✅ Done!

**Cost**: $26/month  
**Time**: 30 minutes  
**What you get**:
- Production API
- Managed PostgreSQL
- S3-compatible storage
- Automatic SSL
- Daily backups

## 📱 Update Mobile App (5 min)

```dart
// apps/mobile/lib/core/config/api_config.dart
class ApiConfig {
  static const String baseUrl = 'https://api.havenkeep.com';
}
```

Remove Supabase:
```bash
# pubspec.yaml - delete supabase_flutter
flutter pub get
```

## 💻 Update Admin Dashboard (5 min)

```bash
cd apps/partner-dashboard
npm uninstall @supabase/supabase-js @supabase/ssr
npm install axios

# Update API URL in .env.local
NEXT_PUBLIC_API_URL=https://api.havenkeep.com
```

## 📚 Full Guides

- **Deployment**: `DIGITALOCEAN_DEPLOYMENT.md`
- **API Docs**: `apps/api/README.md`
- **Migration**: `SUPABASE_TO_DIGITALOCEAN_MIGRATION.md`

## 💰 Cost

| Service | Cost |
|---------|------|
| App Platform (API) | $5/mo |
| PostgreSQL (1GB) | $15/mo |
| Spaces (250GB) | $5/mo |
| **Total** | **$26/mo** |

## 🆘 Need Help?

```bash
# Check API logs
doctl apps logs <app-id>

# Test health
curl https://api.havenkeep.com/health

# Connect to database
psql "postgresql://..."
```

## 🎉 You're Ready!

Deploy now: See `DIGITALOCEAN_DEPLOYMENT.md`
