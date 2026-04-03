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
  if mountpoint -q "$MOUNT_ROOT/boot"; then
    umount "$MOUNT_ROOT/boot"
  fi
  if mountpoint -q "$MOUNT_ROOT"; then
    umount -R "$MOUNT_ROOT"
  fi
  if cryptsetup status "$ROOT_MAPPER_NAME" >/dev/null 2>&1; then
    cryptsetup close "$ROOT_MAPPER_NAME"
  fi
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

cat > "$MOUNT_ROOT/root/post-install.sh" <<'EOS'
#!/bin/bash
set -euo pipefail

USERNAME="__USERNAME__"
HOSTNAME_VALUE="__HOSTNAME__"
TIMEZONE_VALUE="__TIMEZONE__"
LOCALE_VALUE="__LOCALE__"
KEYMAP_VALUE="__KEYMAP__"
ROOT_MAPPER_NAME="__ROOT_MAPPER_NAME__"
LUKS_UUID="__LUKS_UUID__"
KERNEL_PKG="__KERNEL_PKG__"
MICROCODE_PKG="__MICROCODE_PKG__"
KERNEL_CMDLINE="__KERNEL_CMDLINE__"

ln -sf "/usr/share/zoneinfo/$TIMEZONE_VALUE" /etc/localtime
hwclock --systohc

sed -i "s/^#${LOCALE_VALUE} ${LOCALE_VALUE#*.}/${LOCALE_VALUE} ${LOCALE_VALUE#*.}/" /etc/locale.gen || true
if ! grep -q "^${LOCALE_VALUE} " /etc/locale.gen; then
  echo "${LOCALE_VALUE} ${LOCALE_VALUE#*.}" >> /etc/locale.gen
fi
locale-gen
printf 'LANG=%s\n' "$LOCALE_VALUE" > /etc/locale.conf
printf 'KEYMAP=%s\n' "$KEYMAP_VALUE" > /etc/vconsole.conf
printf '%s\n' "$HOSTNAME_VALUE" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 ${HOSTNAME_VALUE}.localdomain ${HOSTNAME_VALUE}
EOF

systemctl enable NetworkManager
systemctl enable sshd

if ! id -u "$USERNAME" >/dev/null 2>&1; then
  useradd -m -G wheel -s /usr/bin/fish "$USERNAME"
fi
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
sed -i 's/^#%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "Set root password:"
passwd

echo "Set password for $USERNAME:"
passwd "$USERNAME"

if grep -q '^HOOKS=' /etc/mkinitcpio.conf; then
  sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
else
  printf '\nHOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)\n' >> /etc/mkinitcpio.conf
fi

cat > /etc/kernel/cmdline <<EOF
${KERNEL_CMDLINE} cryptdevice=UUID=${LUKS_UUID}:${ROOT_MAPPER_NAME} root=/dev/mapper/${ROOT_MAPPER_NAME} rootflags=subvol=@ rw
EOF

mkdir -p /boot/EFI/Linux
cat > "/etc/mkinitcpio.d/${KERNEL_PKG}.preset" <<EOF
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-${KERNEL_PKG}"

PRESETS=('default')

default_uki="/boot/EFI/Linux/arch-linux.efi"
default_options="--cmdline /etc/kernel/cmdline"
EOF

mkinitcpio -P

bootctl install
mkdir -p /boot/loader /boot/loader/entries
cat > /boot/loader/loader.conf <<EOF
default arch
timeout 3
console-mode max
editor no
EOF
cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux
efi     /EFI/Linux/arch-linux.efi
EOF

sbctl create-keys
sbctl enroll-keys -m
sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
sbctl sign -s /boot/EFI/Linux/arch-linux.efi
mkdir -p /boot/EFI/BOOT
cp /boot/EFI/systemd/systemd-bootx64.efi /boot/EFI/BOOT/BOOTX64.EFI
sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
sbctl verify

echo
echo "Post-install complete."
echo "After shutdown, swap the disks and enable Secure Boot in firmware if needed."
EOS

sed -i "s|__USERNAME__|$USERNAME|g" "$MOUNT_ROOT/root/post-install.sh"
sed -i "s|__HOSTNAME__|$HOSTNAME_VALUE|g" "$MOUNT_ROOT/root/post-install.sh"
sed -i "s|__TIMEZONE__|$TIMEZONE_VALUE|g" "$MOUNT_ROOT/root/post-install.sh"
sed -i "s|__LOCALE__|$LOCALE_VALUE|g" "$MOUNT_ROOT/root/post-install.sh"
sed -i "s|__KEYMAP__|$KEYMAP_VALUE|g" "$MOUNT_ROOT/root/post-install.sh"
sed -i "s|__ROOT_MAPPER_NAME__|$ROOT_MAPPER_NAME|g" "$MOUNT_ROOT/root/post-install.sh"
sed -i "s|__LUKS_UUID__|$LUKS_UUID|g" "$MOUNT_ROOT/root/post-install.sh"
sed -i "s|__KERNEL_PKG__|$KERNEL_PKG|g" "$MOUNT_ROOT/root/post-install.sh"
sed -i "s|__MICROCODE_PKG__|$MICROCODE_PKG|g" "$MOUNT_ROOT/root/post-install.sh"
sed -i "s|__KERNEL_CMDLINE__|$KERNEL_CMDLINE|g" "$MOUNT_ROOT/root/post-install.sh"
chmod +x "$MOUNT_ROOT/root/post-install.sh"

echo "==> Entering chroot for final configuration..."
arch-chroot "$MOUNT_ROOT" /root/post-install.sh
rm -f "$MOUNT_ROOT/root/post-install.sh"

echo
echo "==> Install completed successfully."
echo "Unmounting target."
cleanup
trap - EXIT

echo "Swap the new NVMe into the laptop and boot it."
