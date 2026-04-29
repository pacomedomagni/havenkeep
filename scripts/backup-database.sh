#!/bin/bash

# Database Backup Script
#
# Runs `pg_dump` (custom format) into $BACKUP_DIR, gzips, verifies the dump
# parses with `pg_restore --list`, optionally pushes the gzip to S3-compatible
# offsite storage, and prunes local backups older than 30 days.
#
# Required env: DATABASE_URL or { DB_HOST, DB_PORT, DB_USER, DB_NAME, PGPASSWORD }
# Optional offsite: BACKUP_S3_BUCKET, BACKUP_S3_ENDPOINT, AWS_ACCESS_KEY_ID,
# AWS_SECRET_ACCESS_KEY (or use IAM/instance role). When BACKUP_S3_BUCKET is
# unset, the offsite step is skipped — the local backup is still created.

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-./backups}"
TIMESTAMP=$(date -u +%Y%m%d_%H%M%SZ)
BACKUP_FILE="$BACKUP_DIR/havenkeep_backup_$TIMESTAMP.sql"

mkdir -p "$BACKUP_DIR"

echo "[backup] starting backup $TIMESTAMP"

# Use custom format (-Fc) so we can verify with `pg_restore --list` and
# perform partial restores. Plain SQL dumps can't be inspected without
# re-parsing the whole file.
if [ -n "${DATABASE_URL:-}" ]; then
    pg_dump -Fc "$DATABASE_URL" > "$BACKUP_FILE"
else
    pg_dump -Fc \
        -h "${DB_HOST:-localhost}" \
        -p "${DB_PORT:-5432}" \
        -U "${DB_USER:-havenkeep}" \
        -d "${DB_NAME:-havenkeep}" \
        > "$BACKUP_FILE"
fi

# 2.2: parse-verify the dump before gzip — a corrupt dump that we only
# discover on restore day is worse than no dump at all. `pg_restore --list`
# walks the TOC; non-zero exit means the file isn't a valid pg_dump.
if ! pg_restore --list "$BACKUP_FILE" > /dev/null; then
    echo "[backup] FATAL: pg_restore --list rejected $BACKUP_FILE — corrupt dump, aborting"
    rm -f "$BACKUP_FILE"
    exit 1
fi
echo "[backup] verified: $(pg_restore --list "$BACKUP_FILE" | wc -l) TOC entries"

gzip "$BACKUP_FILE"
GZ_FILE="${BACKUP_FILE}.gz"
GZ_SIZE=$(stat -f%z "$GZ_FILE" 2>/dev/null || stat -c%s "$GZ_FILE")
echo "[backup] local: $GZ_FILE (${GZ_SIZE} bytes)"

# 2.2: offsite copy. When configured, push to S3-compatible storage with
# object-lock retention enforced at the bucket level. We don't enable
# server-side retention from the client because one compromised set of
# backup credentials should not be able to relax the policy.
if [ -n "${BACKUP_S3_BUCKET:-}" ]; then
    if ! command -v aws > /dev/null; then
        echo "[backup] WARN: aws CLI not installed; skipping offsite copy"
    else
        S3_ARGS=()
        if [ -n "${BACKUP_S3_ENDPOINT:-}" ]; then
            S3_ARGS+=(--endpoint-url "$BACKUP_S3_ENDPOINT")
        fi
        S3_KEY="havenkeep/$(basename "$GZ_FILE")"
        if aws "${S3_ARGS[@]}" s3 cp "$GZ_FILE" "s3://${BACKUP_S3_BUCKET}/${S3_KEY}"; then
            echo "[backup] offsite: s3://${BACKUP_S3_BUCKET}/${S3_KEY}"
        else
            echo "[backup] WARN: offsite upload failed for $GZ_FILE"
        fi
    fi
else
    echo "[backup] offsite: skipped (BACKUP_S3_BUCKET not set)"
fi

# 2.2: prune by age, not by file count. `tail -n +31` deletes recent
# backups when the schedule is sparse (e.g. recovering from an outage
# that paused the cron for a week).
find "$BACKUP_DIR" -name 'havenkeep_backup_*.sql.gz' -mtime +30 -delete -print | sed 's/^/[backup] pruned /'

echo "[backup] done $TIMESTAMP"
