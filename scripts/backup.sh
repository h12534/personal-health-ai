#!/usr/bin/env sh
set -eu
umask 077

: "${POSTGRES_DB:?POSTGRES_DB is required}"
: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${BACKUP_DIR:?BACKUP_DIR is required}"

POSTGRES_HOST=${POSTGRES_HOST:-postgres}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
PRIVATE_DATA_DIR=${PRIVATE_DATA_DIR:-/data/private}
BACKUP_RETENTION_DAILY=${BACKUP_RETENTION_DAILY:-7}
BACKUP_RETENTION_WEEKLY=${BACKUP_RETENTION_WEEKLY:-4}
BACKUP_RETENTION_MONTHLY=${BACKUP_RETENTION_MONTHLY:-3}

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
daily_dir="$BACKUP_DIR/daily/$timestamp"
mkdir -p "$daily_dir" "$BACKUP_DIR/weekly" "$BACKUP_DIR/monthly"

pg_dump \
  --host="$POSTGRES_HOST" \
  --port="$POSTGRES_PORT" \
  --username="$POSTGRES_USER" \
  --format=custom \
  --file="$daily_dir/database.dump" \
  "$POSTGRES_DB"

if [ -d "$PRIVATE_DATA_DIR" ]; then
  tar -czf "$daily_dir/private-files.tar.gz" -C "$PRIVATE_DATA_DIR" .
else
  tar -czf "$daily_dir/private-files.tar.gz" --files-from /dev/null
fi

(
  cd "$daily_dir"
  sha256sum database.dump private-files.tar.gz > SHA256SUMS
)

if [ "$(date -u +%u)" = "7" ]; then
  cp -al "$daily_dir" "$BACKUP_DIR/weekly/$timestamp"
fi
if [ "$(date -u +%d)" = "01" ]; then
  cp -al "$daily_dir" "$BACKUP_DIR/monthly/$timestamp"
fi

prune_tier() {
  tier=$1
  keep=$2
  directory="$BACKUP_DIR/$tier"
  [ -d "$directory" ] || return 0
  count=0
  for candidate in $(find "$directory" -mindepth 1 -maxdepth 1 -type d | sort -r); do
    count=$((count + 1))
    if [ "$count" -gt "$keep" ]; then
      case "$candidate" in
        "$directory"/*) rm -rf -- "$candidate" ;;
        *) echo "Refusing to prune unexpected path: $candidate" >&2; exit 1 ;;
      esac
    fi
  done
}

prune_tier daily "$BACKUP_RETENTION_DAILY"
prune_tier weekly "$BACKUP_RETENTION_WEEKLY"
prune_tier monthly "$BACKUP_RETENTION_MONTHLY"

echo "Backup completed: $daily_dir"

