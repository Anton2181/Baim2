#!/usr/bin/env bash
set -euo pipefail

WEBMIN_VERSION="1.920"
WEBMIN_TARBALL="webmin-${WEBMIN_VERSION}.tar.gz"
WEBMIN_URL="https://sourceforge.net/projects/webadmin/files/webmin/${WEBMIN_VERSION}/${WEBMIN_TARBALL}"
INSTALL_DIR="/usr/local/webmin"
WEBMIN_PORT="${WEBMIN_PORT:-10000}"
WEBMIN_LOGIN="${WEBMIN_LOGIN:-admin}"
WEBMIN_PASSWORD="${WEBMIN_PASSWORD:-admin123}"
WEBMIN_SSL="${WEBMIN_SSL:-n}"
WEBMIN_START_BOOT="${WEBMIN_START_BOOT:-n}"
WEBMIN_HTTP_PORT="${WEBMIN_HTTP_PORT:-${WEBMIN_PORT}}"
WEBMIN_IP="${WEBMIN_IP:-192.168.100.20}"
WEBMIN_NETMASK="${WEBMIN_NETMASK:-255.255.255.0}"

configure_network() {
  local port="${WEBMIN_HTTP_PORT}"
  local nat_iface
  local internal_iface
  local ifaces
  nat_iface=$(ip route show default 2>/dev/null | awk '{print $5}' | head -n 1)
  ifaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' || true)
  internal_iface=$(echo "${ifaces}" | grep -v "^${nat_iface}$" | head -n 1)

  if [[ -n ${nat_iface} && -n ${internal_iface} ]]; then
    tee /etc/network/interfaces >/dev/null <<EOF
# Managed by webmin-host/setup.sh
auto lo
iface lo inet loopback

auto ${nat_iface}
iface ${nat_iface} inet dhcp

auto ${internal_iface}
iface ${internal_iface} inet static
  address ${WEBMIN_IP}
  netmask ${WEBMIN_NETMASK}
EOF
    systemctl restart networking >/dev/null 2>&1 || \
      service networking restart >/dev/null 2>&1 || true
  fi

  if command -v ufw >/dev/null 2>&1; then
    ufw allow "${port}/tcp" >/dev/null || true
  elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --add-port="${port}/tcp" --permanent >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
  elif command -v iptables >/dev/null 2>&1; then
    iptables -C INPUT -p tcp --dport "${port}" -j ACCEPT >/dev/null 2>&1 || \
      iptables -I INPUT -p tcp --dport "${port}" -j ACCEPT >/dev/null 2>&1 || true
  fi
}

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

tmp_dir=$(mktemp -d)
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

configure_network

echo "Downloading Webmin ${WEBMIN_VERSION} from SourceForge..."
curl -L -o "${tmp_dir}/${WEBMIN_TARBALL}" "${WEBMIN_URL}"

echo "Extracting archive..."
tar -xzf "${tmp_dir}/${WEBMIN_TARBALL}" -C "${tmp_dir}"

cd "${tmp_dir}/webmin-${WEBMIN_VERSION}"

echo "Running Webmin setup (accepting defaults)..."
cat <<EOF | ./setup.sh "${INSTALL_DIR}"
${WEBMIN_PORT}
${WEBMIN_LOGIN}
${WEBMIN_PASSWORD}
${WEBMIN_PASSWORD}
${WEBMIN_SSL}
${WEBMIN_START_BOOT}
EOF

echo "Webmin ${WEBMIN_VERSION} installed in ${INSTALL_DIR}."
echo "Login: ${WEBMIN_LOGIN}"
