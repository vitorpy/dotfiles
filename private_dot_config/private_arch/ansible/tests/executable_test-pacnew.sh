#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
pacnew_tasks="${repo_root}/roles/pacnew/tasks/main.yml"
sudo_template="${repo_root}/roles/security/templates/sudo.j2"
mkinitcpio_template="${repo_root}/roles/boot/templates/mkinitcpio.conf.j2"
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

require_literal "arch_pacnew_reconciliation_enabled: true" "${workstation_vars}"
require_literal "/etc/locale.gen.pacnew:" "${workstation_vars}"
require_literal "/etc/mkinitcpio.conf.pacnew:" "${workstation_vars}"
require_literal "/etc/makepkg.conf.d/fortran.conf.pacnew:" "${workstation_vars}"
require_literal "/etc/pacman.d/mirrorlist.pacnew:" "${workstation_vars}"
require_literal "/etc/pam.d/sudo.pacnew:" "${workstation_vars}"
require_literal "/etc/tpm2-tss/fapi-profiles/P_ECCP384SHA384.json.pacnew:" "${workstation_vars}"
require_literal "/etc/tpm2-tss/fapi-profiles/P_RSA3072SHA384.json.pacnew:" "${workstation_vars}"

require_literal "Reject unreviewed pacnew files" "${pacnew_tasks}"
require_literal "checksum_algorithm: sha256" "${pacnew_tasks}"
require_literal "Reject changed pacnew contents" "${pacnew_tasks}"
require_literal "preserve_current" "${workstation_vars}"
require_literal "Verify no pacnew files remain" "${pacnew_tasks}"
require_literal "pacdiff -o" "${pacnew_tasks}"
require_literal "arch_sudo_fingerprint_auth_enabled" "${sudo_template}"
require_literal "pam_fprintd.so" "${sudo_template}"
require_literal "pam_systemd.so class=none" "${sudo_template}"
require_literal "HOOKS=({{ arch_mkinitcpio_hooks | join(' ') }})" "${mkinitcpio_template}"
require_literal "- role: pacnew" "${site}"

echo "Pacnew merge invariants passed"
