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
apt-get install -y postgresql sudo >/dev/null 2>&1
systemctl enable --now postgresql >/dev/null 2>&1

# Allow postgres user to apt-get (intentionally insecure for CTF flavor)
cat >/etc/sudoers.d/postgres-apt <<'SUDOEOF'
postgres ALL=(root) NOPASSWD: /usr/bin/apt, /usr/bin/apt-get
SUDOEOF
chmod 0440 /etc/sudoers.d/postgres-apt

# Configure DB, roles, schema, and privileges
su - postgres -c "psql -v ON_ERROR_STOP=1" <<SQL
-- Use SCRAM for any passwords set from now on
ALTER SYSTEM SET password_encryption = 'scram-sha-256';
SELECT pg_reload_conf();

-- 1) Create DB if missing
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}') THEN
    CREATE DATABASE ${DB_NAME};
  END IF;
END $$;

-- 2) Create or update roles
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${WEBAPP_USER}') THEN
    CREATE ROLE ${WEBAPP_USER} LOGIN PASSWORD '${WEBAPP_PASS}';
  ELSE
    ALTER ROLE ${WEBAPP_USER} LOGIN PASSWORD '${WEBAPP_PASS}';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${DEV_USER}') THEN
    CREATE ROLE ${DEV_USER} LOGIN PASSWORD '${DEV_PASS}';
  ELSE
    ALTER ROLE ${DEV_USER} LOGIN PASSWORD '${DEV_PASS}';
  END IF;
END $$;

-- 3) Restrict who can connect
REVOKE ALL ON DATABASE ${DB_NAME} FROM PUBLIC;
GRANT CONNECT ON DATABASE ${DB_NAME} TO ${WEBAPP_USER}, ${DEV_USER};

-- dev owns the DB (enables DDL management without superuser)
ALTER DATABASE ${DB_NAME} OWNER TO ${DEV_USER};

\connect ${DB_NAME}

-- 4) Create dedicated schema owned by dev
CREATE SCHEMA IF NOT EXISTS app AUTHORIZATION ${DEV_USER};
REVOKE ALL ON SCHEMA app FROM PUBLIC;

-- webapp can use schema but cannot create objects
GRANT USAGE ON SCHEMA app TO ${WEBAPP_USER};

-- 5) Credentials table (ONLY 3 columns)
CREATE TABLE IF NOT EXISTS app.credentials (
  user_id       BIGSERIAL PRIMARY KEY,
  username      TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL
);
ALTER TABLE app.credentials OWNER TO ${DEV_USER};

-- 6) webapp: read/write data only
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE app.credentials TO ${WEBAPP_USER};
GRANT USAGE, SELECT ON SEQUENCE app.credentials_user_id_seq TO ${WEBAPP_USER};

-- 7) Default privileges so dev-created objects give webapp DML
ALTER DEFAULT PRIVILEGES FOR ROLE ${DEV_USER} IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${WEBAPP_USER};

ALTER DEFAULT PRIVILEGES FOR ROLE ${DEV_USER} IN SCHEMA app
  GRANT USAGE, SELECT ON SEQUENCES TO ${WEBAPP_USER};

-- 8) dev: requested high-risk server capabilities
GRANT pg_read_server_files TO ${DEV_USER};
GRANT pg_write_server_files TO ${DEV_USER};
GRANT pg_execute_server_program TO ${DEV_USER};

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
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO ${DEV_USER};', r.proc);
  END LOOP;
END $$;
SQL

# --- Network exposure for CTF: listen on CTF IP, allow only host2 ---
PGVER="$(psql -V | awk '{print $3}' | cut -d. -f1)"
CONF="/etc/postgresql/${PGVER}/main/postgresql.conf"
HBA="/etc/postgresql/${PGVER}/main/pg_hba.conf"

if [[ ! -f "$CONF" || ! -f "$HBA" ]]; then
  echo "Could not find Postgres config at expected paths: $CONF / $HBA" >&2
  exit 1
fi

# Listen only on the CTF interface IP
sed -i "s/^#\?listen_addresses\s*=.*/listen_addresses = '${HOST3_IP}'/" "$CONF"

# Allow only host2 to connect to appdb as webapp/dev
{
  echo ""
  echo "# Managed by host3_setup.sh (CTF)"
  echo "host  ${DB_NAME}  ${WEBAPP_USER}  ${HOST2_IP}/32  scram-sha-256"
  echo "host  ${DB_NAME}  ${DEV_USER}     ${HOST2_IP}/32  scram-sha-256"
} >> "$HBA"

systemctl restart postgresql

echo "host3 setup complete."
echo "Postgres listens on: ${HOST3_IP}:5432"
echo "Allowed client: ${HOST2_IP} (roles: ${WEBAPP_USER}, ${DEV_USER})"
