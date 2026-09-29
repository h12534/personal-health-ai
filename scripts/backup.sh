#!/usr/bin/env sh
set -eu

: "${POSTGRES_DB:?POSTGRES_DB is required}"
: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${BACKUP_DIR:?BACKUP_DIR is required}"

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$BACKUP_DIR/$timestamp"
pg_dump --format=custom --file="$BACKUP_DIR/$timestamp/database.dump" --username="$POSTGRES_USER" "$POSTGRES_DB"
tar -czf "$BACKUP_DIR/$timestamp/private-files.tar.gz" -C /data uploads
sha256sum "$BACKUP_DIR/$timestamp/"* > "$BACKUP_DIR/$timestamp/SHA256SUMS"

# Daily pruning only. Weekly/monthly promotion belongs to the host backup policy.
find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf -- {} +

