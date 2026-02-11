#!/bin/bash

# Audit Log Cleanup Script
# Runs the retention policy to clean up old audit logs
# Schedule via cron: 0 2 * * * /path/to/run-audit-cleanup.sh

set -e

echo "🧹 HavenKeep Audit Log Cleanup"
echo "=============================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Change to project root
cd "$(dirname "$0")/.."

# Check for required environment variables
if [ -z "$DATABASE_URL" ] && [ -z "$DB_HOST" ]; then
  echo -e "${RED}Error: DATABASE_URL or DB_HOST environment variable is required${NC}"
  exit 1
fi

echo -e "${YELLOW}[1/3]${NC} Checking table size before cleanup..."

# Get current stats
if [ -n "$DATABASE_URL" ]; then
  BEFORE_COUNT=$(psql "$DATABASE_URL" -t -c "SELECT COUNT(*) FROM audit_logs;")
  BEFORE_SIZE=$(psql "$DATABASE_URL" -t -c "SELECT pg_size_pretty(pg_total_relation_size('audit_logs'));")
else
  BEFORE_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM audit_logs;")
  BEFORE_SIZE=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT pg_size_pretty(pg_total_relation_size('audit_logs'));")
fi

echo -e "  Before: ${BEFORE_COUNT// /} rows, $BEFORE_SIZE"

echo -e "${YELLOW}[2/3]${NC} Running cleanup..."

# Run cleanup function
CLEANUP_QUERY="SELECT cleanup_old_audit_logs();"

if [ -n "$DATABASE_URL" ]; then
  psql "$DATABASE_URL" -c "$CLEANUP_QUERY" > /dev/null
else
  PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" -c "$CLEANUP_QUERY" > /dev/null
fi

echo -e "${GREEN}✓${NC} Cleanup completed"

echo -e "${YELLOW}[3/3]${NC} Checking table size after cleanup..."

# Get stats after cleanup
if [ -n "$DATABASE_URL" ]; then
  AFTER_COUNT=$(psql "$DATABASE_URL" -t -c "SELECT COUNT(*) FROM audit_logs;")
  AFTER_SIZE=$(psql "$DATABASE_URL" -t -c "SELECT pg_size_pretty(pg_total_relation_size('audit_logs'));")
else
  AFTER_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM audit_logs;")
  AFTER_SIZE=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT pg_size_pretty(pg_total_relation_size('audit_logs'));")
fi

DELETED_COUNT=$((${BEFORE_COUNT// /} - ${AFTER_COUNT// /}))

echo -e "  After: ${AFTER_COUNT// /} rows, $AFTER_SIZE"
echo -e "  Deleted: $DELETED_COUNT rows"

echo ""
echo -e "${GREEN}=============================="
echo "✅ Cleanup complete!"
echo "==============================${NC}"
echo ""
echo "Retention policy:"
echo "  • Info logs: kept for 1 year"
echo "  • Warning/Error/Critical: kept for 3 years"
echo ""
