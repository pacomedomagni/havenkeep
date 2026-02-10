# Loki Logging Setup for HavenKeep

## Overview

HavenKeep uses **Grafana Loki** for centralized log aggregation instead of heavy solutions like Sentry, Prometheus, or Grafana Cloud. Loki is:
- **Lightweight**: Minimal resource usage
- **Free**: 100% open-source, no paid tiers
- **Fast**: Designed for log queries, not metrics
- **Simple**: No complex setup, no schemas

## Architecture

```
Flutter App → Logging Service → Local Log Files + HTTP → Loki → Grafana (viewing)
```

**Local Logs**: Always written to device storage (survives offline periods)
**Remote Shipping**: Optionally ship logs to Loki when `LOKI_URL` is configured

---

## Quick Start (Development)

### 1. Run Loki Locally with Docker

```bash
# Create a Loki config file
cat > loki-config.yaml << 'EOF'
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 168h

storage_config:
  boltdb:
    directory: /tmp/loki/index

  filesystem:
    directory: /tmp/loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: false
  retention_period: 0s
EOF

# Run Loki
docker run -d \
  --name loki \
  -p 3100:3100 \
  -v $(pwd)/loki-config.yaml:/etc/loki/config.yaml \
  grafana/loki:latest \
  -config.file=/etc/loki/config.yaml
```

### 2. Run Grafana for Viewing Logs

```bash
docker run -d \
  --name grafana \
  -p 3000:3000 \
  grafana/grafana:latest
```

**Access Grafana**: http://localhost:3000 (admin/admin)

### 3. Configure Loki as Data Source in Grafana

1. Go to **Configuration** → **Data Sources** → **Add data source**
2. Select **Loki**
3. Set URL to `http://localhost:3100`
4. Click **Save & Test**

### 4. Update `.env.development`

```bash
# Enable Loki logging
LOKI_URL=http://localhost:3100
```

### 5. View Logs in Grafana

1. Go to **Explore** in Grafana
2. Select **Loki** as data source
3. Use LogQL queries:
   ```
   {app="havenkeep"}                        # All logs
   {app="havenkeep", level="ERROR"}         # Errors only
   {app="havenkeep"} |= "upload"            # Logs containing "upload"
   ```

---

## Production Setup

### Option 1: Self-Hosted on VPS (Cheapest)

Deploy Loki + Grafana on a $5/month VPS (DigitalOcean, Hetzner, Vultr):

```bash
# docker-compose.yml
version: "3"

services:
  loki:
    image: grafana/loki:latest
    ports:
      - "3100:3100"
    volumes:
      - ./loki-config.yaml:/etc/loki/config.yaml
      - loki-data:/tmp/loki
    command: -config.file=/etc/loki/config.yaml
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    volumes:
      - grafana-data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=your-secure-password
    restart: unless-stopped

volumes:
  loki-data:
  grafana-data:
```

```bash
docker-compose up -d
```

**Secure with Nginx + Let's Encrypt**:
```nginx
# /etc/nginx/sites-available/loki
server {
    listen 443 ssl http2;
    server_name loki.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/loki.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/loki.yourdomain.com/privkey.pem;

    location / {
        proxy_pass http://localhost:3100;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}

# /etc/nginx/sites-available/grafana
server {
    listen 443 ssl http2;
    server_name grafana.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/grafana.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/grafana.yourdomain.com/privkey.pem;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

Update `.env.production`:
```
LOKI_URL=https://loki.yourdomain.com
```

### Option 2: Grafana Cloud (Free Tier)

Grafana Cloud offers a free tier with Loki included:
- 50GB logs/month free
- 14-day retention
- No credit card required

1. Sign up at https://grafana.com/
2. Create a Loki data source
3. Get your Loki URL (looks like `https://logs-prod-us-central1.grafana.net`)
4. Get your API key
5. Update `.env.production`:
   ```
   LOKI_URL=https://logs-prod-us-central1.grafana.net/loki/api/v1/push
   ```

---

## Log Retention & Cleanup

### Automatic Local Log Cleanup

The `LoggingService` automatically cleans logs older than 7 days:

```dart
await LoggingService.cleanOldLogs(); // Run on app start
```

### Loki Retention Configuration

Edit `loki-config.yaml`:

```yaml
limits_config:
  retention_period: 720h  # 30 days

table_manager:
  retention_deletes_enabled: true
  retention_period: 720h
```

---

## Querying Logs with LogQL

### Basic Queries

```
# All logs
{app="havenkeep"}

# Filter by level
{app="havenkeep", level="ERROR"}
{app="havenkeep", level="INFO"}

# Filter by environment
{app="havenkeep", environment="production"}

# Search for text
{app="havenkeep"} |= "upload"
{app="havenkeep"} |= "error"

# Exclude text
{app="havenkeep"} != "debug"

# Regex search
{app="havenkeep"} |~ "user.*logged in"
```

### Advanced Queries

```
# Rate of errors per minute
rate({app="havenkeep", level="ERROR"}[1m])

# Count logs over time
count_over_time({app="havenkeep"}[5m])

# Parse JSON and extract field
{app="havenkeep"} | json | userId != ""
```

---

## Troubleshooting

### Logs not appearing in Loki

1. **Check network**: Ensure app can reach Loki URL
   ```bash
   curl http://your-loki-url:3100/ready
   ```

2. **Check Loki logs**:
   ```bash
   docker logs loki
   ```

3. **Verify LOKI_URL** in `.env` file

4. **Check app logs**: LoggingService logs errors to console if Loki push fails

### High storage usage

1. **Reduce retention period** in `loki-config.yaml`
2. **Enable compression**:
   ```yaml
   compactor:
     working_directory: /tmp/loki/compactor
     shared_store: filesystem
     compaction_interval: 10m
   ```

### Slow queries

1. **Use labels** instead of full-text search when possible
2. **Limit time range**: Query last 1h instead of last 24h
3. **Use rate() and count_over_time()** instead of raw logs

---

## Cost Comparison

| Solution | Monthly Cost | Setup Complexity | Resource Usage |
|----------|--------------|------------------|----------------|
| **Loki (self-hosted)** | $5 (VPS) | Low | Minimal |
| **Grafana Cloud (free tier)** | $0 | Very Low | N/A |
| Sentry | $29-$99 | Low | N/A |
| Datadog | $15-$31/host | Medium | N/A |
| New Relic | $25-$99 | Medium | N/A |

---

## Alternative: Local-Only Logging (No Loki)

If you don't need centralized logging, just leave `LOKI_URL` empty:

```bash
# .env.development
LOKI_URL=
```

Logs will still be written to local storage and viewable via:

```dart
final logFile = LoggingService.getLogFile();
// Share logFile for debugging
```

---

## Best Practices

1. **Use structured logging**: Always include context
   ```dart
   LoggingService.info('Item created', {
     'itemId': item.id,
     'category': item.category,
     'userId': user.id,
   });
   ```

2. **Set appropriate levels**:
   - `debug`: Development-only verbose logs
   - `info`: Normal operation events
   - `warn`: Recoverable issues
   - `error`: Errors with context
   - `fatal`: Critical failures

3. **Don't log sensitive data**:
   - ❌ Don't log: passwords, tokens, full credit cards
   - ✅ Do log: user IDs, item IDs, error messages

4. **Use log sampling** for high-volume logs (if needed):
   ```dart
   if (Random().nextDouble() < 0.1) { // 10% sampling
     LoggingService.debug('High volume event');
   }
   ```

---

## Resources

- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [LogQL Reference](https://grafana.com/docs/loki/latest/logql/)
- [Grafana Tutorials](https://grafana.com/tutorials/)
