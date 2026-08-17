#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
keyring_tasks="${repo_root}/roles/keyring/tasks/main.yml"
keyring_template="${repo_root}/roles/keyring/templates/gnome-keyring-dbus.service.j2"
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

require_literal "arch_gnome_keyring_systemd_activation_enabled: true" "${workstation_vars}"
require_literal "  - org.freedesktop.secrets" "${all_vars}"
require_literal "  - org.gnome.keyring" "${all_vars}"
require_literal "  - org.freedesktop.impl.portal.Secret" "${all_vars}"
require_literal ".local/share/dbus-1/services" "${keyring_tasks}"
require_literal "ReloadConfig" "${keyring_tasks}"
require_literal "SystemdService=gnome-keyring-daemon.service" "${keyring_template}"
require_literal "Exec=/usr/bin/gnome-keyring-daemon --start --foreground --components=secrets" "${keyring_template}"
require_literal "- role: keyring" "${site}"
require_literal "- keyring" "${site}"
reject_literal "pkill" "${keyring_tasks}"
reject_literal "killall" "${keyring_tasks}"

echo "GNOME Keyring activation invariants passed"
