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
    ${cmd_prefix} tee /etc/network/interfaces >/dev/null <<EOF
# Managed by webapp setup.sh
auto lo
iface lo inet loopback

auto ${nat_iface}
iface ${nat_iface} inet dhcp

auto ${internal_iface}
iface ${internal_iface} inet static
  address ${WEBAPP_IP}
  netmask ${WEBAPP_NETMASK}
EOF
    ${cmd_prefix} systemctl restart networking >/dev/null 2>&1 || \
      ${cmd_prefix} service networking restart >/dev/null 2>&1 || true
  fi

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

configure_network

sudo_prefix=$(sudo_cmd) || sudo_prefix=""
if [[ -n ${sudo_prefix} ]] || [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  ${sudo_prefix} apt-get update -y >/dev/null 2>&1 || true
  ${sudo_prefix} apt-get install -y apache2 curl python3.13-venv >/dev/null 2>&1 || true
  ${sudo_prefix} a2enmod proxy proxy_http proxy_wstunnel headers rewrite >/dev/null 2>&1 || true
  ${sudo_prefix} tee /etc/apache2/sites-available/webapp.conf >/dev/null <<EOF
<VirtualHost *:80>
    ServerName ${WEBAPP_SERVER_NAME}

    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "http"

    # Webmin exposed under /admin/infra/ (backend is root /)
    ProxyPass /admin/infra/ http://${WEBMIN_HOST}:${WEBMIN_PORT}/ nocanon
    ProxyPassReverse /admin/infra/ http://${WEBMIN_HOST}:${WEBMIN_PORT}/
    ProxyPassReverseCookiePath / /admin/infra

    # Your webapp
    ProxyPass / http://127.0.0.1:${PORT}/
    ProxyPassReverse / http://127.0.0.1:${PORT}/
</VirtualHost>
EOF
  ${sudo_prefix} a2dissite 000-default >/dev/null 2>&1 || true
  ${sudo_prefix} a2ensite webapp >/dev/null 2>&1 || true
  ${sudo_prefix} systemctl reload apache2 >/dev/null 2>&1 || true
fi

python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

python app/init_db.py
chmod +x ./scripts/run.sh ./scripts/setup.sh ./scripts/test.sh ./scripts/attack_timed_sqli.py

echo "Setup complete. Run ./scripts/run.sh to start the app."
