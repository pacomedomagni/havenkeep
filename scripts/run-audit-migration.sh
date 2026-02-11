#!/bin/bash

# Run Audit System Migration
# This script applies the audit system migration to the database

set -e

echo "🔍 HavenKeep Audit System Migration"
echo "===================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Change to project root
cd "$(dirname "$0")/.."

echo "📍 Current directory: $(pwd)"
echo ""

# Check for required environment variables
if [ -z "$DATABASE_URL" ] && [ -z "$DB_HOST" ]; then
  echo -e "${RED}Error: DATABASE_URL or DB_HOST environment variable is required${NC}"
  echo "Please set your database connection details in .env"
  exit 1
fi

echo -e "${YELLOW}[1/3]${NC} Checking database connection..."

# Test database connection
if [ -n "$DATABASE_URL" ]; then
  psql "$DATABASE_URL" -c "SELECT 1" > /dev/null 2>&1
else
  PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1" > /dev/null 2>&1
fi

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓${NC} Database connection successful"
else
  echo -e "${RED}✗${NC} Database connection failed"
  exit 1
fi

echo -e "${YELLOW}[2/3]${NC} Running audit system migration..."

# Run the migration
MIGRATION_FILE="apps/api/src/db/migrations/004_audit_system.sql"

if [ ! -f "$MIGRATION_FILE" ]; then
  echo -e "${RED}✗${NC} Migration file not found: $MIGRATION_FILE"
  exit 1
fi

if [ -n "$DATABASE_URL" ]; then
  psql "$DATABASE_URL" -f "$MIGRATION_FILE"
else
  PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" -f "$MIGRATION_FILE"
fi

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓${NC} Audit system migration completed successfully"
else
  echo -e "${RED}✗${NC} Migration failed"
  exit 1
fi

echo -e "${YELLOW}[3/3]${NC} Verifying migration..."

# Verify the migration
VERIFY_QUERY="SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'audit_logs');"

if [ -n "$DATABASE_URL" ]; then
  RESULT=$(psql "$DATABASE_URL" -t -c "$VERIFY_QUERY")
else
  RESULT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" -t -c "$VERIFY_QUERY")
fi

if [[ "$RESULT" == *"t"* ]]; then
  echo -e "${GREEN}✓${NC} audit_logs table created successfully"
else
  echo -e "${RED}✗${NC} Verification failed - audit_logs table not found"
  exit 1
fi

echo ""
echo -e "${GREEN}===================================="
echo "✅ Audit system migration complete!"
echo "====================================${NC}"
echo ""
echo "The following has been created:"
echo "  ✓ audit_logs table with indexes"
echo "  ✓ audit_action and audit_severity enums"
echo "  ✓ recent_security_events view"
echo "  ✓ user_activity_summary view"
echo "  ✓ cleanup_old_audit_logs() function"
echo ""
echo "Next steps:"
echo "  1. Test the audit API endpoints"
echo "  2. Set up a cron job for log cleanup (optional)"
echo "  3. Review audit logs in admin dashboard"
echo ""
