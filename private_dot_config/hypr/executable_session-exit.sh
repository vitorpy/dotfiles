#!/usr/bin/env bash

usage() {
    printf 'Usage: %s logout|reboot|poweroff\n' "${0##*/}" >&2
}

hyprland_has_remaining_apps() {
    local clients_json layers_json instances_json hyprland_pid child_processes

    if ! clients_json=$(hyprctl clients -j); then
        return 0
    fi
    if ! jq -e 'type == "array" and length == 0' <<<"$clients_json" >/dev/null; then
        return 0
    fi

    if ! layers_json=$(hyprctl layers -j); then
        return 0
    fi
    if ! jq -e 'type == "object" and ([.[]?.levels[][]?] | length == 0)' <<<"$layers_json" >/dev/null; then
        return 0
    fi

    if ! instances_json=$(hyprctl instances -j); then
        return 0
    fi
    if ! hyprland_pid=$(jq -er --arg instance "${HYPRLAND_INSTANCE_SIGNATURE:-}" \
        'first(.[] | select(.instance == $instance) | .pid) | select(type == "number")' \
        <<<"$instances_json"); then
        return 0
    fi

    child_processes=$(ps -o pid=,comm= --ppid "$hyprland_pid")

    while read -r child_pid child_name; do
        if [[ -n "$child_pid" && "$child_name" != "Xwayland" ]]; then
            return 0
        fi
    done <<<"$child_processes"

    return 1
}

if (( $# != 1 )); then
    usage
    exit 2
fi

case "$1" in
    logout)
        label="Logging out..."
        ;;
    reboot)
        label="Restarting..."
        ;;
    poweroff)
        label="Shutting down..."
        ;;
    *)
        usage
        exit 2
        ;;
esac

if [[ ${HYPR_SESSION_EXIT_SCOPED:-0} != 1 ]]; then
    script_path=$(readlink -f -- "$0") || exit 1

    exec systemd-run \
        --user \
        --collect \
        --quiet \
        --unit=hypr-session-exit \
        --description="Graceful Hyprland session exit" \
        --service-type=exec \
        --property=ExitType=cgroup \
        --setenv=HYPR_SESSION_EXIT_SCOPED=1 \
        -- "$script_path" "$1"
fi

hyprshutdown --no-fork --no-exit --top-label "$label"
shutdown_status=$?
if (( shutdown_status != 0 )); then
    exit "$shutdown_status"
fi

# In --no-exit mode Hyprshutdown returns 0 for both completion and Cancel.
# A completed run has removed every client, layer, and direct Hyprland child;
# if anything remains, keep the session alive and treat the run as cancelled.
if hyprland_has_remaining_apps; then
    exit 0
fi

case "$1" in
    logout)
        exec uwsm stop
        ;;
    reboot)
        exec systemctl reboot
        ;;
    poweroff)
        exec systemctl poweroff
        ;;
esac
