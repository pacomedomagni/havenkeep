#!/bin/bash

# Database Backup Script
# Usage: ./backup-database.sh

set -e

BACKUP_DIR="${BACKUP_DIR:-./backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/havenkeep_backup_$TIMESTAMP.sql"

mkdir -p "$BACKUP_DIR"

echo "🔄 Creating database backup..."

if [ -n "$DATABASE_URL" ]; then
    pg_dump "$DATABASE_URL" > "$BACKUP_FILE"
else
    pg_dump -h "${DB_HOST:-localhost}" \
            -p "${DB_PORT:-5432}" \
            -U "${DB_USER:-havenkeep}" \
            -d "${DB_NAME:-havenkeep}" \
            > "$BACKUP_FILE"
fi

gzip "$BACKUP_FILE"

echo "✅ Backup created: ${BACKUP_FILE}.gz"

# Keep only last 30 backups
ls -t "$BACKUP_DIR"/havenkeep_backup_*.sql.gz | tail -n +31 | xargs -r rm

echo "🧹 Cleaned old backups (kept last 30)"
