#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
boot_tasks="${repo_root}/roles/boot/tasks/main.yml"
boot_templates="${repo_root}/roles/boot/templates"
all_vars="${repo_root}/group_vars/all.yml"
workstation_vars="${repo_root}/group_vars/workstation.yml"
site="${repo_root}/site.yml"

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
  local first_line second_line
  first_line="$(grep -nF -- "${first}" "${file}" | head -n1 | cut -d: -f1)"
  second_line="$(grep -nF -- "${second}" "${file}" | head -n1 | cut -d: -f1)"
  [[ -n "${first_line}" && -n "${second_line}" && "${first_line}" -lt "${second_line}" ]] || {
    echo "expected '${first}' before '${second}' in ${file}" >&2
    exit 1
  }
}

require_literal "arch_boot_enabled: true" "${workstation_vars}"
require_literal "arch_manage_secure_boot: true" "${workstation_vars}"
require_literal "arch_esp_uuid: 7F53-362E" "${workstation_vars}"
require_literal "root=PARTUUID=c38a539b-1954-45af-b933-78f2b88f2fc3" "${workstation_vars}"
require_literal "arch_boot_recovery_confirmed: false" "${all_vars}"
require_literal "fmask=0077,dmask=0077" "${all_vars}"
require_literal "  - systemd" "${all_vars}"
require_literal "  - sd-vconsole" "${all_vars}"
reject_literal "arch_luks_uuid" "${all_vars}"
reject_literal "cryptdevice=UUID=" "${boot_tasks}"

require_literal "Require recovery readiness before the initial UKI boot" "${boot_tasks}"
require_literal "Validate the managed fstab before the reboot boundary" "${boot_tasks}"
require_literal "Verify root-only ESP options after a managed UKI boot" "${boot_tasks}"
require_literal "Report ESP option activation pending a clean boot" "${boot_tasks}"
reject_literal "state: restarted" "${boot_tasks}"
reject_literal "fuser" "${boot_tasks}"
require_literal "bootctl --print-stub-path" "${boot_tasks}"
require_literal "bootctl" "${boot_tasks}"
require_literal "kernel-identify" "${boot_tasks}"
require_literal "kernel-inspect" "${boot_tasks}"
require_literal "sbctl verify" "${boot_tasks}"
require_literal '"{{ arch_uki_default_path }}"' "${boot_tasks}"
require_literal '"{{ arch_uki_fallback_path }}"' "${boot_tasks}"
require_literal "Retire legacy split boot entries after a confirmed UKI boot" "${boot_tasks}"
require_before "Verify the signed boot chain with sbctl" "Render systemd-boot loader configuration" "${boot_tasks}"

require_literal "PRESETS=('default' 'fallback')" "${boot_templates}/linux.preset.j2"
require_literal 'fallback_options="-S autodetect"' "${boot_templates}/linux.preset.j2"
require_literal "HOOKS=({{ arch_mkinitcpio_hooks | join(' ') }})" "${boot_templates}/mkinitcpio.conf.j2"
require_literal "default arch.conf" "${boot_templates}/loader.conf.j2"
require_literal "efi     {{ boot_entry_uki }}" "${boot_templates}/uki-entry.conf.j2"
require_literal "- role: boot" "${site}"
require_literal "- boot" "${site}"

echo "Boot and UKI invariants passed"
