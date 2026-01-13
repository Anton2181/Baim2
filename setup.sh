#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ctf_app"

sudo apt-get update
sudo apt-get install -y python3-venv python3-pip mariadb-server bc

if [ ! -d "$APP_DIR/.venv" ]; then
  python3 -m venv "$APP_DIR/.venv"
fi

"$APP_DIR/.venv/bin/pip" install --upgrade pip
"$APP_DIR/.venv/bin/pip" install flask PyMySQL

sudo systemctl enable mariadb
sudo systemctl start mariadb

sudo mysql -e "CREATE USER IF NOT EXISTS 'ctf_user'@'localhost' IDENTIFIED BY 'ctf_password';"
sudo mysql -e "GRANT ALL PRIVILEGES ON ctf_db.* TO 'ctf_user'@'localhost'; FLUSH PRIVILEGES;"

sudo mysql < "$APP_DIR/schema.sql"

echo "Setup complete. Run ./run.sh to start the app."
