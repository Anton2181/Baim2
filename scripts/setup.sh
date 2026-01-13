#!/usr/bin/env bash
set -euo pipefail

python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

python app/init_db.py

echo "Setup complete. Run ./scripts/run.sh to start the app."
