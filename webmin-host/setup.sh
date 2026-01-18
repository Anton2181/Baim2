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
WEBMIN_CONFIG_DIR="${WEBMIN_CONFIG_DIR:-/etc/webmin}"
WEBMIN_LOG_DIR="${WEBMIN_LOG_DIR:-/var/webmin}"
WEBMIN_PERL_PATH="${WEBMIN_PERL_PATH:-/usr/bin/perl}"
WEBAPP_IP="${WEBAPP_IP:-192.168.100.10}"
WEBMIN_WEBPREFIX="${WEBMIN_WEBPREFIX:-/admin/infra}"
WEBAPP_HOST="${WEBAPP_HOST:-192.168.100.10}"
WEBMIN_REDIRECT_HOST="${WEBMIN_REDIRECT_HOST:-${WEBAPP_HOST}}"

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
    ufw insert 1 allow from "${WEBAPP_IP}" to any port "${port}" proto tcp >/dev/null || true
    ufw insert 2 deny "${port}/tcp" >/dev/null || true
  elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --add-rich-rule="rule family=ipv4 priority=10 source address=${WEBAPP_IP} port port=${port} protocol=tcp accept" \
      --permanent >/dev/null 2>&1 || true
    firewall-cmd --add-rich-rule="rule family=ipv4 priority=100 port port=${port} protocol=tcp drop" \
      --permanent >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
  elif command -v iptables >/dev/null 2>&1; then
    iptables -C INPUT -p tcp -s "${WEBAPP_IP}" --dport "${port}" -j ACCEPT >/dev/null 2>&1 || \
      iptables -I INPUT -p tcp -s "${WEBAPP_IP}" --dport "${port}" -j ACCEPT >/dev/null 2>&1 || true
    iptables -C INPUT -p tcp --dport "${port}" -j DROP >/dev/null 2>&1 || \
      iptables -A INPUT -p tcp --dport "${port}" -j DROP >/dev/null 2>&1 || true
  fi
}

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

apt-get update -y >/dev/null 2>&1 || true
apt-get install -y curl perl postgresql-client python3.13-venv >/dev/null 2>&1 || true

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
${WEBMIN_CONFIG_DIR}
${WEBMIN_LOG_DIR}
${WEBMIN_PERL_PATH}
${WEBMIN_PORT}
${WEBMIN_LOGIN}
${WEBMIN_PASSWORD}
${WEBMIN_PASSWORD}
${WEBMIN_SSL}
${WEBMIN_START_BOOT}
EOF

if [[ -f /etc/webmin/miniserv.conf ]]; then
  sed -i "/^bind=/d" /etc/webmin/miniserv.conf
  sed -i "/^allow=/d" /etc/webmin/miniserv.conf
  sed -i "/^deny=/d" /etc/webmin/miniserv.conf
  sed -i "/^redirect_prefix=/d" /etc/webmin/miniserv.conf
  sed -i "/^cookiepath=/d" /etc/webmin/miniserv.conf
  sed -i "/^redirect_host=/d" /etc/webmin/miniserv.conf
  sed -i "/^redirect_port=/d" /etc/webmin/miniserv.conf
  {
    echo "bind=${WEBMIN_IP}"
    echo "allow=${WEBAPP_IP} 127.0.0.1"
    echo "redirect_prefix=${WEBMIN_WEBPREFIX}"
    echo "cookiepath=${WEBMIN_WEBPREFIX}"
    echo "redirect_host=${WEBMIN_REDIRECT_HOST}"
    echo "redirect_port=80"
  } >> /etc/webmin/miniserv.conf
fi

if [[ -f /etc/webmin/config ]]; then
  sed -i "/^referers_none=/d" /etc/webmin/config
  sed -i "/^referers=/d" /etc/webmin/config
  sed -i "/^webprefix=/d" /etc/webmin/config
  sed -i "/^webprefixnoredir=/d" /etc/webmin/config
  echo "referers=${WEBAPP_HOST}" >> /etc/webmin/config
  echo "referers_none=0" >> /etc/webmin/config
  echo "webprefix=${WEBMIN_WEBPREFIX}" >> /etc/webmin/config
  echo "webprefixnoredir=1" >> /etc/webmin/config
fi

if [[ -f /etc/webmin/xterm/config ]]; then
  sed -i "/^host=/d" /etc/webmin/xterm/config
  echo "host=${WEBMIN_REDIRECT_HOST}" >> /etc/webmin/xterm/config
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart webmin >/dev/null 2>&1 || true
elif [[ -x /etc/init.d/webmin ]]; then
  /etc/init.d/webmin restart >/dev/null 2>&1 || true
elif [[ -x /etc/webmin/restart ]]; then
  /etc/webmin/restart >/dev/null 2>&1 || true
fi

echo "Webmin ${WEBMIN_VERSION} installed in ${INSTALL_DIR}."
echo "Login: ${WEBMIN_LOGIN}"
