#!/usr/bin/env bash
set -euo pipefail

# Tworzy VMki:
# host0: attacker, mgmtnet (internet)
# host1: webapp, mgmtnet + ctfnet
# host2: webmin, ctfnet
# host3: postgres, ctfnet
#
# Instalacja tekstowa: --graphics none + console=ttyS0

ISO="${ISO:-/var/lib/libvirt/boot/debian-netinst.iso}"
OSV="${OSV:-debian12}"
CPU_MODEL="${CPU_MODEL:-host-model}"

ensure_iso() {
  [[ -f "$ISO" ]] || { echo "ISO not found: $ISO" >&2; exit 1; }
}

ensure_iso

create_vm() {
  local name="$1"
  local mem="$2"
  local vcpus="$3"
  local disk_gb="$4"
  local nets="$5"

  # Jeśli VM już istnieje, nie nadpisujemy
  if sudo virsh -c qemu:///system dominfo "$name" >/dev/null 2>&1; then
    echo "[i] VM '$name' already exists, skipping"
    return 0
  fi

  echo "[+] Creating: $name"
  # shellcheck disable=SC2086
  sudo virt-install \
    --name "$name" \
    --memory "$mem" --vcpus "$vcpus" --cpu "$CPU_MODEL" \
    --disk "path=/var/lib/libvirt/images/${name}.qcow2,size=${disk_gb},bus=virtio,format=qcow2" \
    --location "$ISO" \
    --extra-args="console=ttyS0,115200n8 serial" \
    $nets \
    --graphics none \
    --console pty,target_type=serial \
    --os-variant "$OSV"
}

# Sieci:
# Uwaga: nets to surowy fragment "--network ... --network ..."
NET_HOST0="--network network=mgmtnet,model=virtio"
NET_HOST1="--network network=mgmtnet,model=virtio --network network=ctfnet,model=virtio"
NET_HOST2="--network network=ctfnet,model=virtio"
NET_HOST3="--network network=ctfnet,model=virtio"

create_vm host0 2048 2 15 "$NET_HOST0"
create_vm host1 4096 2 25 "$NET_HOST1"
create_vm host2 2048 2 15 "$NET_HOST2"
create_vm host3 2048 2 15 "$NET_HOST3"

echo
echo "[+] Done. Domains:"
sudo virsh -c qemu:///system list --all
