#!/usr/bin/env sh
set -eu

: "${POSTGRES_HOST:=localhost}"
: "${POSTGRES_PORT:=5432}"
: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${SOURCE_DATABASE:?SOURCE_DATABASE is required}"
: "${RESTORE_DATABASE:?RESTORE_DATABASE is required}"

case "$RESTORE_DATABASE" in
  *_restore_drill) ;;
  *) echo "RESTORE_DATABASE must end with _restore_drill" >&2; exit 64 ;;
esac
if [ "$SOURCE_DATABASE" = "$RESTORE_DATABASE" ]; then
  echo "Source and restore databases must be different" >&2
  exit 64
fi

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT INT TERM
dump_file="$work_dir/database.dump"

pg_dump \
  --host="$POSTGRES_HOST" \
  --port="$POSTGRES_PORT" \
  --username="$POSTGRES_USER" \
  --format=custom \
  --file="$dump_file" \
  "$SOURCE_DATABASE"

dropdb --if-exists \
  --host="$POSTGRES_HOST" \
  --port="$POSTGRES_PORT" \
  --username="$POSTGRES_USER" \
  "$RESTORE_DATABASE"
createdb \
  --host="$POSTGRES_HOST" \
  --port="$POSTGRES_PORT" \
  --username="$POSTGRES_USER" \
  "$RESTORE_DATABASE"
pg_restore \
  --host="$POSTGRES_HOST" \
  --port="$POSTGRES_PORT" \
  --username="$POSTGRES_USER" \
  --dbname="$RESTORE_DATABASE" \
  --exit-on-error \
  "$dump_file"

for table in users daily_tasks notification_logs health_reports health_followups; do
  source_count=$(psql --host="$POSTGRES_HOST" --port="$POSTGRES_PORT" \
    --username="$POSTGRES_USER" --dbname="$SOURCE_DATABASE" --tuples-only --no-align \
    --command="SELECT CASE WHEN to_regclass('public.$table') IS NULL THEN -1 ELSE (SELECT count(*) FROM $table) END;")
  restored_count=$(psql --host="$POSTGRES_HOST" --port="$POSTGRES_PORT" \
    --username="$POSTGRES_USER" --dbname="$RESTORE_DATABASE" --tuples-only --no-align \
    --command="SELECT CASE WHEN to_regclass('public.$table') IS NULL THEN -1 ELSE (SELECT count(*) FROM $table) END;")
  if [ "$source_count" != "$restored_count" ]; then
    echo "Count mismatch for $table: source=$source_count restored=$restored_count" >&2
    exit 1
  fi
done

psql --host="$POSTGRES_HOST" --port="$POSTGRES_PORT" \
  --username="$POSTGRES_USER" --dbname="$RESTORE_DATABASE" \
  --command="SELECT version_num FROM alembic_version;" >/dev/null

echo "Restore drill passed: $SOURCE_DATABASE -> $RESTORE_DATABASE"

