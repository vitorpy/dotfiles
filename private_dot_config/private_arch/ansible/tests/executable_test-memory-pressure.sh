#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
base_tasks="${repo_root}/roles/base/tasks/main.yml"
base_handlers="${repo_root}/roles/base/handlers/main.yml"
base_templates="${repo_root}/roles/base/templates"
all_vars="${repo_root}/group_vars/all.yml"
workstation_vars="${repo_root}/group_vars/workstation.yml"
private_config_root="$(cd "${repo_root}/../.." && pwd)"
berg_unit="${private_config_root}/systemd/user/quickshell-berg.service"
rclone_unit="${private_config_root}/systemd/user/rclone-box.service"
rclone_gdrive_unit="${private_config_root}/systemd/user/rclone-gdrive.service"

require_literal() {
  local literal="$1"
  local file="$2"
  grep -Fq -- "${literal}" "${file}" || {
    echo "missing '${literal}' in ${file}" >&2
    exit 1
  }
}

require_literal "arch_memory_pressure_managed: false" "${all_vars}"
require_literal "arch_memory_pressure_enabled: false" "${all_vars}"
require_literal "min(min(ram, 4096) + max(ram - 4096, 0) / 2, 32 * 1024)" "${all_vars}"
require_literal "arch_zram_compression_algorithm: zstd" "${all_vars}"
require_literal "arch_zram_swap_priority: 100" "${all_vars}"
require_literal "arch_memory_pressure_managed: true" "${workstation_vars}"
require_literal "arch_memory_pressure_enabled: true" "${workstation_vars}"

require_literal "Configure managed workstation memory pressure" "${base_tasks}"
require_literal "dest: /etc/systemd/zram-generator.conf" "${base_tasks}"
require_literal "dest: /etc/systemd/oomd.conf.d/50-workstation.conf" "${base_tasks}"
require_literal "dest: /etc/systemd/user/app.slice.d/50-workstation-oomd.conf" "${base_tasks}"
require_literal "name: systemd-oomd.service" "${base_tasks}"
require_literal "Restart systemd-oomd" "${base_handlers}"

require_literal "zram-size = {{ arch_zram_size_expression }}" "${base_templates}/zram-generator.conf.j2"
require_literal "compression-algorithm = {{ arch_zram_compression_algorithm }}" "${base_templates}/zram-generator.conf.j2"
require_literal "swap-priority = {{ arch_zram_swap_priority }}" "${base_templates}/zram-generator.conf.j2"
require_literal "SwapUsedLimit={{ arch_oomd_swap_used_limit }}" "${base_templates}/oomd-workstation.conf.j2"
require_literal "ManagedOOMSwap=kill" "${base_templates}/app-slice-oomd.conf.j2"
require_literal "ManagedOOMMemoryPressure=kill" "${base_templates}/app-slice-oomd.conf.j2"

require_literal "Slice=session.slice" "${berg_unit}"
require_literal "ManagedOOMPreference=omit" "${berg_unit}"
require_literal "Slice=background.slice" "${rclone_unit}"
require_literal "ManagedOOMPreference=omit" "${rclone_unit}"
require_literal "Slice=background.slice" "${rclone_gdrive_unit}"
require_literal "ManagedOOMPreference=omit" "${rclone_gdrive_unit}"

SYSTEMD_LOG_LEVEL=err systemd-analyze --user verify "${berg_unit}" "${rclone_unit}" "${rclone_gdrive_unit}"

echo "Memory-pressure policy invariants passed"
