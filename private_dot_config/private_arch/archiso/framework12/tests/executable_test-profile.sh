#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DOTFILES_SOURCE="${DOTFILES_SOURCE:-$(chezmoi source-path)}"
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
DOTFILES_SOURCE="$TEST_DOTFILES_SOURCE"
resolve_defaults
resolve_target_packages > "$CHECK_DIR/target-packages.txt"
resolve_live_packages > "$CHECK_DIR/live-packages.txt"
resolve_workstation_aur_packages > "$CHECK_DIR/workstation-aur-packages.txt"
generate_archinstall_config \
  "$CHECK_DIR/target-packages.txt" \
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

grep -qx 'clonezilla' "$CHECK_DIR/live-packages.txt"
if grep -qx 'clonezilla' "$CHECK_DIR/target-packages.txt"; then
  printf 'ERROR: a releng-only package leaked into the target install set\n' >&2
  exit 1
fi
grep -qx 'networkmanager' "$CHECK_DIR/live-packages.txt"
grep -qx 'networkmanager' "$CHECK_DIR/target-packages.txt"
grep -qx '1password' "$CHECK_DIR/workstation-aur-packages.txt"
grep -qx '1password-cli' "$CHECK_DIR/workstation-aur-packages.txt"
grep -qx 'slack-desktop' "$CHECK_DIR/workstation-aur-packages.txt"

mkdir -p "$CHECK_DIR/profile"
printf 'declare -A file_permissions=()\n' > "$CHECK_DIR/profile/profiledef.sh"
append_private_file_permissions "$CHECK_DIR/profile"
# shellcheck disable=SC1091
source "$CHECK_DIR/profile/profiledef.sh"
[[ "${file_permissions[/etc/NetworkManager/system-connections]}" == "0:0:700" ]]
for profile_id in DomGromek DomGromek_5GHz; do
  [[ "${file_permissions[/etc/NetworkManager/system-connections/$profile_id.nmconnection]}" == "0:0:600" ]]
  [[ "${file_permissions[/usr/share/framework12-bootstrap/network/$profile_id.nmconnection]}" == "0:0:600" ]]
done
[[ "${file_permissions[/usr/share/framework12-bootstrap/dotfiles.tar.zst]}" == "0:0:600" ]]

"$PROFILE_DIR/build.sh" --check --dotfiles-source "$TEST_DOTFILES_SOURCE"
printf '==> Framework 12 profile tests passed\n'
