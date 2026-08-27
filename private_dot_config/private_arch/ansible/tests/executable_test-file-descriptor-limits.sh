#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
base_tasks="${repo_root}/roles/base/tasks/main.yml"
limit_template="${repo_root}/roles/base/templates/default-limit-nofile.conf.j2"
all_vars="${repo_root}/group_vars/all.yml"
workstation_vars="${repo_root}/group_vars/workstation.yml"

require_literal() {
    local literal="$1"
    local file="$2"

    grep -Fq -- "${literal}" "${file}" || {
        echo "missing '${literal}' in ${file}" >&2
        exit 1
    }
}

require_literal "arch_file_descriptor_limits_managed: false" "${all_vars}"
require_literal "arch_file_descriptor_limits_enabled: false" "${all_vars}"
require_literal "arch_default_limit_nofile_soft: 65536" "${all_vars}"
require_literal "arch_default_limit_nofile_hard: 524288" "${all_vars}"
require_literal "arch_file_descriptor_limits_managed: true" "${workstation_vars}"
require_literal "arch_file_descriptor_limits_enabled: true" "${workstation_vars}"

require_literal "Configure managed workstation file descriptor limits" "${base_tasks}"
require_literal "/etc/systemd/system.conf.d/50-workstation-nofile.conf" "${base_tasks}"
require_literal "/etc/systemd/user.conf.d/50-workstation-nofile.conf" "${base_tasks}"
require_literal "Remove systemd manager file descriptor limits when disabled" "${base_tasks}"
require_literal "state: absent" "${base_tasks}"

require_literal "[Manager]" "${limit_template}"
require_literal \
    "DefaultLimitNOFILE={{ arch_default_limit_nofile_soft }}:{{ arch_default_limit_nofile_hard }}" \
    "${limit_template}"

echo "File-descriptor limit policy invariants passed"
