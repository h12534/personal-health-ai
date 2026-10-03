#!/usr/bin/env sh
set -eu

: "${POSTGRES_HOST:=localhost}"
: "${POSTGRES_PORT:=5432}"
: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${SOURCE_DATABASE:?SOURCE_DATABASE is required}"
: "${RESTORE_DATABASE:?RESTORE_DATABASE is required}"

RESTORE_REPORT_PATH=${RESTORE_REPORT_PATH:-}
MARKER_EMAIL=${RESTORE_MARKER_EMAIL:-rc-restore-drill@example.invalid}
MARKER_DOCUMENT_TITLE=${RESTORE_MARKER_DOCUMENT_TITLE:-RC restore drill knowledge document}

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

report() {
  printf '%s\n' "$1"
  if [ -n "$RESTORE_REPORT_PATH" ]; then
    mkdir -p "$(dirname "$RESTORE_REPORT_PATH")"
    printf '%s\n' "$1" >> "$RESTORE_REPORT_PATH"
  fi
}

if [ -n "$RESTORE_REPORT_PATH" ]; then
  : > "$RESTORE_REPORT_PATH"
fi

report "restore_drill_started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
report "source_database=$SOURCE_DATABASE"
report "restore_database=$RESTORE_DATABASE"

pg_dump \
  --host="$POSTGRES_HOST" \
  --port="$POSTGRES_PORT" \
  --username="$POSTGRES_USER" \
  --format=custom \
  --file="$dump_file" \
  "$SOURCE_DATABASE"

report "dump_sha256=$(sha256sum "$dump_file" | awk '{print $1}')"

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
  --no-owner \
  --no-privileges \
  "$dump_file"

for table in users weight_logs meal_logs workout_sessions knowledge_documents knowledge_chunks lab_reports lab_results daily_tasks health_reports; do
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
  if [ "$source_count" = "-1" ]; then
    echo "Required table is missing: $table" >&2
    exit 1
  fi
  report "table.$table.count=$restored_count"
done

compare_marker_ids() {
  name=$1
  query=$2
  source_ids=$(printf '%s\n' "$query" | psql -X --set=ON_ERROR_STOP=1 \
    --host="$POSTGRES_HOST" --port="$POSTGRES_PORT" \
    --username="$POSTGRES_USER" --dbname="$SOURCE_DATABASE" --tuples-only --no-align \
    --set=marker_email="$MARKER_EMAIL" --set=marker_title="$MARKER_DOCUMENT_TITLE" \
    --file=-)
  restored_ids=$(printf '%s\n' "$query" | psql -X --set=ON_ERROR_STOP=1 \
    --host="$POSTGRES_HOST" --port="$POSTGRES_PORT" \
    --username="$POSTGRES_USER" --dbname="$RESTORE_DATABASE" --tuples-only --no-align \
    --set=marker_email="$MARKER_EMAIL" --set=marker_title="$MARKER_DOCUMENT_TITLE" \
    --file=-)
  if [ -z "$source_ids" ] || [ "$source_ids" != "$restored_ids" ]; then
    echo "Marker mismatch for $name: source=$source_ids restored=$restored_ids" >&2
    exit 1
  fi
  report "marker.$name.ids=$restored_ids"
}

compare_marker_ids users \
  "SELECT string_agg(id::text, ',' ORDER BY id) FROM users WHERE email = :'marker_email';"
for table in weight_logs meal_logs workout_sessions lab_reports daily_tasks health_reports; do
  compare_marker_ids "$table" \
    "SELECT string_agg(id::text, ',' ORDER BY id) FROM $table WHERE user_id = (SELECT id FROM users WHERE email = :'marker_email');"
done
compare_marker_ids knowledge_documents \
  "SELECT string_agg(id::text, ',' ORDER BY id) FROM knowledge_documents WHERE title = :'marker_title';"
compare_marker_ids knowledge_chunks \
  "SELECT string_agg(chunk.id::text, ',' ORDER BY chunk.id) FROM knowledge_chunks chunk JOIN knowledge_documents document ON document.id = chunk.document_id WHERE document.title = :'marker_title';"
compare_marker_ids lab_results \
  "SELECT string_agg(result.id::text, ',' ORDER BY result.id) FROM lab_results result JOIN lab_reports report ON report.id = result.report_id JOIN users owner ON owner.id = report.user_id WHERE owner.email = :'marker_email';"

psql --host="$POSTGRES_HOST" --port="$POSTGRES_PORT" \
  --username="$POSTGRES_USER" --dbname="$RESTORE_DATABASE" \
  --command="SELECT version_num FROM alembic_version;" >/dev/null

report "alembic_version=$(psql --host="$POSTGRES_HOST" --port="$POSTGRES_PORT" --username="$POSTGRES_USER" --dbname="$RESTORE_DATABASE" --tuples-only --no-align --command='SELECT version_num FROM alembic_version;')"
report "restore_drill_completed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
report "result=passed"
echo "Restore drill passed: $SOURCE_DATABASE -> $RESTORE_DATABASE"
