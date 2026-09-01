#!/usr/bin/env bash
set -euo pipefail

umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATIC_PROFILE="$SCRIPT_DIR/profile"
PACKAGE_VARS="$ARCH_DIR/ansible/group_vars/all.yml"
RELENG_DIR="/usr/share/archiso/configs/releng"

CHECK_ONLY=false
OUTPUT_DIR="$SCRIPT_DIR/out"
DOTFILES_SOURCE=""
WORK_PARENT=""

WORKSTATION_PACKAGE_KEYS=(
  arch_pacman_packages_base
  arch_pacman_packages_hyprland
  arch_pacman_packages_multimedia
  arch_pacman_packages_development
  arch_pacman_packages_communication
  arch_pacman_packages_theming
  arch_pacman_packages_utilities
  arch_pacman_packages_browsers
  arch_pacman_packages_shells
  arch_pacman_packages_system_extras
  arch_pacman_packages_cli_extras
  arch_pacman_packages_desktop_extras
  arch_pacman_packages_dev_extras
)

WORKSTATION_AUR_KEYS=(
  arch_aur_packages_browsers
  arch_aur_packages_hyprland
  arch_aur_packages_development
  arch_aur_packages_communication
  arch_aur_packages_theming
  arch_aur_packages_utilities
)

FRAMEWORK_PACKAGES=(
  linux
  linux-firmware
  linux-firmware-intel
  intel-ucode
  wireless-regdb
  networkmanager
  wpa_supplicant
  iw
  mesa
  vulkan-intel
  intel-media-driver
  libva-intel-driver
  intel-gpu-tools
  xorg-xrandr
  xf86-input-libinput
  iio-sensor-proxy
  sof-firmware
  alsa-utils
  alsa-firmware
  bluez
  bluez-utils
  blueman
  v4l-utils
  udisks2
  gvfs-mtp
  gvfs-gphoto2
  fprintd
  libfprint
  fwupd
)

WIFI_PROFILE_IDS=(
  "DomGromek|21518a1c-81ba-49f9-b7f2-29f819e9e872|DomGromek"
  "DomGromek_5GHz|791db701-e516-4280-8465-492221d8db1b|DomGromek_5GHz"
)

usage() {
  printf '%s\n' \
    "Usage: $0 [--check] [--output-dir PATH] [--work-dir PATH] [--dotfiles-source PATH]" \
    "" \
    "  --check                 Validate inputs without reading Wi-Fi secrets or building" \
    "  --output-dir PATH       ISO output directory (default: $OUTPUT_DIR)" \
    "  --work-dir PATH         Parent for temporary mkarchiso work" \
    "  --dotfiles-source PATH  Clean chezmoi Git source to archive"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

build_user_home() {
  local build_user
  build_user="${SUDO_USER:-$(id -un)}"
  getent passwd "$build_user" | awk -F: 'NR == 1 { print $6 }'
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check)
        CHECK_ONLY=true
        shift
        ;;
      --output-dir)
        (($# >= 2)) || die "--output-dir requires a path"
        OUTPUT_DIR="$2"
        shift 2
        ;;
      --work-dir)
        (($# >= 2)) || die "--work-dir requires a path"
        WORK_PARENT="$2"
        shift 2
        ;;
      --dotfiles-source)
        (($# >= 2)) || die "--dotfiles-source requires a path"
        DOTFILES_SOURCE="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done
}

resolve_defaults() {
  local user_home
  user_home="$(build_user_home)"
  [[ -n "$user_home" ]] || die "could not resolve the build user's home directory"

  if [[ -z "$DOTFILES_SOURCE" ]]; then
    DOTFILES_SOURCE="$user_home/.local/share/chezmoi"
  fi
  if [[ -z "$WORK_PARENT" ]]; then
    if (( EUID == 0 )); then
      WORK_PARENT=/var/tmp/archiso-framework12
    else
      WORK_PARENT="$user_home/.cache/archiso-framework12"
    fi
  fi
}

yaml_list_values() {
  local keys_csv="$1"
  awk -v wanted_csv="$keys_csv" '
    BEGIN {
      count = split(wanted_csv, keys, ",")
      for (i = 1; i <= count; i++) {
        wanted[keys[i]] = 1
      }
    }
    match($0, /^([A-Za-z0-9_]+):[[:space:]]*$/, fields) {
      current = fields[1]
      active = current in wanted
      next
    }
    active && match($0, /^  - ([^#].*)$/, fields) {
      value = fields[1]
      sub(/[[:space:]]+$/, "", value)
      print value
      next
    }
    active && $0 !~ /^  - / {
      active = 0
    }
  ' "$PACKAGE_VARS"
}

join_by_comma() {
  local IFS=,
  printf '%s' "$*"
}

resolve_workstation_packages() {
  yaml_list_values "$(join_by_comma "${WORKSTATION_PACKAGE_KEYS[@]}")" | sort -u
}

resolve_workstation_aur_packages() {
  yaml_list_values "$(join_by_comma "${WORKSTATION_AUR_KEYS[@]}")" | sort -u
}

resolve_target_packages() {
  {
    resolve_workstation_packages
    printf '%s\n' "${FRAMEWORK_PACKAGES[@]}"
  } | sort -u
}

resolve_live_packages() {
  {
    # archiso 89 still names broadcom-wl, which has left the repositories.
    # Framework 12 uses Intel Wi-Fi, covered explicitly by FRAMEWORK_PACKAGES.
    sed \
      -e '/^[[:space:]]*#/d' \
      -e '/^[[:space:]]*$/d' \
      -e '/^broadcom-wl$/d' \
      "$RELENG_DIR/packages.x86_64"
    printf '%s\n' "${FRAMEWORK_PACKAGES[@]}"
  } | sort -u
}

repo_version() {
  LC_ALL=C pacman -Si "$1" \
    | awk '$1 == "Version" && $2 == ":" { print $3; exit }'
}

validate_versions() {
  local linux_version libfprint_version archinstall_version install_scripts_version
  linux_version="$(repo_version linux)"
  libfprint_version="$(repo_version libfprint)"
  archinstall_version="$(repo_version archinstall)"
  install_scripts_version="$(repo_version arch-install-scripts)"

  [[ -n "$linux_version" ]] || die "could not resolve the repository linux version"
  [[ -n "$libfprint_version" ]] || die "could not resolve the repository libfprint version"
  [[ -n "$archinstall_version" ]] || die "could not resolve the repository archinstall version"
  [[ -n "$install_scripts_version" ]] \
    || die "could not resolve the repository arch-install-scripts version"
  (( $(vercmp "$linux_version" 7.1) >= 0 )) \
    || die "Framework 12 Core Series 3 requires linux >= 7.1; repository has $linux_version"
  (( $(vercmp "$libfprint_version" 1.94.100) >= 0 )) \
    || die "Framework 12 fingerprint support requires libfprint >= 1.94.100; repository has $libfprint_version"
  (( $(vercmp "$archinstall_version" 4.4) >= 0 )) \
    || die "bootstrap handoff requires archinstall >= 4.4; repository has $archinstall_version"
  (( $(vercmp "$install_scripts_version" 31) >= 0 )) \
    || die "bootstrap handoff requires arch-install-scripts >= 31; repository has $install_scripts_version"
}

validate_package_sets() {
  local temp_dir="$1"
  local workstation_file="$temp_dir/workstation-packages.txt"
  local aur_file="$temp_dir/workstation-aur-packages.txt"
  local target_file="$temp_dir/target-packages.txt"
  local live_file="$temp_dir/live-packages.txt"
  local -a available_packages

  resolve_workstation_packages > "$workstation_file"
  resolve_workstation_aur_packages > "$aur_file"
  resolve_target_packages > "$target_file"
  resolve_live_packages > "$live_file"

  [[ -s "$workstation_file" ]] || die "resolved workstation package list is empty"
  [[ -s "$target_file" ]] || die "resolved target package list is empty"
  [[ -s "$live_file" ]] || die "resolved live package list is empty"
  if comm -12 "$workstation_file" "$aur_file" | grep -q .; then
    die "an AUR package is present in the workstation pacman set"
  fi

  mapfile -t available_packages < <(sort -u "$target_file" "$live_file")
  pacman -Si "${available_packages[@]}" >/dev/null \
    || die "one or more ISO packages are unavailable from configured repositories"
  validate_versions

  printf '==> Workstation repo packages: %s\n' "$(wc -l < "$workstation_file")"
  printf '==> Target install packages: %s\n' "$(wc -l < "$target_file")"
  printf '==> Live environment packages: %s\n' "$(wc -l < "$live_file")"
}

validate_dotfiles_source() {
  local status

  [[ -d "$DOTFILES_SOURCE/.git" ]] \
    || die "dotfiles source is not a Git worktree: $DOTFILES_SOURCE"
  status="$(git -C "$DOTFILES_SOURCE" status --porcelain=v1 --untracked-files=all)" \
    || die "could not inspect dotfiles source: $DOTFILES_SOURCE"
  [[ -z "$status" ]] \
    || die "dotfiles source must be clean before it can be embedded"
}

validate_static_files() {
  local script
  for script in \
    "$SCRIPT_DIR/build.sh" \
    "$STATIC_PROFILE/airootfs/root/framework-install" \
    "$STATIC_PROFILE/airootfs/usr/local/libexec/framework12-postinstall" \
    "$SCRIPT_DIR/tests/test-profile.sh"; do
    [[ -f "$script" ]] || die "missing profile file: $script"
    bash -n "$script"
  done

  [[ -f "$PACKAGE_VARS" ]] || die "missing Ansible package source: $PACKAGE_VARS"
  [[ -d "$RELENG_DIR" ]] || die "archiso releng profile not found: $RELENG_DIR"
}

generate_archinstall_config() {
  local package_file="$1"
  local output_file="$2"
  local packages_json

  packages_json="$(jq -R . < "$package_file" | jq -s .)"
  jq -n --argjson packages "$packages_json" '
    {
      "archinstall-language": "English",
      "bootloader_config": {
        "bootloader": "Systemd-boot",
        "uki": true,
        "removable": false
      },
      "custom_commands": [
        "/run/udev/framework12-bootstrap/postinstall vitorpy"
      ],
      "hostname": "rivest",
      "kernels": ["linux"],
      "locale_config": {
        "kb_layout": "us",
        "sys_enc": "UTF-8",
        "sys_lang": "en_US.UTF-8"
      },
      "network_config": {
        "type": "nm"
      },
      "ntp": true,
      "packages": $packages,
      "profile_config": null,
      "script": "guided",
      "services": [
        "sddm.service",
        "bluetooth.service",
        "cups.service",
        "avahi-daemon.service",
        "power-profiles-daemon.service"
      ],
      "swap": {
        "enabled": true,
        "algorithm": "zstd"
      },
      "timezone": "Europe/Warsaw"
    }
  ' > "$output_file"
  jq -e . "$output_file" >/dev/null
}

generate_wifi_profile() {
  local profile_id="$1"
  local profile_uuid="$2"
  local ssid="$3"
  local output_file="$4"
  local psk

  psk="$(
    nmcli --escape no --show-secrets \
      -g 802-11-wireless-security.psk \
      connection show "$profile_uuid"
  )"
  [[ -n "$psk" ]] || die "saved Wi-Fi profile has no PSK: $profile_id ($profile_uuid)"
  if (( ${#psk} < 8 || ${#psk} > 63 )) && [[ ! "$psk" =~ ^[[:xdigit:]]{64}$ ]]; then
    die "saved Wi-Fi profile has an invalid WPA-PSK length: $profile_id"
  fi

  nmcli --offline connection add \
    type wifi \
    con-name "$profile_id" \
    connection.uuid "$profile_uuid" \
    connection.autoconnect yes \
    ssid "$ssid" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "$psk" \
    ipv4.method auto \
    ipv6.method auto > "$output_file"
  chmod 0600 "$output_file"
  unset psk
}

configure_live_networking() {
  local profile_dir="$1"
  local bootstrap_dir="$2"
  local systemd_dir="$profile_dir/airootfs/etc/systemd/system"
  local nm_dir="$profile_dir/airootfs/etc/NetworkManager/system-connections"
  local entry profile_id profile_uuid ssid output_file

  rm -f \
    "$systemd_dir/multi-user.target.wants/iwd.service" \
    "$systemd_dir/multi-user.target.wants/systemd-networkd.service" \
    "$systemd_dir/network-online.target.wants/systemd-networkd-wait-online.service" \
    "$systemd_dir/dbus-org.freedesktop.network1.service" \
    "$systemd_dir/sockets.target.wants/systemd-networkd.socket"

  mkdir -p \
    "$systemd_dir/multi-user.target.wants" \
    "$systemd_dir/network-online.target.wants" \
    "$nm_dir" \
    "$bootstrap_dir/network"
  ln -sf /usr/lib/systemd/system/NetworkManager.service \
    "$systemd_dir/multi-user.target.wants/NetworkManager.service"
  ln -sf /usr/lib/systemd/system/NetworkManager-wait-online.service \
    "$systemd_dir/network-online.target.wants/NetworkManager-wait-online.service"

  for entry in "${WIFI_PROFILE_IDS[@]}"; do
    IFS='|' read -r profile_id profile_uuid ssid <<< "$entry"
    output_file="$nm_dir/$profile_id.nmconnection"
    generate_wifi_profile "$profile_id" "$profile_uuid" "$ssid" "$output_file"
    install -m 0600 "$output_file" "$bootstrap_dir/network/$profile_id.nmconnection"
  done
}

append_private_file_permissions() {
  local profile_dir="$1"
  local profiledef="$profile_dir/profiledef.sh"
  local entry profile_id profile_uuid ssid

  printf '%s\n' \
    'file_permissions["/etc/NetworkManager/system-connections"]="0:0:700"' \
    'file_permissions["/usr/share/framework12-bootstrap/dotfiles.tar.zst"]="0:0:600"' \
    >> "$profiledef"
  for entry in "${WIFI_PROFILE_IDS[@]}"; do
    IFS='|' read -r profile_id profile_uuid ssid <<< "$entry"
    printf 'file_permissions["/etc/NetworkManager/system-connections/%s.nmconnection"]="0:0:600"\n' \
      "$profile_id" >> "$profiledef"
    printf 'file_permissions["/usr/share/framework12-bootstrap/network/%s.nmconnection"]="0:0:600"\n' \
      "$profile_id" >> "$profiledef"
  done
}

embed_dotfiles_snapshot() {
  local bootstrap_dir="$1"
  local package_file="$2"
  local archive="$bootstrap_dir/dotfiles.tar.zst"
  local commit commit_time archive_sha archive_size
  local linux_version libfprint_version archinstall_version install_scripts_version

  commit="$(git -C "$DOTFILES_SOURCE" rev-parse HEAD)"
  commit_time="$(git -C "$DOTFILES_SOURCE" show -s --format=%cI HEAD)"
  git -C "$DOTFILES_SOURCE" archive --format=tar HEAD \
    | zstd -q -T0 -19 -o "$archive"
  archive_sha="$(sha256sum "$archive" | awk '{ print $1 }')"
  archive_size="$(stat -c %s "$archive")"
  linux_version="$(repo_version linux)"
  libfprint_version="$(repo_version libfprint)"
  archinstall_version="$(repo_version archinstall)"
  install_scripts_version="$(repo_version arch-install-scripts)"

  install -m 0644 "$package_file" "$bootstrap_dir/packages.txt"
  jq -n \
    --arg built_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg commit "$commit" \
    --arg commit_time "$commit_time" \
    --arg archive_sha256 "$archive_sha" \
    --argjson archive_size "$archive_size" \
    --arg linux_version "$linux_version" \
    --arg libfprint_version "$libfprint_version" \
    --arg archinstall_version "$archinstall_version" \
    --arg install_scripts_version "$install_scripts_version" \
    --argjson package_count "$(wc -l < "$package_file")" \
    '{
      built_at: $built_at,
      dotfiles: {
        commit: $commit,
        commit_time: $commit_time,
        archive: "dotfiles.tar.zst",
        sha256: $archive_sha256,
        size: $archive_size
      },
      platform: {
        target: "Framework Laptop 12",
        minimum_kernel: "7.1",
        linux_version: $linux_version,
        minimum_libfprint: "1.94.100",
        libfprint_version: $libfprint_version
      },
      installer: {
        archinstall_version: $archinstall_version,
        arch_install_scripts_version: $install_scripts_version,
        bootstrap_handoff: "/run/udev/framework12-bootstrap"
      },
      package_count: $package_count,
      wifi_profiles: ["DomGromek", "DomGromek_5GHz"]
    }
  ' > "$bootstrap_dir/build-manifest.json"
  chmod 0600 "$archive"
  chmod 0644 "$bootstrap_dir/build-manifest.json"
}

prepare_profile() {
  local profile_dir="$1"
  local live_package_file="$2"
  local target_package_file="$3"
  local bootstrap_dir="$profile_dir/airootfs/usr/share/framework12-bootstrap"

  cp -a "$RELENG_DIR/." "$profile_dir/"
  cp -a "$STATIC_PROFILE/." "$profile_dir/"
  install -m 0644 "$live_package_file" "$profile_dir/packages.x86_64"
  generate_archinstall_config \
    "$target_package_file" \
    "$profile_dir/airootfs/root/framework12-user_configuration.json"

  sed -i \
    -e 's/^iso_name=.*/iso_name="rivest-framework12"/' \
    -e 's|^iso_application=.*|iso_application="Rivest Framework 12 Guided Arch Installer"|' \
    "$profile_dir/profiledef.sh"
  printf '%s\n' \
    'file_permissions["/root/framework-install"]="0:0:755"' \
    'file_permissions["/root/framework12-user_configuration.json"]="0:0:600"' \
    'file_permissions["/usr/local/libexec/framework12-postinstall"]="0:0:755"' \
    >> "$profile_dir/profiledef.sh"

  mkdir -p "$bootstrap_dir"
  configure_live_networking "$profile_dir" "$bootstrap_dir"
  embed_dotfiles_snapshot "$bootstrap_dir" "$target_package_file"
  append_private_file_permissions "$profile_dir"
}

run_checks() (
  local check_dir
  check_dir="$(mktemp -d /tmp/framework12-archiso-check.XXXXXX)"
  trap 'rm -rf -- "$check_dir"' EXIT

  validate_static_files
  validate_dotfiles_source
  validate_package_sets "$check_dir"
  generate_archinstall_config \
    "$check_dir/target-packages.txt" \
    "$check_dir/framework12-user_configuration.json"
  printf '==> Framework 12 ArchISO inputs are valid\n'
)

main() {
  local work_dir profile_dir live_package_file target_package_file
  local iso_path build_user build_group

  parse_args "$@"
  resolve_defaults

  for command in awk bash comm getent git grep jq nmcli pacman sha256sum sort stat vercmp zstd; do
    require_command "$command"
  done
  run_checks

  if [[ "$CHECK_ONLY" == "true" ]]; then
    exit 0
  fi

  (( EUID == 0 )) || die "full ISO builds require root; run this build command yourself with sudo"
  require_command mkarchiso

  mkdir -p "$OUTPUT_DIR" "$WORK_PARENT"
  chmod 0700 "$OUTPUT_DIR"
  work_dir="$(mktemp -d "$WORK_PARENT/build.XXXXXX")"
  [[ -n "$work_dir" && "$work_dir" == "$WORK_PARENT"/build.* ]] \
    || die "refusing to use unexpected work directory: $work_dir"
  trap 'rm -rf -- "$work_dir"' EXIT
  profile_dir="$work_dir/profile"
  live_package_file="$work_dir/live-packages.txt"
  target_package_file="$work_dir/target-packages.txt"

  resolve_live_packages > "$live_package_file"
  resolve_target_packages > "$target_package_file"
  prepare_profile "$profile_dir" "$live_package_file" "$target_package_file"

  printf '==> Building Framework 12 ISO\n'
  printf '    profile: %s\n' "$profile_dir"
  printf '    output:  %s\n' "$OUTPUT_DIR"
  mkarchiso -v -w "$work_dir/work" -o "$OUTPUT_DIR" "$profile_dir"

  iso_path="$(find "$OUTPUT_DIR" -maxdepth 1 -type f -name 'rivest-framework12-*.iso' -printf '%T@ %p\n' \
    | sort -nr | awk 'NR == 1 { sub(/^[^ ]+ /, ""); print; exit }')"
  [[ -n "$iso_path" && -f "$iso_path" ]] || die "mkarchiso completed but no ISO was found"
  sha256sum "$iso_path" > "$iso_path.sha256"
  install -m 0644 \
    "$profile_dir/airootfs/usr/share/framework12-bootstrap/build-manifest.json" \
    "$iso_path.build-manifest.json"

  chmod 0600 "$iso_path" "$iso_path.sha256"
  build_user="${SUDO_USER:-$(id -un)}"
  build_group="$(id -gn "$build_user")"
  chown "$build_user":"$build_group" \
    "$iso_path" "$iso_path.sha256" "$iso_path.build-manifest.json"
  if [[ "$(stat -c %U "$OUTPUT_DIR")" == root && "$build_user" != root ]]; then
    chown "$build_user":"$build_group" "$OUTPUT_DIR"
  fi

  printf '==> ISO: %s\n' "$iso_path"
  printf '==> SHA-256: %s\n' "$iso_path.sha256"
  printf '==> Manifest: %s\n' "$iso_path.build-manifest.json"
  printf '==> Treat this ISO as private: it contains recoverable Wi-Fi credentials.\n'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
