#!/usr/bin/env bash
set -euo pipefail

# host3: PostgreSQL in CTF network (192.168.100.0/24)
# - DB: appdb
# - Roles: webapp, dev
# - Only host2 (192.168.100.20) may connect over TCP
# - Postgres listens on HOST3_IP (default 192.168.100.30)

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
systemctl enable --now postgresql >/dev/null 2>&1 || true

# Allow postgres user to apt-get (intentionally insecure for CTF flavor)
cat >/etc/sudoers.d/postgres-apt <<'SUDOEOF'
postgres ALL=(root) NOPASSWD: /usr/bin/apt, /usr/bin/apt-get
SUDOEOF
chmod 0440 /etc/sudoers.d/postgres-apt

# --- DB bootstrap (use a temp SQL file; avoids heredoc/STDIN corruption) ---
tmp_sql="$(mktemp /tmp/host3_setup.XXXXXX.sql)"
cleanup() { rm -f "$tmp_sql"; }
trap cleanup EXIT

cat >"$tmp_sql" <<'SQL'
-- Use SCRAM for any passwords set from now on
ALTER SYSTEM SET password_encryption = 'scram-sha-256';
SELECT pg_reload_conf();

-- 1) Create DB if missing
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '__DB_NAME__') THEN
    EXECUTE format('CREATE DATABASE %I', '__DB_NAME__');
  END IF;
END $$;

-- 2) Create or update roles
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '__WEBAPP_USER__') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', '__WEBAPP_USER__', '__WEBAPP_PASS__');
  ELSE
    EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', '__WEBAPP_USER__', '__WEBAPP_PASS__');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '__DEV_USER__') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', '__DEV_USER__', '__DEV_PASS__');
  ELSE
    EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', '__DEV_USER__', '__DEV_PASS__');
  END IF;
END $$;

-- 3) Restrict who can connect + set DB owner
DO $$
BEGIN
  EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC', '__DB_NAME__');
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO %I, %I', '__DB_NAME__', '__WEBAPP_USER__', '__DEV_USER__');
  EXECUTE format('ALTER DATABASE %I OWNER TO %I', '__DB_NAME__', '__DEV_USER__');
END $$;

\connect __DB_NAME__

-- 4) Create dedicated schema owned by dev
DO $$
BEGIN
  EXECUTE format('CREATE SCHEMA IF NOT EXISTS app AUTHORIZATION %I', '__DEV_USER__');
END $$;
REVOKE ALL ON SCHEMA app FROM PUBLIC;
DO $$ BEGIN EXECUTE format('GRANT USAGE ON SCHEMA app TO %I', '__WEBAPP_USER__'); END $$;

-- 5) Credentials table (ONLY 3 columns)
CREATE TABLE IF NOT EXISTS app.credentials (
  user_id       BIGSERIAL PRIMARY KEY,
  username      TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL
);
DO $$ BEGIN EXECUTE format('ALTER TABLE app.credentials OWNER TO %I', '__DEV_USER__'); END $$;

-- 6) webapp: read/write data only
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE app.credentials TO %I', '__WEBAPP_USER__');
  EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE app.credentials_user_id_seq TO %I', '__WEBAPP_USER__');
END $$;

-- 7) Ensure future dev-created tables/sequences grant webapp DML automatically
DO $$ BEGIN
  EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA app GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I', '__DEV_USER__', '__WEBAPP_USER__');
  EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA app GRANT USAGE, SELECT ON SEQUENCES TO %I', '__DEV_USER__', '__WEBAPP_USER__');
END $$;

-- 8) dev: requested high-risk server capabilities
DO $$ BEGIN
  EXECUTE format('GRANT pg_read_server_files TO %I', '__DEV_USER__');
  EXECUTE format('GRANT pg_write_server_files TO %I', '__DEV_USER__');
  EXECUTE format('GRANT pg_execute_server_program TO %I', '__DEV_USER__');
END $$;

-- 9) Allow dev to call server-file helper functions
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
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO %I', r.proc, '__DEV_USER__');
  END LOOP;
END $$;
SQL

# Replace placeholders (simple; assumes alnum usernames/passwords like in your defaults)
sed -i \
  -e "s/__DB_NAME__/${DB_NAME}/g" \
  -e "s/__WEBAPP_USER__/${WEBAPP_USER}/g" \
  -e "s/__WEBAPP_PASS__/${WEBAPP_PASS}/g" \
  -e "s/__DEV_USER__/${DEV_USER}/g" \
  -e "s/__DEV_PASS__/${DEV_PASS}/g" \
  "$tmp_sql"

su - postgres -c "psql -v ON_ERROR_STOP=1 -f '$tmp_sql'"

# --- Network exposure for CTF: listen on CTF IP, allow only host2 ---
PGMAIN_DIR="$(ls -d /etc/postgresql/*/main 2>/dev/null | head -n 1 || true)"
if [[ -z "${PGMAIN_DIR}" ]]; then
  echo "Could not find Postgres config at /etc/postgresql/*/main" >&2
  exit 1
fi

CONF="${PGMAIN_DIR}/postgresql.conf"
HBA="${PGMAIN_DIR}/pg_hba.conf"

if [[ ! -f "$CONF" || ! -f "$HBA" ]]; then
  echo "Could not find Postgres config at expected paths: $CONF / $HBA" >&2
  exit 1
fi

# Listen only on the CTF interface IP
if grep -qE '^\\s*listen_addresses\\s*=' "$CONF"; then
  sed -i "s/^\\s*listen_addresses\\s*=.*/listen_addresses = '${HOST3_IP}'/" "$CONF"
else
  echo "listen_addresses = '${HOST3_IP}'" >> "$CONF"
fi

# Idempotent HBA block
sed -i '/^# Managed by host3_setup\\.sh (CTF)$/,/^# End host3_setup\\.sh (CTF)$/d' "$HBA"
cat >>"$HBA" <<EOF

# Managed by host3_setup.sh (CTF)
host  ${DB_NAME}  ${WEBAPP_USER}  ${HOST2_IP}/32  scram-sha-256
host  ${DB_NAME}  ${DEV_USER}     ${HOST2_IP}/32  scram-sha-256
# End host3_setup.sh (CTF)
EOF

systemctl restart postgresql

echo ""
echo "host3 setup complete."
echo "Postgres listens on: ${HOST3_IP}:5432"
echo "Allowed client: ${HOST2_IP} (roles: ${WEBAPP_USER}, ${DEV_USER})"
echo ""
echo "Quick check (listening sockets):"
ss -lntp | grep -E ':5432\\b' || true
