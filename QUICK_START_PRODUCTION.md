# HavenKeep — Quick Start Production Guide

Get HavenKeep running in production in 5 minutes.

---

## Prerequisites

- Docker & Docker Compose v2+
- A server with 2+ GB RAM (DigitalOcean Droplet recommended)
- Domain DNS pointing to your server IP
- Git access to this repository

## Steps

### 1. Clone & Configure

```bash
git clone git@github.com:pacomedomagni/havenkeep.git
cd havenkeep
```

### 2. Generate Secrets

```bash
./scripts/generate-secrets.sh
```

### 3. Create Environment File

```bash
cp .env.example .env.production
# Edit .env.production — fill in ALL values, remove CHANGE_ME placeholders
nano .env.production
```

**Critical values to set:**
- `POSTGRES_PASSWORD` — strong, 16+ chars
- `JWT_SECRET` / `REFRESH_TOKEN_SECRET` — `openssl rand -hex 32`
- `REDIS_PASSWORD` — strong password
- `MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY` — strong credentials
- `STRIPE_SECRET_KEY` — your live Stripe key
- `CORS_ORIGINS` — your production domains

### 4. SSL Certificates (First Time Only)

```bash
./scripts/deploy-staging.sh ssl-init
# Or for production:
# Update domains in the deploy script, then run ssl-init
```

### 5. Run Database Migrations

```bash
docker compose -f docker-compose.production.yml --profile migrate run --rm migrate
```

### 6. Deploy

```bash
docker compose -f docker-compose.production.yml up -d --build
```

### 7. Verify

```bash
# Check all services are running
docker compose -f docker-compose.production.yml ps

# Check API health
curl https://api.yourdomain.com/health/detailed

# Run the validation script
./scripts/validate-production-ready.sh
```

## Common Operations

```bash
# View logs
docker compose -f docker-compose.production.yml logs -f api

# Restart a service
docker compose -f docker-compose.production.yml restart api

# Backup database
./scripts/backup-database.sh

# Renew SSL
./scripts/deploy-staging.sh ssl-renew
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| API won't start | Check `docker logs havenkeep-api-prod` — likely missing env vars |
| 502 Bad Gateway | API container crashed — check logs, verify healthcheck |
| SSL errors | Re-run `ssl-init`, check cert paths in nginx.conf |
| DB connection refused | Verify postgres healthcheck, check DATABASE_URL |
| CORS errors | Update `CORS_ORIGINS` in .env to include your frontend domains |
