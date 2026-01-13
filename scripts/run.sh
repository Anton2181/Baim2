#!/usr/bin/env bash
set -euo pipefail

source .venv/bin/activate

python app/legacy_webmin.py &
LEGACY_PID=$!

trap 'kill ${LEGACY_PID}' EXIT

python app/app.py
