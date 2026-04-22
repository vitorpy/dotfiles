#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${1:-$SCRIPT_DIR/out}"
WORK_DIR="$(mktemp -d /tmp/archiso-mediaserver.XXXXXX)"
RELENG_DIR="/usr/share/archiso/configs/releng"

trap 'rm -rf "$WORK_DIR"' EXIT

if [[ ! -d "$RELENG_DIR" ]]; then
    echo "archiso not installed - run: sudo pacman -S archiso"
    exit 1
fi

echo "==> Copying releng base profile"
cp -r "$RELENG_DIR" "$WORK_DIR/profile"

echo "==> Overlaying customizations"
cp -rT "$SCRIPT_DIR/airootfs" "$WORK_DIR/profile/airootfs"
cp -rT "$SCRIPT_DIR/efiboot" "$WORK_DIR/profile/efiboot"

echo "==> Enabling auto-install service"
mkdir -p "$WORK_DIR/profile/airootfs/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/auto-install.service \
    "$WORK_DIR/profile/airootfs/etc/systemd/system/multi-user.target.wants/auto-install.service"

chmod 755 "$WORK_DIR/profile/airootfs/root/install.sh"
chmod 755 "$WORK_DIR/profile/airootfs/root/install-chroot.sh"

echo "==> Building ISO (output: $OUTPUT_DIR)"
mkdir -p "$OUTPUT_DIR"
mkarchiso -v -w "$WORK_DIR/work" -o "$OUTPUT_DIR" "$WORK_DIR/profile"

echo "==> Done: $(ls "$OUTPUT_DIR"/*.iso)"
