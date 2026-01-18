#!/usr/bin/env bash
set -euo pipefail

PORT=5000
WEBAPP_IP="${WEBAPP_IP:-192.168.100.10}"
WEBAPP_NETMASK="${WEBAPP_NETMASK:-255.255.255.0}"
WEBAPP_SERVER_NAME="${WEBAPP_SERVER_NAME:-192.168.100.10}"
WEBMIN_HOST="${WEBMIN_HOST:-192.168.100.20}"
WEBMIN_PORT="${WEBMIN_PORT:-10000}"

sudo_cmd() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    echo ""
  elif command -v sudo >/dev/null 2>&1; then
    echo "sudo"
  else
    return 1
  fi
}

# Ensure admin binaries are available even on minimal PATH
ensure_sbin_path() {
  if [[ ":$PATH:" != *":/usr/sbin:"* ]]; then
    export PATH="$PATH:/usr/sbin:/sbin"
  fi
}

configure_network() {
  local nat_iface
  local internal_iface
  local ifaces
  local cmd_prefix

  nat_iface=$(ip route show default 2>/dev/null | awk '{print $5}' | head -n 1)
  ifaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' || true)
  internal_iface=$(echo "${ifaces}" | grep -v "^${nat_iface}$" | head -n 1)
  cmd_prefix=$(sudo_cmd) || {
    echo "Skipping network configuration (no sudo/root available)." >&2
    return
  }

  if [[ -n ${nat_iface} && -n ${internal_iface} ]]; then
    ${cmd_prefix} tee /etc/network/interfaces >/dev/null <<EOF_NET
# Managed by webapp setup.sh
auto lo
iface lo inet loopback

# NAT / Internet
auto ${nat_iface}
iface ${nat_iface} inet dhcp

# CTF network
auto ${internal_iface}
iface ${internal_iface} inet static
  address ${WEBAPP_IP}
  netmask ${WEBAPP_NETMASK}
EOF_NET
    ${cmd_prefix} systemctl restart networking >/dev/null 2>&1 || \
      ${cmd_prefix} service networking restart >/dev/null 2>&1 || true
  fi

  # Open ports (best-effort, depends on firewall tooling)
  if command -v ufw >/dev/null 2>&1; then
    ${cmd_prefix} ufw allow "${PORT}/tcp" >/dev/null || true
    ${cmd_prefix} ufw allow "80/tcp" >/dev/null || true
  elif command -v firewall-cmd >/dev/null 2>&1; then
    ${cmd_prefix} firewall-cmd --add-port="${PORT}/tcp" --permanent >/dev/null 2>&1 || true
    ${cmd_prefix} firewall-cmd --add-port="80/tcp" --permanent >/dev/null 2>&1 || true
    ${cmd_prefix} firewall-cmd --reload >/dev/null 2>&1 || true
  elif command -v iptables >/dev/null 2>&1; then
    ${cmd_prefix} iptables -C INPUT -p tcp --dport "${PORT}" -j ACCEPT >/dev/null 2>&1 || \
      ${cmd_prefix} iptables -I INPUT -p tcp --dport "${PORT}" -j ACCEPT >/dev/null 2>&1 || true
    ${cmd_prefix} iptables -C INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || \
      ${cmd_prefix} iptables -I INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true
  fi
}

configure_apache() {
  local cmd_prefix
  cmd_prefix=$(sudo_cmd) || {
    echo "Skipping Apache configuration (no sudo/root available)." >&2
    return
  }
  ensure_sbin_path

  # Ensure apache is installed
  ${cmd_prefix} apt-get update -y >/dev/null 2>&1 || true
  ${cmd_prefix} apt-get install -y apache2 curl >/dev/null 2>&1 || true

  # Enable required modules (must exist for ProxyPreserveHost/ProxyPass)
  ${cmd_prefix} a2enmod proxy proxy_http headers rewrite >/dev/null 2>&1 || true

  # Write site config
  ${cmd_prefix} tee /etc/apache2/sites-available/webapp.conf >/dev/null <<EOF_APACHE
<VirtualHost *:80>
    ServerName ${WEBAPP_SERVER_NAME}
    ServerAlias *

    ProxyPreserveHost On

    # --- WEBMIN PROXY ---
    <Location /admin/infra/>
        ProxyPass http://${WEBMIN_HOST}:${WEBMIN_PORT}/ nocanon
        ProxyPassReverse http://${WEBMIN_HOST}:${WEBMIN_PORT}/

        ProxyPassReverseCookiePath / /admin/infra
        ProxyPassReverseCookieDomain ${WEBMIN_HOST} ${WEBAPP_IP}

        RequestHeader set X-Forwarded-Proto "http"
        RequestHeader set X-Forwarded-Host "${WEBAPP_IP}"
        RequestHeader set X-Forwarded-Port "80"

        Header edit Location "^http://${WEBMIN_HOST}:${WEBMIN_PORT}(/.*)?$" "/admin/infra$1"
        Header edit Location "^http://${WEBAPP_IP}:${WEBMIN_PORT}(/.*)?$" "/admin/infra$1"
        Header edit Location "^/(?!admin/infra)(.*)$" "/admin/infra/$1"
    </Location>

    # --- WEBAPP ---
    ProxyPass / http://127.0.0.1:${PORT}/
    ProxyPassReverse / http://127.0.0.1:${PORT}/
</VirtualHost>
EOF_APACHE

  # Disable default site, enable ours (use .conf names explicitly)
  ${cmd_prefix} a2dissite 000-default.conf >/dev/null 2>&1 || true
  ${cmd_prefix} a2ensite webapp.conf >/dev/null 2>&1 || true

  # Validate config before reload/restart
  if ${cmd_prefix} apachectl -t >/dev/null 2>&1; then
    ${cmd_prefix} systemctl reload apache2 >/dev/null 2>&1 || ${cmd_prefix} systemctl restart apache2 >/dev/null 2>&1 || true
  else
    echo "Apache config test failed. Showing errors:" >&2
    ${cmd_prefix} apachectl -t >&2 || true
    return 1
  fi
}

setup_python_env() {
  # Prefer python3-venv (Debian standard); fall back if you really have 3.13 packages
  local cmd_prefix
  cmd_prefix=$(sudo_cmd) || cmd_prefix=""

  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 not found." >&2
    return 1
  fi

  # Install venv module if missing
  if ! python3 -c 'import venv' >/dev/null 2>&1; then
    ${cmd_prefix} apt-get update -y >/dev/null 2>&1 || true
    ${cmd_prefix} apt-get install -y python3-venv >/dev/null 2>&1 || true
  fi

  python3 -m venv .venv
  # shellcheck disable=SC1091
  source .venv/bin/activate
  pip install --upgrade pip
  pip install -r requirements.txt

  python app/init_db.py
}

main() {
  configure_network
  configure_apache
  setup_python_env

  chmod +x ./scripts/run.sh ./scripts/setup.sh ./scripts/test.sh ./scripts/attack_timed_sqli.py
  echo "Setup complete. Run ./scripts/run.sh to start the app."
}

main "$@"
