#!/usr/bin/env bash
set -euo pipefail

WEBMIN_VERSION="1.920"
WEBMIN_TARBALL="webmin-${WEBMIN_VERSION}.tar.gz"
WEBMIN_URL="https://sourceforge.net/projects/webadmin/files/webmin/${WEBMIN_VERSION}/${WEBMIN_TARBALL}"
INSTALL_DIR="/usr/local/webmin"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

tmp_dir=$(mktemp -d)
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

echo "Downloading Webmin ${WEBMIN_VERSION} from SourceForge..."
curl -L -o "${tmp_dir}/${WEBMIN_TARBALL}" "${WEBMIN_URL}"

echo "Extracting archive..."
tar -xzf "${tmp_dir}/${WEBMIN_TARBALL}" -C "${tmp_dir}"

cd "${tmp_dir}/webmin-${WEBMIN_VERSION}"

echo "Running Webmin setup (accepting defaults)..."
yes "" | ./setup.sh "${INSTALL_DIR}"

echo "Webmin ${WEBMIN_VERSION} installed in ${INSTALL_DIR}."
