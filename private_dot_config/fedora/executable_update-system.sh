#!/usr/bin/env bash
# Interactive Fedora RPM update. Flatpak and firmware have separate workflows.
set -euo pipefail
# shellcheck disable=SC1091
source /etc/os-release
[[ $ID == fedora ]] || { echo 'This updater requires Fedora.' >&2; exit 1; }
refresh_berg_updates() {
    local result=$?
    if systemctl --user is-active --quiet quickshell-berg.service; then
        qs -c berg ipc call shell refreshUpdates >/dev/null 2>&1 || true
    fi
    return "$result"
}
trap refresh_berg_updates EXIT
printf 'Fedora RPM updates (all enabled repositories)\n\n'
updates=$(dnf5 --quiet --assumeyes --refresh repoquery --upgrades --latest-limit=1 --queryformat '%{name}.%{arch} %{evr}\n')
if [[ -z $updates ]]; then
    echo 'RPM packages are up to date.'; exit 0
fi
printf '%s\n\n' "$updates"
read -r -p 'Proceed with RPM updates? [y/N] ' answer
[[ $answer == y || $answer == Y ]] || exit 0
available=$(df --output=avail --block-size=1 / | tail -n 1)
if [[ ! $available =~ ^[[:space:]]*[0-9]+[[:space:]]*$ ]] || (( available < 10 * 1024 * 1024 * 1024 )); then
    echo 'At least 10 GiB free on / is required.' >&2; exit 1
fi
sudo -v
sudo -n dnf5 --refresh upgrade
