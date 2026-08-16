#!/usr/bin/env bash

set -euo pipefail

action=${1:-status}
canonical_profiles=(power-saver balanced performance)

read_profiles() {
    local line
    profiles=()

    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*\*?[[:space:]]*(power-saver|balanced|performance):[[:space:]]*$ ]]; then
            profiles+=("${BASH_REMATCH[1]}")
        fi
    done < <(powerprofilesctl list)

    ((${#profiles[@]} > 0))
}

profile_is_available() {
    local candidate=$1
    local available

    for available in "${profiles[@]}"; do
        [[ $available == "$candidate" ]] && return 0
    done

    return 1
}

emit_status() {
    local active tooltip available_json

    active=$(powerprofilesctl get)
    read_profiles
    tooltip="Power profile: $active
Available: ${profiles[*]}
Click to cycle"
    available_json=$(printf '%s\n' "${profiles[@]}" | jq -R . | jq -sc .)

    jq -cn \
        --arg text "$active" \
        --arg tooltip "$tooltip" \
        --argjson available "$available_json" \
        '{text: $text, tooltip: $tooltip, available: $available}'
}

cycle_profile() {
    local active current_index=-1 offset candidate_index candidate

    active=$(powerprofilesctl get)
    read_profiles

    for offset in "${!canonical_profiles[@]}"; do
        if [[ ${canonical_profiles[$offset]} == "$active" ]]; then
            current_index=$offset
            break
        fi
    done

    for ((offset = 1; offset <= ${#canonical_profiles[@]}; ++offset)); do
        candidate_index=$(((current_index + offset) % ${#canonical_profiles[@]}))
        candidate=${canonical_profiles[$candidate_index]}
        if profile_is_available "$candidate"; then
            powerprofilesctl set "$candidate"
            emit_status
            return 0
        fi
    done

    printf 'No advertised power profile is available\n' >&2
    return 1
}

case "$action" in
    status)
        emit_status
        ;;
    cycle)
        cycle_profile
        ;;
    *)
        printf 'Usage: %s [status|cycle]\n' "$0" >&2
        exit 2
        ;;
esac
