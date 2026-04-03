#!/bin/bash
# Install Arch Linux onto a USB-attached target disk with LUKS2, systemd-boot,
# a Unified Kernel Image (UKI), and Secure Boot signing via sbctl.
#
# Run this from an existing Arch Linux system on the same machine that will boot
# the new disk. The target disk is expected to be attached via USB enclosure.
#
# WARNING: This script DESTROYS all data on the target disk.
#
# Example:
#   sudo TARGET_DISK=/dev/sda USERNAME=vitor HOSTNAME=zygalski TIMEZONE=Europe/Warsaw \
#     ~/.config/arch/install-usb-luks-secureboot.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_SYSTEM_SOURCE="$SCRIPT_DIR/bootstrap-system.sh"

if [[ ! -f "$BOOTSTRAP_SYSTEM_SOURCE" ]]; then
  BOOTSTRAP_SYSTEM_SOURCE="$SCRIPT_DIR/executable_bootstrap-system.sh"
fi

if [[ ! -f "$BOOTSTRAP_SYSTEM_SOURCE" ]]; then
  echo "ERROR: bootstrap-system.sh not found next to $0" >&2
  exit 1
fi

TARGET_DISK="${TARGET_DISK:-}"
USERNAME="${USERNAME:-vitor}"
HOSTNAME_VALUE="${HOSTNAME:-zygalski}"
TIMEZONE_VALUE="${TIMEZONE:-Europe/Warsaw}"
LOCALE_VALUE="${LOCALE:-en_US.UTF-8}"
KEYMAP_VALUE="${KEYMAP:-us}"
ROOT_MAPPER_NAME="${ROOT_MAPPER_NAME:-cryptroot}"
ROOT_FS_TYPE="${ROOT_FS_TYPE:-btrfs}"
ESP_SIZE_MIB="${ESP_SIZE_MIB:-1025}"
MOUNT_ROOT="${MOUNT_ROOT:-/mnt}"
KERNEL_PKG="${KERNEL_PKG:-linux}"
MICROCODE_PKG="${MICROCODE_PKG:-intel-ucode}"
EXTRA_PACKAGES="${EXTRA_PACKAGES:-}"
KERNEL_CMDLINE_DEFAULT="quiet loglevel=3 rd.systemd.show_status=auto rd.udev.log_level=3 vt.global_cursor_default=0 video=2256x1504"
KERNEL_CMDLINE="${KERNEL_CMDLINE:-$KERNEL_CMDLINE_DEFAULT}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: Required command not found: $1" >&2
    exit 1
  }
}

confirm() {
  local prompt="$1"
  read -r -p "$prompt [y/N] " response
  [[ "$response" =~ ^[Yy]$ ]]
}

partition_path() {
  local disk="$1"
  local part="$2"
  if [[ "$disk" =~ nvme[0-9]+n[0-9]+$ ]]; then
    printf '%sp%s' "$disk" "$part"
  else
    printf '%s%s' "$disk" "$part"
  fi
}

cleanup() {
  set +e
  umount "$MOUNT_ROOT/run/host/var/lib/sbctl" 2>/dev/null || true
  umount "$MOUNT_ROOT/boot" 2>/dev/null || true
  umount "$MOUNT_ROOT/.snapshots" 2>/dev/null || true
  umount "$MOUNT_ROOT/home" 2>/dev/null || true
  umount "$MOUNT_ROOT/var/log" 2>/dev/null || true
  umount -R "$MOUNT_ROOT" 2>/dev/null || true
  cryptsetup close "$ROOT_MAPPER_NAME" 2>/dev/null || true
}

trap cleanup EXIT

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Run as root (use sudo)." >&2
    exit 1
  fi
}

require_root

for cmd in lsblk sgdisk parted cryptsetup mkfs.fat mkfs.btrfs btrfs pacstrap genfstab arch-chroot bootctl sbctl blkid; do
  require_cmd "$cmd"
done

if [[ -z "$TARGET_DISK" ]]; then
  echo "ERROR: Set TARGET_DISK, for example TARGET_DISK=/dev/sda" >&2
  lsblk -o NAME,SIZE,MODEL,TYPE,FSTYPE,MOUNTPOINTS
  exit 1
fi

if [[ ! -b "$TARGET_DISK" ]]; then
  echo "ERROR: TARGET_DISK is not a block device: $TARGET_DISK" >&2
  exit 1
fi

ESP_PART="$(partition_path "$TARGET_DISK" 1)"
CRYPT_PART="$(partition_path "$TARGET_DISK" 2)"

cat <<EOF
About to erase and install Arch Linux on:
  TARGET_DISK     $TARGET_DISK
  EFI partition   $ESP_PART
  LUKS partition  $CRYPT_PART
  Username        $USERNAME
  Hostname        $HOSTNAME_VALUE
  Timezone        $TIMEZONE_VALUE
  Locale          $LOCALE_VALUE
  Keymap          $KEYMAP_VALUE
  Root FS         $ROOT_FS_TYPE
  Kernel          $KERNEL_PKG
EOF

lsblk -o NAME,SIZE,MODEL,TYPE,FSTYPE,MOUNTPOINTS "$TARGET_DISK"

echo
if ! confirm "Continue? This will destroy all data on $TARGET_DISK."; then
  echo "Aborted."
  exit 1
fi

echo "==> Installing required host packages..."
pacman -Syu --needed --noconfirm arch-install-scripts dosfstools btrfs-progs cryptsetup mkinitcpio efibootmgr sbctl "$MICROCODE_PKG"

if [[ -n "$EXTRA_PACKAGES" ]]; then
  pacman -S --needed --noconfirm $EXTRA_PACKAGES
fi

echo "==> Partitioning target disk..."
sgdisk --zap-all "$TARGET_DISK"
parted -s "$TARGET_DISK" mklabel gpt
parted -s "$TARGET_DISK" mkpart ESP fat32 1MiB "${ESP_SIZE_MIB}MiB"
parted -s "$TARGET_DISK" set 1 esp on
parted -s "$TARGET_DISK" mkpart cryptroot "${ESP_SIZE_MIB}MiB" 100%

echo "==> Creating LUKS2 container..."
cryptsetup luksFormat --type luks2 "$CRYPT_PART"
cryptsetup open "$CRYPT_PART" "$ROOT_MAPPER_NAME"

echo "==> Creating filesystems..."
mkfs.fat -F32 "$ESP_PART"
case "$ROOT_FS_TYPE" in
  btrfs)
    mkfs.btrfs -f -O ^block-group-tree "/dev/mapper/$ROOT_MAPPER_NAME"
    ;;
  *)
    echo "ERROR: Unsupported ROOT_FS_TYPE: $ROOT_FS_TYPE" >&2
    exit 1
    ;;
esac

echo "==> Mounting target system..."
mkdir -p "$MOUNT_ROOT"
mount "/dev/mapper/$ROOT_MAPPER_NAME" "$MOUNT_ROOT"
btrfs subvolume create "$MOUNT_ROOT/@"
btrfs subvolume create "$MOUNT_ROOT/@home"
btrfs subvolume create "$MOUNT_ROOT/@snapshots"
btrfs subvolume create "$MOUNT_ROOT/@var_log"
btrfs subvolume list "$MOUNT_ROOT"
umount "$MOUNT_ROOT"

mount -o subvol=@,compress=zstd,noatime "/dev/mapper/$ROOT_MAPPER_NAME" "$MOUNT_ROOT"
mkdir -p "$MOUNT_ROOT/home" "$MOUNT_ROOT/.snapshots" "$MOUNT_ROOT/var/log"
mount -o subvol=@home,compress=zstd,noatime "/dev/mapper/$ROOT_MAPPER_NAME" "$MOUNT_ROOT/home"
mount -o subvol=@snapshots,compress=zstd,noatime "/dev/mapper/$ROOT_MAPPER_NAME" "$MOUNT_ROOT/.snapshots"
mount -o subvol=@var_log,compress=zstd,noatime "/dev/mapper/$ROOT_MAPPER_NAME" "$MOUNT_ROOT/var/log"
mkdir -p "$MOUNT_ROOT/boot"
mount "$ESP_PART" "$MOUNT_ROOT/boot"

echo "==> Installing base system..."
pacstrap -K "$MOUNT_ROOT" \
  base base-devel "$KERNEL_PKG" linux-firmware "$MICROCODE_PKG" \
  mkinitcpio systemd sbctl efibootmgr btrfs-progs \
  git neovim vim fish sudo networkmanager \
  pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber \
  xdg-user-dirs xdg-utils wget curl openssh rsync jq man-db man-pages

echo "==> Generating fstab..."
genfstab -U "$MOUNT_ROOT" >> "$MOUNT_ROOT/etc/fstab"

LUKS_UUID="$(blkid -s UUID -o value "$CRYPT_PART")"
cp "$BOOTSTRAP_SYSTEM_SOURCE" "$MOUNT_ROOT/root/bootstrap-system.sh"
chmod +x "$MOUNT_ROOT/root/bootstrap-system.sh"

echo "==> Entering chroot for final configuration..."
for host_key_path in \
  /var/lib/sbctl/GUID \
  /var/lib/sbctl/keys/PK/PK.key \
  /var/lib/sbctl/keys/PK/PK.pem \
  /var/lib/sbctl/keys/KEK/KEK.key \
  /var/lib/sbctl/keys/KEK/KEK.pem \
  /var/lib/sbctl/keys/db/db.key \
  /var/lib/sbctl/keys/db/db.pem; do
  if [[ ! -f "$host_key_path" ]]; then
    echo "ERROR: Host sbctl key material missing: $host_key_path" >&2
    exit 1
  fi
done
mkdir -p "$MOUNT_ROOT/run/host/var/lib/sbctl"
mount --bind /var/lib/sbctl "$MOUNT_ROOT/run/host/var/lib/sbctl"
arch-chroot "$MOUNT_ROOT" /usr/bin/env \
  USERNAME="$USERNAME" \
  HOSTNAME_VALUE="$HOSTNAME_VALUE" \
  TIMEZONE_VALUE="$TIMEZONE_VALUE" \
  LOCALE_VALUE="$LOCALE_VALUE" \
  KEYMAP_VALUE="$KEYMAP_VALUE" \
  ROOT_MAPPER_NAME="$ROOT_MAPPER_NAME" \
  LUKS_UUID="$LUKS_UUID" \
  KERNEL_PKG="$KERNEL_PKG" \
  KERNEL_CMDLINE="$KERNEL_CMDLINE" \
  /root/bootstrap-system.sh
rm -f "$MOUNT_ROOT/root/bootstrap-system.sh"

echo
echo "==> Install completed successfully."
echo "Unmounting target."
cleanup
trap - EXIT

echo "Swap the new NVMe into the laptop and boot it."
