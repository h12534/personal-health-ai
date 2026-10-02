#!/usr/bin/env sh
set -eu

SAMPLES=${RESOURCE_SAMPLES:-6}
INTERVAL_SECONDS=${RESOURCE_INTERVAL_SECONDS:-10}
OUTPUT_PATH=${RESOURCE_OUTPUT_PATH:-artifacts/resource-usage.csv}

case "$SAMPLES:$INTERVAL_SECONDS" in
  *[!0-9:]*|0:*|*:0) echo "RESOURCE_SAMPLES and RESOURCE_INTERVAL_SECONDS must be positive integers" >&2; exit 64 ;;
esac

mkdir -p "$(dirname "$OUTPUT_PATH")"
printf 'timestamp,service,cpu_percent,memory_usage,net_io,block_io,pids\n' > "$OUTPUT_PATH"

iteration=1
while [ "$iteration" -le "$SAMPLES" ]; do
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  docker compose --env-file .env.staging \
    -f docker-compose.production.yml -f docker-compose.staging.yml \
    ps --services --filter status=running | while IFS= read -r service; do
      container_id=$(docker compose --env-file .env.staging \
        -f docker-compose.production.yml -f docker-compose.staging.yml ps -q "$service")
      [ -n "$container_id" ] || continue
      metrics=$(docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}|{{.NetIO}}|{{.BlockIO}}|{{.PIDs}}' "$container_id")
      printf '%s,%s,%s\n' "$timestamp" "$service" "$(printf '%s' "$metrics" | tr '|' ',')" >> "$OUTPUT_PATH"
    done
    iteration=$((iteration + 1))
    if [ "$iteration" -le "$SAMPLES" ]; then
      sleep "$INTERVAL_SECONDS"
    fi
done

echo "Resource measurements written to $OUTPUT_PATH"
