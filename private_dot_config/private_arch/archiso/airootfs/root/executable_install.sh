#!/bin/bash
set -euo pipefail

CONFIG=/etc/mediaserver-install.conf
LOG=/root/install.log

if [[ ! -f "$CONFIG" ]]; then
    echo "missing installer config: $CONFIG" >&2
    systemctl halt
fi

# shellcheck source=/dev/null
source "$CONFIG"

exec > >(tee -a "$LOG") 2>&1

log() { echo "[$(date '+%H:%M:%S')] $*"; }
fail() {
    log "ERROR: $*"
    systemctl halt
}

select_target_disk() {
    if [[ -n "${INSTALL_TARGET_DISK:-}" ]]; then
        [[ -b "$INSTALL_TARGET_DISK" ]] || fail "configured disk is not a block device: $INSTALL_TARGET_DISK"
        printf '%s\n' "$INSTALL_TARGET_DISK"
        return
    fi

    lsblk -dpno NAME,TYPE | awk -v pattern="$INSTALL_TARGET_DISK_REGEX" '$2=="disk" && $1 ~ pattern { print $1; exit }'
}

partition_path() {
    local disk="$1"
    local number="$2"

    if [[ "$disk" =~ [0-9]$ ]]; then
        printf '%sp%s\n' "$disk" "$number"
    else
        printf '%s%s\n' "$disk" "$number"
    fi
}

write_first_boot_service() {
    [[ "${INSTALL_FIRST_BOOT_ANSIBLE:-false}" == "true" ]] || return

    log "Installing first-boot Ansible convergence service"
    install -d -m 0755 /mnt/usr/local/sbin /mnt/var/lib /mnt/etc/systemd/system

    cat > /mnt/usr/local/sbin/mediaserver-firstboot.sh <<'FIRSTBOOT'
#!/bin/bash
set -euo pipefail

CONFIG=/etc/mediaserver-install.conf
STATE=/var/lib/mediaserver-firstboot.done

# shellcheck source=/dev/null
source "$CONFIG"

exec > >(tee -a "$INSTALL_FIRST_BOOT_LOG") 2>&1

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

if [[ -f "$STATE" ]]; then
    log "First-boot convergence already completed"
    exit 0
fi

log "Waiting for first-boot network connectivity"
until curl -fsS --max-time 10 https://archlinux.org >/dev/null; do
    sleep 5
done

log "Installing first-boot bootstrap packages"
pacman -Syu --needed --noconfirm ansible chezmoi git jq base-devel sudo

log "Applying Arch dotfiles subtree for $INSTALL_USERNAME"
runuser -l "$INSTALL_USERNAME" -s /bin/bash -c "
set -euo pipefail
if [[ -d \"\$HOME/.local/share/chezmoi/.git\" ]]; then
    git -C \"\$HOME/.local/share/chezmoi\" pull --ff-only
else
    chezmoi init '$INSTALL_DOTFILES_REPO'
fi
chezmoi apply \"\$HOME/.config/arch\"
"

log "Running Ansible profile: $INSTALL_ANSIBLE_LIMIT"
runuser -l "$INSTALL_USERNAME" -s /bin/bash -c "
set -euo pipefail
cd \"\$HOME/.config/arch/ansible\"
ansible-playbook -i inventory/hosts.yml site.yml --limit '$INSTALL_ANSIBLE_LIMIT' --connection=local
"

touch "$STATE"
systemctl disable mediaserver-firstboot.service
log "First-boot convergence complete"
FIRSTBOOT

    chmod 755 /mnt/usr/local/sbin/mediaserver-firstboot.sh

    cat > /mnt/etc/systemd/system/mediaserver-firstboot.service <<'SERVICE'
[Unit]
Description=Converge mediaserver Ansible profile on first boot
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/mediaserver-firstboot.sh
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
SERVICE

    arch-chroot /mnt systemctl enable mediaserver-firstboot.service
}

log "==> Starting unattended mediaserver installation"

log "Waiting for network connectivity"
until curl -fsS --max-time 10 https://archlinux.org >/dev/null; do
    sleep 3
done
log "Network ready"

DISK="$(select_target_disk)"
[[ -n "$DISK" ]] || fail "no install target disk found matching $INSTALL_TARGET_DISK_REGEX"
log "Target disk: $DISK"

EFI_PART="$(partition_path "$DISK" 1)"
ROOT_PART="$(partition_path "$DISK" 2)"

log "Partitioning $DISK"
swapoff --all || true
wipefs -af "$DISK"
sgdisk --zap-all "$DISK"
sgdisk -n "1:0:${INSTALL_EFI_SIZE}" -t 1:ef00 -c "1:${INSTALL_EFI_LABEL}" "$DISK"
sgdisk -n 2:0:0 -t 2:8300 -c "2:${INSTALL_ROOT_LABEL}" "$DISK"
partprobe "$DISK"
udevadm settle

[[ -b "$EFI_PART" ]] || fail "EFI partition was not created: $EFI_PART"
[[ -b "$ROOT_PART" ]] || fail "root partition was not created: $ROOT_PART"

log "Formatting partitions"
mkfs.fat -F32 -n "$INSTALL_EFI_LABEL" "$EFI_PART"
mkfs.ext4 -L "$INSTALL_ROOT_LABEL" -F "$ROOT_PART"

log "Mounting target system"
mount "$ROOT_PART" /mnt
mount --mkdir "$EFI_PART" /mnt/boot

log "Installing base system via pacstrap"
pacstrap -K /mnt "${INSTALL_PACSTRAP_PACKAGES[@]}"

log "Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

log "Configuring installed system"
cp "$CONFIG" /mnt/etc/mediaserver-install.conf
chmod 644 /mnt/etc/mediaserver-install.conf

sed -i "s/^#${INSTALL_LOCALE} UTF-8/${INSTALL_LOCALE} UTF-8/" /mnt/etc/locale.gen
printf 'LANG=%s\n' "$INSTALL_LOCALE" > /mnt/etc/locale.conf
printf 'KEYMAP=%s\n' "$INSTALL_KEYMAP" > /mnt/etc/vconsole.conf

printf '%s\n' "$INSTALL_HOSTNAME" > /mnt/etc/hostname
printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 %s.localdomain %s\n' \
    "$INSTALL_HOSTNAME" "$INSTALL_HOSTNAME" > /mnt/etc/hosts

install -d -m 0750 /mnt/etc/sudoers.d
printf '%%wheel ALL=(ALL:ALL) NOPASSWD: ALL\n' > /mnt/etc/sudoers.d/10-wheel
chmod 440 /mnt/etc/sudoers.d/10-wheel

mkdir -p /mnt/boot/loader/entries
printf 'default arch.conf\ntimeout 3\nconsole-mode max\neditor no\n' \
    > /mnt/boot/loader/loader.conf

ROOT_PARTUUID="$(blkid -s PARTUUID -o value "$ROOT_PART")"
printf 'title   Arch Linux\nlinux   /vmlinuz-linux\ninitrd  /intel-ucode.img\ninitrd  /initramfs-linux.img\noptions root=PARTUUID=%s rw quiet\n' \
    "$ROOT_PARTUUID" > /mnt/boot/loader/entries/arch.conf

log "Running chroot setup"
cp /root/install-chroot.sh /mnt/root/install-chroot.sh
arch-chroot /mnt bash /root/install-chroot.sh
rm /mnt/root/install-chroot.sh

write_first_boot_service

log "==> Installation complete, rebooting in 5 seconds"
sleep 5
reboot
