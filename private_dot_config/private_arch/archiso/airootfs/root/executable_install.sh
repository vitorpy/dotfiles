#!/bin/bash
set -euo pipefail

LOG=/root/install.log
exec > >(tee -a "$LOG") 2>&1

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "==> Starting automated mediaserver installation"

log "Waiting for network connectivity..."
until curl -s --max-time 5 https://archlinux.org > /dev/null 2>&1; do
    sleep 3
done
log "Network ready"

DISK=$(lsblk -dpno NAME,TYPE | awk '$2=="disk" && /nvme/{print $1; exit}')
if [[ -z "$DISK" ]]; then
    log "ERROR: no NVMe disk found"
    systemctl halt
fi
log "Target disk: $DISK"

EFI_PART="${DISK}p1"
ROOT_PART="${DISK}p2"

log "Partitioning $DISK"
wipefs -af "$DISK"
sgdisk --zap-all "$DISK"
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:EFI "$DISK"
sgdisk -n 2:0:0 -t 2:8300 -c 2:root "$DISK"
partprobe "$DISK"
sleep 2

log "Formatting partitions"
mkfs.fat -F32 -n EFI "$EFI_PART"
mkfs.ext4 -L root -F "$ROOT_PART"

log "Mounting"
mount "$ROOT_PART" /mnt
mount --mkdir "$EFI_PART" /mnt/boot

log "Installing base system via pacstrap"
pacstrap -K /mnt \
    base linux linux-firmware intel-ucode \
    networkmanager openssh sudo \
    efibootmgr git zsh

log "Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

log "Configuring system"

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /mnt/etc/locale.gen
printf 'LANG=en_US.UTF-8\n' > /mnt/etc/locale.conf

printf 'mediaserver\n' > /mnt/etc/hostname
printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 mediaserver.localdomain mediaserver\n' \
    > /mnt/etc/hosts

printf '%%wheel ALL=(ALL:ALL) NOPASSWD: ALL\n' > /mnt/etc/sudoers.d/10-wheel
chmod 440 /mnt/etc/sudoers.d/10-wheel

mkdir -p /mnt/boot/loader/entries
printf 'default arch.conf\ntimeout 3\nconsole-mode max\neditor no\n' \
    > /mnt/boot/loader/loader.conf

ROOT_PARTUUID=$(blkid -s PARTUUID -o value "$ROOT_PART")
printf 'title   Arch Linux\nlinux   /vmlinuz-linux\ninitrd  /intel-ucode.img\ninitrd  /initramfs-linux.img\noptions root=PARTUUID=%s rw quiet\n' \
    "$ROOT_PARTUUID" > /mnt/boot/loader/entries/arch.conf

log "Running chroot setup"
cp /root/install-chroot.sh /mnt/root/install-chroot.sh
arch-chroot /mnt bash /root/install-chroot.sh
rm /mnt/root/install-chroot.sh

log "==> Installation complete, rebooting in 5 seconds"
sleep 5
reboot
