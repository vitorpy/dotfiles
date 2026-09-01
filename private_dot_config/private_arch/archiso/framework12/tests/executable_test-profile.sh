#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOTFILES_SOURCE="${DOTFILES_SOURCE:-$(chezmoi source-path)}"
CHECK_DIR="$(mktemp -d /tmp/framework12-profile-test.XXXXXX)"
trap 'rm -rf -- "$CHECK_DIR"' EXIT

bash -n "$PROFILE_DIR/build.sh"
bash -n "$PROFILE_DIR/profile/airootfs/root/framework-install"
bash -n "$PROFILE_DIR/profile/airootfs/usr/local/libexec/framework12-postinstall"

grep -q 'script=/root/framework-install' \
  "$PROFILE_DIR/profile/efiboot/loader/entries/00-rivest-framework12.conf"
grep -q '^default 00-rivest-framework12.conf$' \
  "$PROFILE_DIR/profile/efiboot/loader/loader.conf"
grep -q '^INCLUDE archiso_sys-linux.cfg$' \
  "$PROFILE_DIR/profile/syslinux/archiso_sys.cfg"
grep -q '"/run/udev/framework12-bootstrap/postinstall vitorpy"' \
  "$PROFILE_DIR/build.sh"
grep -q '^BOOTSTRAP_RUN=/run/udev/framework12-bootstrap$' \
  "$PROFILE_DIR/profile/airootfs/root/framework-install"
grep -q '^BOOTSTRAP_RUN=/run/udev/framework12-bootstrap$' \
  "$PROFILE_DIR/profile/airootfs/usr/local/libexec/framework12-postinstall"

if rg -n 'wipefs|sgdisk|auto-install\.service|mediaserver-install' \
  "$PROFILE_DIR/profile" >/dev/null; then
  printf 'ERROR: destructive mediaserver installer content leaked into Framework profile\n' >&2
  exit 1
fi

if rg -n '^psk=' "$PROFILE_DIR" >/dev/null; then
  printf 'ERROR: a Wi-Fi PSK was written into the tracked Framework profile\n' >&2
  exit 1
fi

# Exercise the real resolver and config generator without a privileged ISO
# build. Disk layout and authentication must remain explicit TUI choices.
source "$PROFILE_DIR/build.sh"
resolve_defaults
resolve_final_packages > "$CHECK_DIR/packages.x86_64"
generate_archinstall_config \
  "$CHECK_DIR/packages.x86_64" \
  "$CHECK_DIR/framework12-user_configuration.json"
jq -e '
  .hostname == "rivest" and
  .bootloader_config.bootloader == "Systemd-boot" and
  .bootloader_config.uki == true and
  .network_config.type == "nm" and
  .custom_commands == ["/run/udev/framework12-bootstrap/postinstall vitorpy"] and
  (.packages | index("networkmanager") != null) and
  (.packages | index("linux-firmware-intel") != null) and
  (.packages | index("chezmoi") != null) and
  (has("disk_config") | not) and
  (has("auth_config") | not)
' "$CHECK_DIR/framework12-user_configuration.json" >/dev/null

"$PROFILE_DIR/build.sh" --check --dotfiles-source "$DOTFILES_SOURCE"
printf '==> Framework 12 profile tests passed\n'
