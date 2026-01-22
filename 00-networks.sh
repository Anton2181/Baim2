#!/usr/bin/env bash
set -euo pipefail

# Tworzy dwie sieci libvirt:
# - mgmtnet: NAT + DHCP (internet)
# - ctfnet : NAT (opcjonalnie) + DHCP (my i tak ustawiamy statyczne IP w VM)
#
# Uwaga: libvirt "network" domyślnie używa NAT, więc mgmtnet da internet VMkom,
# jeśli w VM jest DHCP/route.
#
# Adresacja:
# mgmtnet: 192.168.50.0/24, GW 192.168.50.1
# ctfnet : 192.168.100.0/24, GW 192.168.100.1 (libvirt), ale w wariancie 2
#          host2/host3 zwykle i tak nie wychodzą na świat.

MGMT_NET_NAME="mgmtnet"
MGMT_NET_ADDR="192.168.50.1"
MGMT_NET_MASK="255.255.255.0"
MGMT_DHCP_START="192.168.50.100"
MGMT_DHCP_END="192.168.50.199"

CTF_NET_NAME="ctfnet"
CTF_NET_ADDR="192.168.100.1"
CTF_NET_MASK="255.255.255.0"
CTF_DHCP_START="192.168.100.100"
CTF_DHCP_END="192.168.100.199"

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }
}

need virsh

define_net() {
  local name="$1"
  local xml="$2"

  if virsh net-info "$name" >/dev/null 2>&1; then
    echo "[i] Network '$name' already exists"
    return 0
  fi

  echo "[+] Defining network: $name"
  virsh net-define /dev/stdin <<<"$xml"
  virsh net-start "$name"
  virsh net-autostart "$name"
}

MGMT_XML="$(cat <<EOF
<network>
  <name>${MGMT_NET_NAME}</name>
  <forward mode='nat'/>
  <bridge name='virbr50' stp='on' delay='0'/>
  <ip address='${MGMT_NET_ADDR}' netmask='${MGMT_NET_MASK}'>
    <dhcp>
      <range start='${MGMT_DHCP_START}' end='${MGMT_DHCP_END}'/>
    </dhcp>
  </ip>
</network>
EOF
)"

CTF_XML="$(cat <<EOF
<network>
  <name>${CTF_NET_NAME}</name>
  <bridge name='virbr100' stp='on' delay='0'/>
  <ip address='${CTF_NET_ADDR}' netmask='${CTF_NET_MASK}'>
    <dhcp>
      <range start='${CTF_DHCP_START}' end='${CTF_DHCP_END}'/>
    </dhcp>
  </ip>
</network>
EOF
)"

define_net "$MGMT_NET_NAME" "$MGMT_XML"
define_net "$CTF_NET_NAME" "$CTF_XML"

echo
echo "[+] Done. Networks:"
virsh net-list --all
