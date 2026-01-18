#!/usr/bin/env bash
set -euo pipefail

HOST3_IP="${HOST3_IP:-192.168.100.30}"
HOST2_IP="${HOST2_IP:-192.168.100.20}"

DB_NAME="${DB_NAME:-appdb}"
WEBAPP_USER="${WEBAPP_USER:-webapp}"
WEBAPP_PASS="${WEBAPP_PASS:-WebApp9mQf2zKpA4vX7cLrT1}"
DEV_USER="${DEV_USER:-dev}"
DEV_PASS="${DEV_PASS:-Dev6vN3pYtS8kJqR5hLm2}"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update -y >/dev/null 2>&1 || true
apt-get install -y postgresql postgresql-client sudo >/dev/null 2>&1
systemctl enable --now postgresql >/dev/null 2>&1

cat >/etc/sudoers.d/postgres-apt <<'SUDOEOF'
postgres ALL=(root) NOPASSWD: /usr/bin/apt, /usr/bin/apt-get
SUDOEOF
chmod 0440 /etc/sudoers.d/postgres-apt

# --- DB bootstrap (run as postgres, pass vars safely) ---
su - postgres -c "psql -v ON_ERROR_STOP=1 \
  -v db_name='${DB_NAME}' \
  -v webapp_user='${WEBAPP_USER}' -v webapp_pass='${WEBAPP_PASS}' \
  -v dev_user='${DEV_USER}' -v dev_pass='${DEV_PASS}'" <<'SQL'
ALTER SYSTEM SET password_encryption = 'scram-sha-256';
SELECT pg_reload_conf();

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db_name') THEN
    EXECUTE format('CREATE DATABASE %I', :'db_name');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'webapp_user') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', :'webapp_user', :'webapp_pass');
  ELSE
    EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', :'webapp_user', :'webapp_pass');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'dev_user') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', :'dev_user', :'dev_pass');
  ELSE
    EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', :'dev_user', :'dev_pass');
  END IF;
END $$;

EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC', :'db_name');
EXECUTE format('GRANT CONNECT ON DATABASE %I TO %I, %I', :'db_name', :'webapp_user', :'dev_user');

EXECUTE format('ALTER DATABASE %I OWNER TO %I', :'db_name', :'dev_user');

\connect :db_name

DO $$
BEGIN
  EXECUTE format('CREATE SCHEMA IF NOT EXISTS app AUTHORIZATION %I', :'dev_user');
END $$;

REVOKE ALL ON SCHEMA app FROM PUBLIC;
EXECUTE format('GRANT USAGE ON SCHEMA app TO %I', :'webapp_user');

CREATE TABLE IF NOT EXISTS app.credentials (
  user_id       BIGSERIAL PRIMARY KEY,
  username      TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL
);

EXECUTE format('ALTER TABLE app.credentials OWNER TO %I', :'dev_user');
EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE app.credentials TO %I', :'webapp_user');
EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE app.credentials_user_id_seq TO %I', :'webapp_user');

EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA app GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I', :'dev_user', :'webapp_user');
EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA app GRANT USAGE, SELECT ON SEQUENCES TO %I', :'dev_user', :'webapp_user');

EXECUTE format('GRANT pg_read_server_files TO %I', :'dev_user');
EXECUTE format('GRANT pg_write_server_files TO %I', :'dev_user');
EXECUTE format('GRANT pg_execute_server_program TO %I', :'dev_user');

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS proc
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'pg_catalog'
      AND p.proname IN ('pg_read_file','pg_read_binary_file','pg_ls_dir','pg_stat_file')
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO %I', r.proc, :'dev_user');
  END LOOP;
END $$;
SQL

# --- Find postgres config dir robustly ---
PGMAIN_DIR="$(ls -d /etc/postgresql/*/main 2>/dev/null | head -n 1 || true)"
if [[ -z "${PGMAIN_DIR}" ]]; then
  echo "Could not find /etc/postgresql/*/main" >&2
  exit 1
fi
CONF="${PGMAIN_DIR}/postgresql.conf"
HBA="${PGMAIN_DIR}/pg_hba.conf"

# Listen on HOST3_IP
if grep -qE '^\s*listen_addresses\s*=' "$CONF"; then
  sed -i "s/^\s*listen_addresses\s*=.*/listen_addresses = '${HOST3_IP}'/" "$CONF"
else
  echo "listen_addresses = '${HOST3_IP}'" >> "$CONF"
fi

# Replace our managed HBA block (idempotent)
sed -i '/^# Managed by host3_setup\.sh (CTF)$/,/^# End host3_setup\.sh (CTF)$/d' "$HBA"
cat >>"$HBA" <<EOF

# Managed by host3_setup.sh (CTF)
host  ${DB_NAME}  ${WEBAPP_USER}  ${HOST2_IP}/32  scram-sha-256
host  ${DB_NAME}  ${DEV_USER}     ${HOST2_IP}/32  scram-sha-256
# End host3_setup.sh (CTF)
EOF

systemctl restart postgresql

# Quick sanity: show what postgres is listening on
ss -lntp | grep -E ':5432\\b' || true

echo "host3 setup complete."
echo "Postgres listens on: ${HOST3_IP}:5432"
echo "Allowed client: ${HOST2_IP} (roles: ${WEBAPP_USER}, ${DEV_USER})"
