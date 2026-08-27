#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
berg_root="$(cd "${script_dir}/.." && pwd)"
private_config_root="$(cd "${berg_root}/../.." && pwd)"
state_file="${berg_root}/PackageUpdatesState.qml"
policy_file="${berg_root}/PackageUpdates.js"
bar_state_file="${berg_root}/BarState.qml"
shell_file="${berg_root}/shell.qml"
source_updater="${private_config_root}/private_arch/executable_update-system.sh"
live_updater="${private_config_root}/arch/update-system.sh"

if [[ -f "${source_updater}" ]]; then
    updater="${source_updater}"
elif [[ -f "${live_updater}" ]]; then
    updater="${live_updater}"
else
    echo "unable to locate the managed system updater" >&2
    exit 1
fi

require_literal() {
    local literal="$1"
    local file="$2"

    grep -Fq -- "${literal}" "${file}" || {
        echo "missing '${literal}' in ${file}" >&2
        exit 1
    }
}

require_literal "return 60 * 60 * 1000;" "${policy_file}"
require_literal "PackageUpdates.refreshIsBusy(official.running, aur.running)" "${state_file}"
require_literal "refreshPending = true;" "${state_file}"
require_literal "refreshPending = false;" "${state_file}"
require_literal "Qt.callLater(refresh);" "${state_file}"
require_literal "interval: PackageUpdates.periodicRefreshIntervalMs()" "${state_file}"
require_literal "triggeredOnStart: true" "${state_file}"
require_literal "function refreshUpdates(): void" "${bar_state_file}"
require_literal "function updatesStatus(): string" "${bar_state_file}"
require_literal "function refreshUpdates(): void" "${shell_file}"
require_literal "function updatesStatus(): string" "${shell_file}"
require_literal "trap refresh_berg_updates EXIT" "${updater}"
require_literal "ipc call shell refreshUpdates" "${updater}"

bash -n "${updater}"
/usr/lib/qt6/bin/qmllint \
    "${state_file}" \
    "${bar_state_file}" \
    "${shell_file}"

echo "Package-update polling policy invariants passed"
