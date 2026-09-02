#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
all_vars="${repo_root}/group_vars/all.yml"
workstation_vars="${repo_root}/group_vars/workstation.yml"
corp_vars="${repo_root}/group_vars/corp_workstation.yml"
inventory="${repo_root}/inventory/hosts.yml"
archiso_build="${repo_root}/../archiso/framework12/build.sh"
if [[ ! -f "${archiso_build}" ]]; then
  archiso_build="${repo_root}/../archiso/framework12/executable_build.sh"
fi
ansible_temp="$(mktemp -d /tmp/ansible-corp-workstation-test.XXXXXX)"
trap 'rm -rf -- "${ansible_temp}"' EXIT
inventory_json="$(
  ANSIBLE_CONFIG="${repo_root}/ansible.cfg" \
    ANSIBLE_LOCAL_TEMP="${ansible_temp}/local" \
    ANSIBLE_REMOTE_TEMP="${ansible_temp}/remote" \
    ansible-inventory --list
)"

require_literal() {
  local literal="$1"
  local file="$2"
  grep -Fq -- "${literal}" "${file}" || {
    echo "missing '${literal}' in ${file}" >&2
    exit 1
  }
}

require_single_package_declaration() {
  local package="$1"
  local count
  count="$(grep -Ec "^[[:space:]]+- ${package}$" "${all_vars}")"
  if [[ "${count}" != "1" ]]; then
    echo "expected one declaration of ${package}, found ${count}" >&2
    exit 1
  fi
}

require_literal "arch_corp_workstation_enabled: false" "${all_vars}"
require_literal "arch_aur_packages_corporate:" "${all_vars}"
require_literal "arch_corp_workstation_enabled: true" "${corp_vars}"
require_literal "+ (arch_aur_packages_corporate if arch_corp_workstation_enabled else [])" "${workstation_vars}"
require_literal "corp_workstation:" "${inventory}"
require_literal "rivest:" "${inventory}"
require_literal "arch_aur_packages_corporate" "${archiso_build}"

jq -e '
  .corp_workstation.hosts == ["rivest"] and
  (.workstation.children | index("corp_workstation") != null) and
  (.workstation.children | index("personal_workstation") != null) and
  .personal_workstation.hosts == ["localhost"]
' <<< "${inventory_json}" >/dev/null

require_single_package_declaration 1password
require_single_package_declaration 1password-cli
require_single_package_declaration slack-desktop

echo "Corporate workstation invariants passed"
