#!/bin/bash
set -euo pipefail

CONFIG=/etc/mediaserver-install.conf

# shellcheck source=/dev/null
source "$CONFIG"

ln -sf "/usr/share/zoneinfo/$INSTALL_TIMEZONE" /etc/localtime
hwclock --systohc

locale-gen

if ! id -u "$INSTALL_USERNAME" >/dev/null 2>&1; then
    useradd -m -G wheel -s "$INSTALL_USER_SHELL" "$INSTALL_USERNAME"
fi
passwd -l "$INSTALL_USERNAME"

cat > /etc/sudoers.d/99-vitorpy-bootstrap <<EOF
${INSTALL_USERNAME} ALL=(ALL:ALL) NOPASSWD: ALL
EOF
chmod 440 /etc/sudoers.d/99-vitorpy-bootstrap
visudo -cf /etc/sudoers.d/10-wheel
visudo -cf /etc/sudoers.d/99-vitorpy-bootstrap

install -d -m 700 -o "$INSTALL_USERNAME" -g "$INSTALL_USERNAME" /home/"$INSTALL_USERNAME"/.ssh
install -m 600 -o "$INSTALL_USERNAME" -g "$INSTALL_USERNAME" /dev/null /home/"$INSTALL_USERNAME"/.ssh/authorized_keys
for key in "${INSTALL_AUTHORIZED_KEYS[@]}"; do
    grep -qxF "$key" /home/"$INSTALL_USERNAME"/.ssh/authorized_keys \
        || printf '%s\n' "$key" >> /home/"$INSTALL_USERNAME"/.ssh/authorized_keys
done
chown "$INSTALL_USERNAME":"$INSTALL_USERNAME" /home/"$INSTALL_USERNAME"/.ssh/authorized_keys

mkinitcpio -P

systemctl enable NetworkManager sshd NetworkManager-wait-online.service

bootctl install --esp-path=/boot
