#!/bin/bash
set -euo pipefail

USERNAME="vitorpy"

ln -sf /usr/share/zoneinfo/Europe/Warsaw /etc/localtime
hwclock --systohc

locale-gen

useradd -m -G wheel -s /usr/bin/zsh "$USERNAME"
passwd -l "$USERNAME"

install -d -m 700 /home/"$USERNAME"/.ssh
cat > /home/"$USERNAME"/.ssh/authorized_keys <<'KEYS'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEjbmkLFQ7T6sLQ9DaeNeW8KB42RjHBvIowNz892tJN5 vitorpy@zygalski
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJAKVxPIZpwFMNX+gH1PmuIHqrlP+vUftjmYYfZJFYxo tito
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICCHiLKhovfixpOHPCnLzOsdRIUad248KhnBRA1ETUEd aur
KEYS
chmod 600 /home/"$USERNAME"/.ssh/authorized_keys
chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"/.ssh

mkinitcpio -P

systemctl enable NetworkManager sshd

bootctl install
