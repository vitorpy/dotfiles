#!/usr/bin/env bash

set -u

readonly window_class="hyprpwcenter"

if [[ -n ${XDG_RUNTIME_DIR:-} ]]; then
    lock_file="${XDG_RUNTIME_DIR}/waybar-hyprpwcenter-toggle.lock"
else
    lock_file="/tmp/waybar-hyprpwcenter-toggle-${UID}.lock"
fi

umask 077
exec 9>"${lock_file}"

# Ignore overlapping clicks while an earlier toggle is still settling.
if ! flock -n 9; then
    exit 0
fi

if ! clients_json=$(hyprctl -j clients); then
    printf 'hyprpwcenter-toggle: could not query Hyprland clients\n' >&2
    exit 1
fi

if ! addresses_text=$(jq -r \
    --arg class "${window_class}" \
    '.[] | select((.class // "") == $class) | .address' \
    <<<"${clients_json}"); then
    printf 'hyprpwcenter-toggle: could not parse Hyprland clients\n' >&2
    exit 1
fi

addresses=()
if [[ -n ${addresses_text} ]]; then
    mapfile -t addresses <<<"${addresses_text}"
fi

if (( ${#addresses[@]} > 0 )); then
    close_failed=0

    for address in "${addresses[@]}"; do
        if ! hyprctl dispatch \
            "hl.dsp.window.close({ window = \"address:${address}\" })"; then
            printf 'hyprpwcenter-toggle: could not close window %s\n' "${address}" >&2
            close_failed=1
        fi
    done

    exit "${close_failed}"
fi

# Close the lock descriptor in the child so it is held only while this helper
# waits for the new window to register with Hyprland.
uwsm app -- hyprpwcenter 9>&- >/dev/null &

for ((attempt = 0; attempt < 50; attempt++)); do
    if clients_json=$(hyprctl -j clients) &&
        jq -e --arg class "${window_class}" \
            'any(.[]; (.class // "") == $class)' \
            <<<"${clients_json}" >/dev/null; then
        exit 0
    fi

    sleep 0.1
done

printf 'hyprpwcenter-toggle: window did not appear within 5 seconds\n' >&2
exit 1
