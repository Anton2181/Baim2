#!/usr/bin/env bash
set -euo pipefail

HOST3_IP="${HOST3_IP:-192.168.100.30}"
HOST2_IP="${HOST2_IP:-192.168.100.20}"

DB_NAME="appdb"
WEBAPP_USER="webapp"
WEBAPP_PASS="WebApp9mQf2zKpA4vX7cLrT1"
DEV_USER="dev"
DEV_PASS="Dev6vN3pYtS8kJqR5hLm2"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "[+] Installing PostgreSQL"
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y postgresql sudo >/dev/null 2>&1

systemctl enable --now postgresql >/dev/null 2>&1

echo "[+] Allow postgres to use apt (CTF insecure feature)"
cat >/etc/sudoers.d/postgres-apt <<EOF
postgres ALL=(root) NOPASSWD: /usr/bin/apt, /usr/bin/apt-get
EOF
chmod 0440 /etc/sudoers.d/postgres-apt

TMP_SQL="/tmp/host3_setup.sql"

cat >"$TMP_SQL" <<'SQL'
ALTER SYSTEM SET password_encryption = 'scram-sha-256';
SELECT pg_reload_conf();

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'appdb') THEN
    CREATE DATABASE appdb;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'webapp') THEN
    CREATE ROLE webapp LOGIN PASSWORD 'WebApp9mQf2zKpA4vX7cLrT1';
  ELSE
    ALTER ROLE webapp LOGIN PASSWORD 'WebApp9mQf2zKpA4vX7cLrT1';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dev') THEN
    CREATE ROLE dev LOGIN PASSWORD 'Dev6vN3pYtS8kJqR5hLm2';
  ELSE
    ALTER ROLE dev LOGIN PASSWORD 'Dev6vN3pYtS8kJqR5hLm2';
  END IF;
END $$;

REVOKE ALL ON DATABASE appdb FROM PUBLIC;
GRANT CONNECT ON DATABASE appdb TO webapp, dev;
ALTER DATABASE appdb OWNER TO dev;

\connect appdb

CREATE SCHEMA IF NOT EXISTS app AUTHORIZATION dev;
REVOKE ALL ON SCHEMA app FROM PUBLIC;
GRANT USAGE ON SCHEMA app TO webapp;

CREATE TABLE IF NOT EXISTS app.credentials (
  user_id BIGSERIAL PRIMARY KEY,
  username TEXT UNIQUE,
  password_hash TEXT
);

ALTER TABLE app.credentials OWNER TO dev;
GRANT SELECT,INSERT,UPDATE,DELETE ON app.credentials TO webapp;
GRANT USAGE,SELECT ON SEQUENCE app.credentials_user_id_seq TO webapp;

ALTER DEFAULT PRIVILEGES FOR ROLE dev IN SCHEMA app
  GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO webapp;

ALTER DEFAULT PRIVILEGES FOR ROLE dev IN SCHEMA app
  GRANT USAGE,SELECT ON SEQUENCES TO webapp;

GRANT pg_read_server_files TO dev;
GRANT pg_write_server_files TO dev;
GRANT pg_execute_server_program TO dev;
SQL

echo "[+] Running SQL configuration"
su - postgres -c "psql -v ON_ERROR_STOP=1 -f '$TMP_SQL'"

rm -f "$TMP_SQL"

echo "[+] Configuring network exposure"

PGVER=$(psql -V | awk '{print $3}' | cut -d. -f1)
CONF="/etc/postgresql/${PGVER}/main/postgresql.conf"
HBA="/etc/postgresql/${PGVER}/main/pg_hba.conf"

sed -i "s/^#\\?listen_addresses\\s*=.*/listen_addresses = '${HOST3_IP}'/" "$CONF"

cat >>"$HBA" <<EOF

# Managed by host3_setup.sh (CTF)
host  appdb  webapp  ${HOST2_IP}/32  scram-sha-256
host  appdb  dev     ${HOST2_IP}/32  scram-sha-256
EOF

systemctl restart postgresql

echo ""
echo "======================================="
echo "host3 PostgreSQL ready"
echo "Listen: ${HOST3_IP}:5432"
echo "DB: appdb"
echo "Users: webapp, dev"
echo "Allowed client: ${HOST2_IP}"
echo "======================================="
