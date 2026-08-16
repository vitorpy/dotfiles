#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
sddm_role="${repo_root}/roles/sddm"
sddm_tasks="${sddm_role}/tasks/main.yml"
sddm_config="${sddm_role}/templates/10-berg.conf.j2"
sddm_hyprland="${sddm_role}/templates/berg-hyprland.lua.j2"
sddm_theme="${sddm_role}/files/berg"
all_vars="${repo_root}/group_vars/all.yml"
workstation_vars="${repo_root}/group_vars/workstation.yml"
packages_tasks="${repo_root}/roles/packages/tasks/main.yml"
wallpaper_unit="${repo_root}/../../systemd/user/arts-wallpaper.service"
ly_user_config="${repo_root}/../../ly"
ly_role="${repo_root}/roles/ly"

require_literal() {
  local literal="$1"
  local file="$2"
  grep -Fq -- "${literal}" "${file}" || {
    echo "missing '${literal}' in ${file}" >&2
    exit 1
  }
}

reject_literal() {
  local literal="$1"
  local file="$2"
  if grep -Fq -- "${literal}" "${file}"; then
    echo "unexpected '${literal}' in ${file}" >&2
    exit 1
  fi
}

require_before() {
  local first="$1"
  local second="$2"
  local file="$3"
  local first_line
  local second_line

  require_literal "${first}" "${file}"
  require_literal "${second}" "${file}"
  first_line="$(grep -Fnm1 -- "${first}" "${file}" | cut -d: -f1)"
  second_line="$(grep -Fnm1 -- "${second}" "${file}" | cut -d: -f1)"
  if ((first_line >= second_line)); then
    echo "expected '${first}' before '${second}' in ${file}" >&2
    exit 1
  fi
}

require_literal "arch_display_manager: sddm" "${workstation_vars}"
require_literal "arch_sddm_retire_ly: true" "${workstation_vars}"
require_literal "arch_package_prune_exclude:" "${workstation_vars}"
require_literal "  - ly" "${workstation_vars}"
require_literal "  - sddm" "${all_vars}"
reject_literal "  - ly" "${all_vars}"
require_literal "arch_package_prune_exclude" "${packages_tasks}"

require_literal "DisplayServer=wayland" "${sddm_config}"
require_literal "QML_XHR_ALLOW_FILE_READ=1" "${sddm_config}"
require_literal "Relogin=false" "${sddm_config}"
require_literal "Session=" "${sddm_config}"
require_literal "User=" "${sddm_config}"
require_literal "RememberLastSession=true" "${sddm_config}"
require_literal "RememberLastUser=true" "${sddm_config}"
require_literal "/usr/share/sddm/berg-hyprland.lua" "${sddm_config}"
reject_literal "/usr/share/sddm/berg-hyprland.conf" "${sddm_config}"

require_literal 'mode: "2750"' "${sddm_tasks}"
require_literal 'mode: "0640"' "${sddm_tasks}"
require_literal "checksum_algorithm: sha1" "${sddm_tasks}"
reject_literal "checksum_algorithm: sha256" "${sddm_tasks}"
require_literal "item.checksum is defined" "${sddm_tasks}"
reject_literal "item.changed | default(false)" "${sddm_tasks}"
require_literal "render-greeter" "${sddm_tasks}"
require_literal "current.png" "${sddm_tasks}"
require_literal "sddm_artwork_group_query.rc == 0" "${sddm_tasks}"
require_literal "sddm_artwork_repository.stat.exists" "${sddm_tasks}"
require_literal "sddm_config_directory.stat.exists" "${sddm_tasks}"
require_literal "enabled: false" "${sddm_tasks}"
require_literal "enabled: true" "${sddm_tasks}"
require_literal "ly@tty2.service" "${sddm_tasks}"
require_literal "getty@tty2.service" "${sddm_tasks}"
require_literal "sddm.service" "${sddm_tasks}"
require_literal "Query the Ly package before retirement" "${sddm_tasks}"
require_literal "Determine whether Ly retirement validation is required" "${sddm_tasks}"
require_literal "sddm_ly_retirement_required | bool" "${sddm_tasks}"
require_literal "Inspect tty2 recovery enablement before Ly retirement" "${sddm_tasks}"
require_literal "/etc/systemd/system/getty.target.wants/getty@tty2.service" "${sddm_tasks}"
require_literal "sddm_tty2_recovery_link.stat.lnk_source" "${sddm_tasks}"
require_literal "Verify accepted display-manager state before Ly retirement" "${sddm_tasks}"
require_literal "ansible_facts.services.get('sddm.service', {}).get('state', '') ==" "${sddm_tasks}"
require_literal "ansible_facts.services.get('getty@tty2.service', {}).get('state', '') ==" "${sddm_tasks}"
require_literal "Validate shared artwork JSON before Ly retirement" "${sddm_tasks}"
require_literal "json.tool" "${sddm_tasks}"
require_literal "Validate shared artwork images before Ly retirement" "${sddm_tasks}"
require_literal "/usr/bin/magick" "${sddm_tasks}"
require_literal "Validate published artwork metadata as the desktop user" "${sddm_tasks}"
require_literal "Remove managed Ly user configuration after SDDM acceptance" "${sddm_tasks}"
require_before "Verify accepted display-manager state before Ly retirement" \
  "Remove Ly package after SDDM acceptance" "${sddm_tasks}"
require_before "Validate shared artwork JSON before Ly retirement" \
  "Remove Ly package after SDDM acceptance" "${sddm_tasks}"
require_before "Validate shared artwork images before Ly retirement" \
  "Remove Ly package after SDDM acceptance" "${sddm_tasks}"
require_before "Validate published artwork metadata as the desktop user" \
  "Remove Ly package after SDDM acceptance" "${sddm_tasks}"
require_literal "daemon_reload: true" "${sddm_tasks}"
require_literal "sddm_primary_user_bus.stat.exists" "${sddm_tasks}"
reject_literal "state: started" "${sddm_tasks}"

require_literal 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })' "${sddm_hyprland}"
require_literal "hl.config({" "${sddm_hyprland}"
require_literal 'kb_layout = "pl,us"' "${sddm_hyprland}"
require_literal "disable_hyprland_logo = true" "${sddm_hyprland}"
if [[ -e "${sddm_role}/templates/berg-hyprland.conf.j2" ]]; then
  echo "deprecated Hyprland greeter configuration still exists" >&2
  exit 1
fi

if [[ -e "${ly_user_config}/config.ini" || -e "${ly_user_config}/setup.sh" ]]; then
  echo "obsolete managed Ly user configuration still exists" >&2
  exit 1
fi

if [[ -e "${ly_role}/tasks/main.yml" ]]; then
  echo "obsolete Ly role still exists" >&2
  exit 1
fi

require_literal "ARTS_WALLPAPER_DATA_DIR=/var/lib/arts-wallpaper" "${wallpaper_unit}"
require_literal "UMask=0027" "${wallpaper_unit}"
require_literal "file:///var/lib/arts-wallpaper/current.png" "${sddm_theme}/theme.conf"
reject_literal "file:///var/lib/arts-wallpaper/current.webp" "${sddm_theme}/theme.conf"
require_literal "file:///var/lib/arts-wallpaper/current.json" "${sddm_theme}/theme.conf"
reject_literal "/home/" "${sddm_theme}/Main.qml"

echo "SDDM migration invariants passed"
