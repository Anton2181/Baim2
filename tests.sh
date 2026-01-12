#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:5000}"

function assert_lt() {
  local value="$1"
  local limit="$2"
  if (( $(echo "$value < $limit" | bc -l) )); then
    echo "PASS: $value < $limit"
  else
    echo "FAIL: Expected $value < $limit" >&2
    exit 1
  fi
}

function assert_gt() {
  local value="$1"
  local limit="$2"
  if (( $(echo "$value > $limit" | bc -l) )); then
    echo "PASS: $value > $limit"
  else
    echo "FAIL: Expected $value > $limit" >&2
    exit 1
  fi
}

function assert_status() {
  local status="$1"
  local expected="$2"
  if [ "$status" -eq "$expected" ]; then
    echo "PASS: status $status == $expected"
  else
    echo "FAIL: Expected status $expected, got $status" >&2
    exit 1
  fi
}

printf "Checking classic SQLi is blocked...\n"
classic_time=$(curl -s -o /tmp/ctf_classic.html -w "%{time_total}" \
  -X POST "$BASE_URL/login" \
  -d "username=' OR 1=1 --" \
  -d "password=anything" \
  -d "sort=created_at")

if ! grep -q "Login failed" /tmp/ctf_classic.html; then
  echo "FAIL: Classic SQLi did not fail as expected." >&2
  exit 1
fi

assert_lt "$classic_time" 2

printf "Checking normal sort values are fast...\n"
created_time=$(curl -s -o /tmp/ctf_created.html -w "%{time_total}" \
  -X POST "$BASE_URL/login" \
  -d "username=invalid" \
  -d "password=invalid" \
  -d "sort=created_at")

assert_lt "$created_time" 2

user_time=$(curl -s -o /tmp/ctf_user.html -w "%{time_total}" \
  -X POST "$BASE_URL/login" \
  -d "username=invalid" \
  -d "password=invalid" \
  -d "sort=username")

assert_lt "$user_time" 2

printf "Checking time-based SQLi triggers delay...\n"
time_payload="created_at, IF(1=1, SLEEP(3), 1)"

sleep_time=$(curl -s -o /tmp/ctf_sleep.html -w "%{time_total}" \
  -X POST "$BASE_URL/login" \
  -d "username=invalid" \
  -d "password=invalid" \
  --data-urlencode "sort=$time_payload")

assert_gt "$sleep_time" 2.5

printf "Checking invalid sort causes server error (no whitelist)...\n"
status_code=$(curl -s -o /tmp/ctf_invalid.html -w "%{http_code}" \
  -X POST "$BASE_URL/login" \
  -d "username=invalid" \
  -d "password=invalid" \
  -d "sort=not_a_column")

assert_status "$status_code" 500

printf "All tests passed.\n"
