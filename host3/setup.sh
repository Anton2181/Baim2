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
systemctl enable --now postgresql >/dev/null 2>&1 || true

cat >/etc/sudoers.d/postgres-apt <<'EOF'
postgres ALL=(root) NOPASSWD: /usr/bin/apt, /usr/bin/apt-get
EOF
chmod 0440 /etc/sudoers.d/postgres-apt

# Create DB if missing (outside transaction)
su - postgres -c "psql -v ON_ERROR_STOP=1 -d postgres" <<SQL
SELECT format('CREATE DATABASE %I', '${DB_NAME}')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}');
\gexec
SQL

TMP_SQL="$(mktemp /tmp/host3_setup.XXXXXX.sql)"
cleanup() { rm -f "$TMP_SQL"; }
trap cleanup EXIT

# WRITE FILE AS ROOT FIRST
cat >"$TMP_SQL" <<SQL
ALTER SYSTEM SET password_encryption = 'scram-sha-256';
SELECT pg_reload_conf();

DO \$\$
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
END \$\$;

REVOKE ALL ON DATABASE ${DB_NAME} FROM PUBLIC;
GRANT CONNECT ON DATABASE ${DB_NAME} TO ${WEBAPP_USER}, ${DEV_USER};
ALTER DATABASE ${DB_NAME} OWNER TO ${DEV_USER};

\connect ${DB_NAME}

CREATE SCHEMA IF NOT EXISTS app AUTHORIZATION ${DEV_USER};
REVOKE ALL ON SCHEMA app FROM PUBLIC;
GRANT USAGE ON SCHEMA app TO ${WEBAPP_USER};

CREATE TABLE IF NOT EXISTS app.credentials (
  user_id       BIGSERIAL PRIMARY KEY,
  username      TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL
);
ALTER TABLE app.credentials OWNER TO ${DEV_USER};

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE app.credentials TO ${WEBAPP_USER};
GRANT USAGE, SELECT ON SEQUENCE app.credentials_user_id_seq TO ${WEBAPP_USER};

ALTER DEFAULT PRIVILEGES FOR ROLE ${DEV_USER} IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${WEBAPP_USER};

ALTER DEFAULT PRIVILEGES FOR ROLE ${DEV_USER} IN SCHEMA app
  GRANT USAGE, SELECT ON SEQUENCES TO ${WEBAPP_USER};

GRANT pg_read_server_files TO ${DEV_USER};
GRANT pg_write_server_files TO ${DEV_USER};
GRANT pg_execute_server_program TO ${DEV_USER};
SQL

# make readable for postgres
chmod 0644 "$TMP_SQL"

su - postgres -c "psql -v ON_ERROR_STOP=1 -f '$TMP_SQL'"

PGMAIN_DIR="$(ls -d /etc/postgresql/*/main 2>/dev/null | head -n 1 || true)"
CONF="${PGMAIN_DIR}/postgresql.conf"
HBA="${PGMAIN_DIR}/pg_hba.conf"

# Listen only on the CTF IP
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

echo "host3 setup complete."
echo "Postgres listens on: ${HOST3_IP}:5432"
echo "Allowed client: ${HOST2_IP} (roles: ${WEBAPP_USER}, ${DEV_USER})"
