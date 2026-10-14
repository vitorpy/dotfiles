#!/usr/bin/env bash
# Run as root INSIDE the disposable Fedora guest, never on an existing workstation.
set -euo pipefail
if [[ $EUID -ne 0 ]] || [[ $(hostname) != fedora44-lab ]]; then
    printf 'This script requires root inside fedora44-lab.\n' >&2
    exit 1
fi
# shellcheck disable=SC1091
source /etc/os-release
if [[ $ID != fedora || $VERSION_ID != 44 ]]; then
    printf 'This lab provisioning script requires Fedora 44.\n' >&2
    exit 1
fi
if [[ ! -f /var/lib/cloud/instance/boot-finished ]]; then
    printf 'Wait for cloud-init to finish before provisioning the desktop.\n' >&2
    exit 1
fi
case "${1:-}" in
    --preview) transaction_flag=--assumeno ;;
    --install) transaction_flag=--assumeyes ;;
    *) printf 'Usage: %s {--preview|--install}\n' "$0" >&2; exit 2 ;;
esac

# Fedora's base repositories lack current Hyprland. Keep the COPR's scope limited
# to the compositor family, Quickshell, UWSM, and their matching portal.
cat > /etc/yum.repos.d/fedora-migration-hyprland.repo <<'EOF'
[copr:copr.fedorainfracloud.org:lionheartp:Hyprland]
name=Hyprland compatibility lab - lionheartp COPR
baseurl=https://download.copr.fedorainfracloud.org/results/lionheartp/Hyprland/fedora-$releasever-$basearch/
enabled=1
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/lionheartp/Hyprland/pubkey.gpg
repo_gpgcheck=0
skip_if_unavailable=False
includepkgs=hypr* aquamarine* quickshell* uwsm* xdg-desktop-portal-hyprland*
EOF
chmod 644 /etc/yum.repos.d/fedora-migration-hyprland.repo

dnf "$transaction_flag" install \
    hyprland quickshell uwsm hypridle hyprlock hyprpaper hyprsunset \
    hyprpolkitagent hyprlauncher hyprshutdown \
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
    pipewire pipewire-pulseaudio wireplumber playerctl brightnessctl libnotify \
    gnome-keyring power-profiles-daemon network-manager-applet \
    grim slurp wl-clipboard greetd \
    qt6-qtdeclarative-devel qt6-qtsvg qt6-qt5compat \
    mesa-dri-drivers mesa-vulkan-drivers mesa-libEGL \
    google-noto-sans-fonts google-noto-color-emoji-fonts python3-pytest

if [[ $transaction_flag == --assumeyes ]]; then
    rpm -q hyprland quickshell uwsm
    printf 'Desktop packages installed. A graphical login has not been configured yet.\n'
fi
