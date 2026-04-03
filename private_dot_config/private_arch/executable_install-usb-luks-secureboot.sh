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
BOOTSTRAP_MIGRATE_HOME_SOURCE="$SCRIPT_DIR/bootstrap-migrate-home.sh"

if [[ ! -f "$BOOTSTRAP_SYSTEM_SOURCE" ]]; then
  BOOTSTRAP_SYSTEM_SOURCE="$SCRIPT_DIR/executable_bootstrap-system.sh"
fi

if [[ ! -f "$BOOTSTRAP_MIGRATE_HOME_SOURCE" ]]; then
  BOOTSTRAP_MIGRATE_HOME_SOURCE="$SCRIPT_DIR/executable_bootstrap-migrate-home.sh"
fi

if [[ ! -f "$BOOTSTRAP_SYSTEM_SOURCE" ]]; then
  echo "ERROR: bootstrap-system.sh not found next to $0" >&2
  exit 1
fi

if [[ ! -f "$BOOTSTRAP_MIGRATE_HOME_SOURCE" ]]; then
  echo "ERROR: bootstrap-migrate-home.sh not found next to $0" >&2
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
HOME_MIGRATION_MODE="${HOME_MIGRATION_MODE:-ask}"
HOME_MIGRATION_SOURCE="${HOME_MIGRATION_SOURCE:-/home/$USERNAME}"
START_STAGE="${START_STAGE:-full}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: Required command not found: $1" >&2
    exit 1
  }
}

require_stage() {
  case "$START_STAGE" in
    full|mount_existing|system_bootstrap|home_migration)
      ;;
    *)
      echo "ERROR: Unsupported START_STAGE: $START_STAGE" >&2
      echo "Use one of: full, mount_existing, system_bootstrap, home_migration" >&2
      exit 1
      ;;
  esac
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
  umount "$MOUNT_ROOT/boot" 2>/dev/null || true
  umount "$MOUNT_ROOT/.snapshots" 2>/dev/null || true
  umount "$MOUNT_ROOT/home" 2>/dev/null || true
  umount "$MOUNT_ROOT/var/log" 2>/dev/null || true
  umount -R "$MOUNT_ROOT" 2>/dev/null || true
  cryptsetup close "$ROOT_MAPPER_NAME" 2>/dev/null || true
}

open_existing_luks() {
  if cryptsetup status "$ROOT_MAPPER_NAME" >/dev/null 2>&1; then
    return
  fi
  echo "==> Opening existing LUKS2 container..."
  cryptsetup open "$CRYPT_PART" "$ROOT_MAPPER_NAME"
}

mount_existing_target() {
  echo "==> Mounting existing target system..."
  mkdir -p "$MOUNT_ROOT"
  mount -o subvol=@,compress=zstd,noatime "/dev/mapper/$ROOT_MAPPER_NAME" "$MOUNT_ROOT"
  mkdir -p "$MOUNT_ROOT/home" "$MOUNT_ROOT/.snapshots" "$MOUNT_ROOT/var/log" "$MOUNT_ROOT/boot"
  mount -o subvol=@home,compress=zstd,noatime "/dev/mapper/$ROOT_MAPPER_NAME" "$MOUNT_ROOT/home"
  mount -o subvol=@snapshots,compress=zstd,noatime "/dev/mapper/$ROOT_MAPPER_NAME" "$MOUNT_ROOT/.snapshots"
  mount -o subvol=@var_log,compress=zstd,noatime "/dev/mapper/$ROOT_MAPPER_NAME" "$MOUNT_ROOT/var/log"
  mount "$ESP_PART" "$MOUNT_ROOT/boot"
}

trap cleanup EXIT

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Run as root (use sudo)." >&2
    exit 1
  fi
}

require_root
require_stage

for cmd in lsblk sgdisk parted cryptsetup mkfs.fat mkfs.btrfs btrfs pacstrap genfstab arch-chroot bootctl sbctl blkid rsync; do
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
  Start stage     $START_STAGE
  Home migrate    $HOME_MIGRATION_MODE ($HOME_MIGRATION_SOURCE)
EOF

lsblk -o NAME,SIZE,MODEL,TYPE,FSTYPE,MOUNTPOINTS "$TARGET_DISK"

echo
case "$START_STAGE" in
  full)
    if ! confirm "Continue? This will destroy all data on $TARGET_DISK."; then
      echo "Aborted."
      exit 1
    fi
    ;;
  *)
    if ! confirm "Continue? This will resume from $START_STAGE and reuse the existing target on $TARGET_DISK."; then
      echo "Aborted."
      exit 1
    fi
    ;;
esac

echo "==> Installing required host packages..."
pacman -Syu --needed --noconfirm arch-install-scripts dosfstools btrfs-progs cryptsetup mkinitcpio efibootmgr sbctl rsync "$MICROCODE_PKG"

if [[ -n "$EXTRA_PACKAGES" ]]; then
  pacman -S --needed --noconfirm $EXTRA_PACKAGES
fi

case "$START_STAGE" in
  full)
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

    mount_existing_target

    echo "==> Installing base system..."
    pacstrap -K "$MOUNT_ROOT" \
      base base-devel "$KERNEL_PKG" linux-firmware "$MICROCODE_PKG" \
      mkinitcpio systemd sbctl efibootmgr btrfs-progs \
      git neovim vim fish sudo networkmanager \
      pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber \
      xdg-user-dirs xdg-utils wget curl openssh rsync jq man-db man-pages

    echo "==> Generating fstab..."
    genfstab -U "$MOUNT_ROOT" >> "$MOUNT_ROOT/etc/fstab"
    ;;
  mount_existing|system_bootstrap|home_migration)
    open_existing_luks
    mount_existing_target
    ;;
esac

if [[ "$START_STAGE" == "mount_existing" ]]; then
  echo "==> Installing base system..."
  pacstrap -K "$MOUNT_ROOT" \
    base base-devel "$KERNEL_PKG" linux-firmware "$MICROCODE_PKG" \
    mkinitcpio systemd sbctl efibootmgr btrfs-progs \
    git neovim vim fish sudo networkmanager \
    pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber \
    xdg-user-dirs xdg-utils wget curl openssh rsync jq man-db man-pages

  echo "==> Regenerating fstab..."
  genfstab -U "$MOUNT_ROOT" > "$MOUNT_ROOT/etc/fstab"
fi

LUKS_UUID="$(blkid -s UUID -o value "$CRYPT_PART")"
if [[ "$START_STAGE" == "full" || "$START_STAGE" == "mount_existing" || "$START_STAGE" == "system_bootstrap" ]]; then
  mkdir -p "$MOUNT_ROOT/var/lib/sbctl/keys"
  cp /var/lib/sbctl/GUID "$MOUNT_ROOT/var/lib/sbctl/GUID"
  cp -a /var/lib/sbctl/keys/. "$MOUNT_ROOT/var/lib/sbctl/keys/"
  rm -f "$MOUNT_ROOT/var/lib/sbctl/files.json" "$MOUNT_ROOT/var/lib/sbctl/bundles.json"
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
fi

should_migrate_home=false
if [[ "$START_STAGE" != "full" && "$START_STAGE" != "mount_existing" && "$START_STAGE" != "system_bootstrap" && "$START_STAGE" != "home_migration" ]]; then
  echo "ERROR: Unexpected START_STAGE: $START_STAGE" >&2
  exit 1
fi

if [[ "$START_STAGE" == "full" || "$START_STAGE" == "mount_existing" || "$START_STAGE" == "system_bootstrap" || "$START_STAGE" == "home_migration" ]]; then
  case "$HOME_MIGRATION_MODE" in
    always)
      should_migrate_home=true
      ;;
    ask)
      if [[ -d "$HOME_MIGRATION_SOURCE" ]]; then
        echo
        if confirm "Copy $HOME_MIGRATION_SOURCE into the target home for $USERNAME?"; then
          should_migrate_home=true
        fi
      else
        echo "==> Skipping home migration; source does not exist: $HOME_MIGRATION_SOURCE"
      fi
      ;;
    never)
      ;;
    *)
      echo "ERROR: Unsupported HOME_MIGRATION_MODE: $HOME_MIGRATION_MODE (use ask, always, or never)" >&2
      exit 1
      ;;
  esac

  if [[ "$should_migrate_home" == true ]]; then
    if [[ ! -d "$HOME_MIGRATION_SOURCE" ]]; then
      echo "ERROR: HOME_MIGRATION_SOURCE does not exist: $HOME_MIGRATION_SOURCE" >&2
      exit 1
    fi
    "$BOOTSTRAP_MIGRATE_HOME_SOURCE" "$HOME_MIGRATION_SOURCE" "$MOUNT_ROOT/home/$USERNAME" "$USERNAME"
  fi
fi

echo
echo "==> Install completed successfully."
echo "Unmounting target."
cleanup
trap - EXIT

echo "Swap the new NVMe into the laptop and boot it."
