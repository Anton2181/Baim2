#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ctf_app"

export DB_HOST="127.0.0.1"
export DB_USER="ctf_user"
export DB_PASSWORD="ctf_password"
export DB_NAME="ctf_db"

"$APP_DIR/.venv/bin/python" "$APP_DIR/app.py"
