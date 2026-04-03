#!/bin/bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: Required environment variable not set: $name" >&2
    exit 1
  fi
}

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "ERROR: Required file not found: $path" >&2
    exit 1
  fi
}

for env_name in \
  USERNAME \
  HOSTNAME_VALUE \
  TIMEZONE_VALUE \
  LOCALE_VALUE \
  KEYMAP_VALUE \
  ROOT_MAPPER_NAME \
  LUKS_UUID \
  KERNEL_PKG \
  KERNEL_CMDLINE; do
  require_env "$env_name"
done

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

for key_path in \
  /var/lib/sbctl/GUID \
  /var/lib/sbctl/keys/PK/PK.key \
  /var/lib/sbctl/keys/PK/PK.pem \
  /var/lib/sbctl/keys/KEK/KEK.key \
  /var/lib/sbctl/keys/KEK/KEK.pem \
  /var/lib/sbctl/keys/db/db.key \
  /var/lib/sbctl/keys/db/db.pem; do
  require_file "$key_path"
done

sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
sbctl sign -s /boot/EFI/Linux/arch-linux.efi
mkdir -p /boot/EFI/BOOT
cp /boot/EFI/systemd/systemd-bootx64.efi /boot/EFI/BOOT/BOOTX64.EFI
sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
sbctl verify

echo
echo "System bootstrap complete."
