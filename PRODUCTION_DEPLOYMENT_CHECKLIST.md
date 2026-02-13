# HavenKeep — Production Deployment Checklist

Use this checklist before every production deployment.

---

## Pre-Deployment

- [ ] All code merged to `main` and CI passing
- [ ] Staging environment tested and verified
- [ ] Database migrations reviewed and tested on staging
- [ ] Environment variables updated in `.env.production`
- [ ] Secrets generated via `./scripts/generate-secrets.sh`
- [ ] No `CHANGE_ME` placeholders in env file
- [ ] Backup current production database: `./scripts/backup-database.sh`

## Security

- [ ] JWT_SECRET is at least 32 characters, randomly generated
- [ ] REFRESH_TOKEN_SECRET is different from JWT_SECRET
- [ ] Database password is 16+ characters, no dev defaults
- [ ] Redis password is set
- [ ] MinIO credentials are production-grade
- [ ] CORS_ORIGINS only lists production domains
- [ ] SSL certificates are valid and not expiring soon
- [ ] Stripe is using **live keys** (sk_live_...), not test keys

## Infrastructure

- [ ] PostgreSQL healthcheck passing
- [ ] Redis healthcheck passing
- [ ] MinIO healthcheck passing
- [ ] API `/health/detailed` returns all checks OK
- [ ] Nginx SSL config uses TLS 1.2+ only
- [ ] Rate limiting is configured
- [ ] Loki + Promtail are running and collecting logs

## Deployment

```bash
# 1. Pull latest code
git pull origin main

# 2. Run migrations (if any)
docker compose -f docker-compose.production.yml --profile migrate run --rm migrate

# 3. Build and deploy
docker compose -f docker-compose.production.yml up -d --build

# 4. Verify health
curl -f https://api.havenkeep.com/health/detailed
```

## Post-Deployment

- [ ] Health endpoints return 200
- [ ] Mobile app connects successfully
- [ ] Partner dashboard loads and authenticates
- [ ] Webhook endpoints are reachable
- [ ] Logs flowing to Loki
- [ ] Monitor for 15 minutes after deploy

## Rollback Plan

```bash
# Stop current deployment
docker compose -f docker-compose.production.yml down

# Restore database from backup (if schema changed)
gunzip -c backups/havenkeep_backup_YYYYMMDD_HHMMSS.sql.gz | psql "$DATABASE_URL"

# Redeploy previous version
git checkout <previous-tag>
docker compose -f docker-compose.production.yml up -d --build
```
