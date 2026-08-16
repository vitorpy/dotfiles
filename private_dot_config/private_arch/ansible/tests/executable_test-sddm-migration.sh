#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
sddm_role="${repo_root}/roles/sddm"
sddm_tasks="${sddm_role}/tasks/main.yml"
sddm_config="${sddm_role}/templates/10-berg.conf.j2"
sddm_theme="${sddm_role}/files/berg"
all_vars="${repo_root}/group_vars/all.yml"
workstation_vars="${repo_root}/group_vars/workstation.yml"
wallpaper_unit="${repo_root}/../../systemd/user/arts-wallpaper.service"

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

require_literal "arch_display_manager: sddm" "${workstation_vars}"
require_literal "arch_sddm_retire_ly: false" "${workstation_vars}"
require_literal "  - sddm" "${all_vars}"
require_literal "  - ly" "${all_vars}"

require_literal "DisplayServer=wayland" "${sddm_config}"
require_literal "QML_XHR_ALLOW_FILE_READ=1" "${sddm_config}"
require_literal "Relogin=false" "${sddm_config}"
require_literal "Session=" "${sddm_config}"
require_literal "User=" "${sddm_config}"
require_literal "RememberLastSession=true" "${sddm_config}"
require_literal "RememberLastUser=true" "${sddm_config}"

require_literal 'mode: "2750"' "${sddm_tasks}"
require_literal 'mode: "0640"' "${sddm_tasks}"
require_literal "enabled: false" "${sddm_tasks}"
require_literal "enabled: true" "${sddm_tasks}"
require_literal "ly@tty2.service" "${sddm_tasks}"
require_literal "getty@tty2.service" "${sddm_tasks}"
require_literal "sddm.service" "${sddm_tasks}"
require_literal "daemon_reload: true" "${sddm_tasks}"
require_literal "sddm_primary_user_bus.stat.exists" "${sddm_tasks}"
reject_literal "state: started" "${sddm_tasks}"

require_literal "ARTS_WALLPAPER_DATA_DIR=/var/lib/arts-wallpaper" "${wallpaper_unit}"
require_literal "UMask=0027" "${wallpaper_unit}"
require_literal "file:///var/lib/arts-wallpaper/current.webp" "${sddm_theme}/theme.conf"
require_literal "file:///var/lib/arts-wallpaper/current.json" "${sddm_theme}/theme.conf"
reject_literal "/home/" "${sddm_theme}/Main.qml"

echo "SDDM migration invariants passed"
