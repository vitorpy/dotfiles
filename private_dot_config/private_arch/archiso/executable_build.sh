#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_ONLY=false

if [[ "${1:-}" == "--check" ]]; then
    CHECK_ONLY=true
    shift
fi

OUTPUT_DIR="${1:-$SCRIPT_DIR/out}"
WORK_DIR="$(mktemp -d /tmp/archiso-mediaserver.XXXXXX)"
RELENG_DIR="/usr/share/archiso/configs/releng"
CONFIG_FILE="$SCRIPT_DIR/airootfs/etc/mediaserver-install.conf"

resolve_profile_file() {
    local rel_path="$1"
    local projected="$SCRIPT_DIR/$rel_path"
    local rel_dir
    local rel_base
    local source_named

    rel_dir="$(dirname "$rel_path")"
    rel_base="$(basename "$rel_path")"
    source_named="$SCRIPT_DIR/$rel_dir/executable_$rel_base"

    if [[ -f "$projected" ]]; then
        printf '%s\n' "$projected"
    elif [[ -f "$source_named" ]]; then
        printf '%s\n' "$source_named"
    else
        return 1
    fi
}

normalize_executable_file() {
    local rel_path="$1"
    local target="$WORK_DIR/profile/$rel_path"
    local rel_dir
    local rel_base
    local source_named

    rel_dir="$(dirname "$rel_path")"
    rel_base="$(basename "$rel_path")"
    source_named="$WORK_DIR/profile/$rel_dir/executable_$rel_base"

    if [[ -f "$source_named" && ! -f "$target" ]]; then
        mv "$source_named" "$target"
    fi
}

trap 'rm -rf "$WORK_DIR"' EXIT

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "missing installer config: $CONFIG_FILE" >&2
    exit 1
fi

INSTALL_SCRIPT="$(resolve_profile_file "airootfs/root/install.sh")"
CHROOT_SCRIPT="$(resolve_profile_file "airootfs/root/install-chroot.sh")"

bash -n "$CONFIG_FILE"
bash -n "$INSTALL_SCRIPT"
bash -n "$CHROOT_SCRIPT"

if [[ "$CHECK_ONLY" == "true" ]]; then
    echo "==> ArchISO mediaserver profile syntax OK"
    exit 0
fi

if [[ ! -d "$RELENG_DIR" ]]; then
    echo "archiso not installed - run: sudo pacman -S archiso"
    exit 1
fi

echo "==> Copying releng base profile"
cp -r "$RELENG_DIR" "$WORK_DIR/profile"

echo "==> Overlaying customizations"
cp -rT "$SCRIPT_DIR/airootfs" "$WORK_DIR/profile/airootfs"
cp -rT "$SCRIPT_DIR/efiboot" "$WORK_DIR/profile/efiboot"
normalize_executable_file "airootfs/root/install.sh"
normalize_executable_file "airootfs/root/install-chroot.sh"

echo "==> Enabling auto-install service"
mkdir -p "$WORK_DIR/profile/airootfs/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/auto-install.service \
    "$WORK_DIR/profile/airootfs/etc/systemd/system/multi-user.target.wants/auto-install.service"

chmod 755 "$WORK_DIR/profile/airootfs/root/install.sh"
chmod 755 "$WORK_DIR/profile/airootfs/root/install-chroot.sh"
chmod 644 "$WORK_DIR/profile/airootfs/etc/mediaserver-install.conf"

echo "==> Building ISO (output: $OUTPUT_DIR)"
mkdir -p "$OUTPUT_DIR"
mkarchiso -v -w "$WORK_DIR/work" -o "$OUTPUT_DIR" "$WORK_DIR/profile"

echo "==> Done: $(ls "$OUTPUT_DIR"/*.iso)"
