# HavenKeep API

Express.js REST API for HavenKeep warranty tracking app.

## Stack

- **Runtime**: Node.js 20+
- **Framework**: Express.js
- **Database**: PostgreSQL 15+
- **Auth**: JWT + bcrypt
- **File Storage**: DigitalOcean Spaces (S3-compatible)
- **Cache/Rate Limit**: Redis
- **Logging**: Pino
- **Security**: Helmet, CORS, rate limiting

## Quick Start

```bash
# Install dependencies
npm install

# Copy environment file
cp .env.example .env

# Edit .env with your credentials

# Run migrations
npm run db:migrate

# Start development server
npm run dev

# API runs on http://localhost:3000
```

## API Endpoints

### Authentication
```
POST   /api/auth/register      - Create account
POST   /api/auth/login         - Login
POST   /api/auth/refresh       - Refresh access token
POST   /api/auth/logout        - Logout
```

### Users
```
GET    /api/users/me           - Get current user
PUT    /api/users/me           - Update current user
```

### Homes
```
GET    /api/homes              - List user's homes
POST   /api/homes              - Create home
PUT    /api/homes/:id          - Update home
DELETE /api/homes/:id          - Delete home
```

### Items
```
GET    /api/items              - List items
GET    /api/items/:id          - Get item
POST   /api/items              - Create item
PUT    /api/items/:id          - Update item
DELETE /api/items/:id          - Delete item
```

### Documents
```
GET    /api/documents          - List documents
POST   /api/documents          - Upload document
DELETE /api/documents/:id      - Delete document
```

### Barcode (Premium)
```
POST   /api/barcode/lookup     - Lookup product by barcode
```

### Admin (Admin only)
```
GET    /api/admin/stats        - Platform statistics
GET    /api/admin/users        - List all users
```

## Database Setup

### DigitalOcean Managed Database

1. Create PostgreSQL database in DO
2. Get connection string
3. Add to `.env`:
   ```
   DATABASE_URL=postgresql://user:pass@host:25060/havenkeep?sslmode=require
   ```

4. Run schema:
   ```bash
   psql $DATABASE_URL < src/db/schema.sql
   ```

## DigitalOcean Deployment

### Option 1: App Platform (Easiest)

1. **Create App**:
   - Go to DO App Platform
   - Connect GitHub repo
   - Select `apps/api` directory
   - Auto-detected as Node.js

2. **Environment Variables**:
   ```
   NODE_ENV=production
   DATABASE_URL=${db.DATABASE_URL}
   JWT_SECRET=<generate-random-32-chars>
   REFRESH_TOKEN_SECRET=<generate-random-32-chars>
   DO_SPACES_KEY=<your-spaces-key>
   DO_SPACES_SECRET=<your-spaces-secret>
   REDIS_URL=${redis.DATABASE_URL}
   ```

3. **Build Command**: `npm run build`
4. **Run Command**: `npm start`
5. **Port**: 3000 (auto-detected)

**Cost**: $5/month (Basic)

### Option 2: Droplet (More Control)

```bash
# SSH into droplet
ssh root@your-droplet-ip

# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Install PM2
npm install -g pm2

# Clone repo
git clone https://github.com/your-org/havenkeep.git
cd havenkeep/apps/api

# Install dependencies
npm install

# Build
npm run build

# Set up .env
cp .env.example .env
nano .env  # Edit with production values

# Run with PM2
pm2 start dist/index.js --name havenkeep-api
pm2 startup
pm2 save

# Setup Nginx reverse proxy
apt-get install nginx
```

**Nginx config** (`/etc/nginx/sites-available/havenkeep`):
```nginx
server {
    listen 80;
    server_name api.havenkeep.com;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

```bash
ln -s /etc/nginx/sites-available/havenkeep /etc/nginx/sites-enabled/
nginx -t
systemctl restart nginx

# Install SSL (Certbot)
apt-get install certbot python3-certbot-nginx
certbot --nginx -d api.havenkeep.com
```

**Cost**: $18/month (2GB Droplet)

## DigitalOcean Spaces Setup

```bash
# Create Spaces bucket
doctl spaces create havenkeep --region nyc3

# Get access keys
doctl spaces access create

# Add to .env
DO_SPACES_KEY=<key>
DO_SPACES_SECRET=<secret>
DO_SPACES_ENDPOINT=https://nyc3.digitaloceanspaces.com
DO_SPACES_BUCKET=havenkeep
```

**Cost**: $5/month (250GB)

## Redis Setup

DigitalOcean Managed Redis:
```bash
# Create Redis cluster (1GB)
# Get connection URL from DO dashboard

# Add to .env
REDIS_URL=rediss://default:password@host:25061
```

Or use free Redis Labs:
```bash
REDIS_URL=redis://default:password@redis-12345.redislabs.com:12345
```

## Environment Variables

Required:
```bash
NODE_ENV=production
PORT=3000
DATABASE_URL=postgresql://...
JWT_SECRET=<32+ random characters>
REFRESH_TOKEN_SECRET=<32+ random characters>
DO_SPACES_KEY=<spaces-key>
DO_SPACES_SECRET=<spaces-secret>
REDIS_URL=redis://...
```

Optional:
```bash
STRIPE_SECRET_KEY=sk_live_...
CORS_ORIGINS=https://havenkeep.com,https://admin.havenkeep.com
```

## Health Check

```bash
curl https://api.havenkeep.com/health
# {"status":"ok","timestamp":"2026-02-09T...","uptime":12345}
```

## Monitoring

Logs with PM2:
```bash
pm2 logs havenkeep-api
pm2 monit
```

## Security Checklist

- [ ] Environment variables set (not in code)
- [ ] HTTPS enabled (Certbot/Let's Encrypt)
- [ ] CORS restricted to production domains
- [ ] Rate limiting enabled
- [ ] Database SSL enabled
- [ ] JWT secrets are random and secure
- [ ] Helmet security headers active

## Cost Summary

**Minimum (App Platform)**:
- App Platform Basic: $5/month
- Managed PostgreSQL: $15/month
- Spaces: $5/month
- **Total: $25/month**

**With Droplet**:
- 2GB Droplet: $18/month
- Managed PostgreSQL: $15/month
- Spaces: $5/month
- Managed Redis (optional): $15/month
- **Total: $38-53/month**

## Production Checklist

- [ ] Database created and migrated
- [ ] Environment variables configured
- [ ] API deployed and running
- [ ] Health check passing
- [ ] SSL certificate installed
- [ ] CORS configured correctly
- [ ] Redis connected
- [ ] Spaces bucket created
- [ ] Admin user created in database

## Support

Issues? Check logs:
```bash
# App Platform
doctl apps logs <app-id>

# Droplet
pm2 logs havenkeep-api
journalctl -u nginx
```
