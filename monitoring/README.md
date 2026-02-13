# HavenKeep — Monitoring Stack

## Overview

HavenKeep uses a **Pino → Promtail → Loki** logging pipeline.

```
┌──────────┐     ┌───────────┐     ┌──────┐
│ API      │────▶│ Promtail  │────▶│ Loki │
│ (Pino)   │     │ (shipper) │     │(store)│
└──────────┘     └───────────┘     └──────┘
```

## Components

### Pino (API Logger)
- **Location:** `apps/api/src/utils/logger.ts`
- **Dev mode:** Pretty-printed, colorized output
- **Production:** Raw JSON for machine parsing
- Includes: `service`, `environment` base labels

### Promtail (Log Shipper)
- **Config:** `monitoring/promtail-config.yml`
- Scrapes:
  - HavenKeep API log files (`/var/log/havenkeep/api/*.log`)
  - Docker container logs via Docker socket
  - PostgreSQL logs (if file-based)
  - Redis logs (if file-based)
- Parses JSON structured logs from Pino
- Extracts labels: `level`, `service`, `environment`

### Loki (Log Storage)
- **Config:** `monitoring/loki-config.yml`
- Storage: Filesystem-based (TSDB + chunks)
- Retention: 31 days (`744h`)
- Schema: v13 with 24h index periods

## Querying Logs

Use the Loki HTTP API directly to query logs:

```bash
# All API errors (last 1 hour)
curl -sG 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={service="api"} |= "error" | json | level="50"' \
  --data-urlencode 'limit=100' | jq .

# All requests to a specific endpoint
curl -sG 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={service="api"} | json | msg="request completed" | path=~"/api/v1/items.*"' | jq .

# Slow requests (>500ms)
curl -sG 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={service="api"} | json | msg="request completed" | duration > 500' | jq .

# Auth failures
curl -sG 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={service="api"} | json | msg=~".*auth.*" | level="40"' | jq .

# Container logs for a specific service
curl -sG 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={container="havenkeep-stg-api"}' | jq .

# Check Loki is healthy
curl -s http://localhost:3100/ready
```

## Configuration

| Setting | Value | File |
|---------|-------|------|
| Retention | 31 days | `loki-config.yml` → `limits_config.retention_period` |
| Max query series | 100,000 | `loki-config.yml` → `limits_config.max_query_series` |
| Embedded cache | 100 MB | `loki-config.yml` → `query_range.results_cache` |
| Promtail port | 9080 | `promtail-config.yml` → `server.http_listen_port` |
| Loki port | 3100 | `loki-config.yml` → `server.http_listen_port` |

## Accessing Loki in Staging

Loki is not exposed externally. To query from your local machine:

```bash
# SSH tunnel from your local machine
ssh -L 3100:localhost:3100 user@staging-server

# Then query logs locally
curl -sG 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={service="api"}' \
  --data-urlencode 'limit=50' | jq .
```
