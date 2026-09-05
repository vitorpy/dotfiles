#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
all_vars="${repo_root}/group_vars/all.yml"
personal_vars="${repo_root}/group_vars/personal_workstation.yml"
corp_vars="${repo_root}/group_vars/corp_workstation.yml"
package_tasks="${repo_root}/roles/packages/tasks/main.yml"
google_earth_desktop="${repo_root}/roles/packages/templates/google-earth-pro.desktop.j2"
ansible_temp="$(mktemp -d /tmp/ansible-personal-workstation-test.XXXXXX)"
trap 'rm -rf -- "${ansible_temp}"' EXIT
inventory_json="$(
  ANSIBLE_CONFIG="${repo_root}/ansible.cfg" \
    ANSIBLE_LOCAL_TEMP="${ansible_temp}/local" \
    ANSIBLE_REMOTE_TEMP="${ansible_temp}/remote" \
    ansible-inventory --playbook-dir "${repo_root}" --list
)"
personal_host_json="$(
  ANSIBLE_CONFIG="${repo_root}/ansible.cfg" \
    ANSIBLE_LOCAL_TEMP="${ansible_temp}/local" \
    ANSIBLE_REMOTE_TEMP="${ansible_temp}/remote" \
    ansible-inventory --playbook-dir "${repo_root}" --host localhost
)"
corp_host_json="$(
  ANSIBLE_CONFIG="${repo_root}/ansible.cfg" \
    ANSIBLE_LOCAL_TEMP="${ansible_temp}/local" \
    ANSIBLE_REMOTE_TEMP="${ansible_temp}/remote" \
    ansible-inventory --playbook-dir "${repo_root}" --host rivest
)"

require_literal() {
  local literal="$1"
  local file="$2"
  grep -Fq -- "${literal}" "${file}" || {
    echo "missing '${literal}' in ${file}" >&2
    exit 1
  }
}

require_literal "arch_notion_cli_enabled: false" "${all_vars}"
require_literal "arch_notion_cli_enabled: true" "${personal_vars}"
require_literal "arch_google_earth_pro_desktop_override_enabled: false" "${all_vars}"
require_literal "arch_google_earth_pro_desktop_override_enabled: true" "${personal_vars}"
require_literal "arch_aur_packages_personal: []" "${all_vars}"
require_literal "arch_aur_packages_personal:" "${personal_vars}"
require_literal "  - shellcheck" "${all_vars}"
require_literal "  - claude-code" "${personal_vars}"
require_literal "  - gemini-cli" "${personal_vars}"
require_literal "  - google-earth-pro" "${personal_vars}"
require_literal "+ arch_aur_packages_personal" "${repo_root}/group_vars/workstation.yml"
require_literal "arch_corp_workstation_enabled: true" "${corp_vars}"
require_literal "Download official Notion CLI archive" "${package_tasks}"
require_literal "checksum: \"{{ arch_notion_cli_archive_checksum }}\"" "${package_tasks}"
require_literal "Verify managed Notion CLI binary" "${package_tasks}"
require_literal "Install managed Google Earth Pro desktop override" "${package_tasks}"
require_literal "    - google-earth-pro" "${package_tasks}"
require_literal "Exec=/usr/bin/env BROWSER=/usr/bin/google-chrome-stable" "${google_earth_desktop}"

jq -e '
  .personal_workstation.hosts == ["localhost"] and
  .corp_workstation.hosts == ["rivest"] and
  (.workstation.children | index("personal_workstation") != null) and
  (.workstation.children | index("corp_workstation") != null)
' <<< "${inventory_json}" >/dev/null

jq -e '
  .arch_notion_cli_enabled == true and
  .arch_google_earth_pro_desktop_override_enabled == true and
  (.arch_pacman_packages_development | index("shellcheck") != null) and
  (.arch_aur_packages_personal | index("claude-code") != null) and
  (.arch_aur_packages_personal | index("gemini-cli") != null) and
  (.arch_aur_packages_personal | index("google-earth-pro") != null)
' <<< "${personal_host_json}" >/dev/null
jq -e '
  .arch_notion_cli_enabled == false and
  .arch_google_earth_pro_desktop_override_enabled == false and
  (.arch_pacman_packages_development | index("shellcheck") != null) and
  (.arch_aur_packages_personal | index("claude-code") == null) and
  (.arch_aur_packages_personal | index("gemini-cli") == null) and
  (.arch_aur_packages_personal | index("google-earth-pro") == null)
' <<< "${corp_host_json}" >/dev/null

echo "Personal workstation invariants passed"
