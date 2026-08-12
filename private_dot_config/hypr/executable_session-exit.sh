#!/usr/bin/env bash

usage() {
    printf 'Usage: %s logout|reboot|poweroff\n' "${0##*/}" >&2
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

hyprshutdown --no-fork --no-exit --top-label "$label"
shutdown_status=$?
if (( shutdown_status != 0 )); then
    exit "$shutdown_status"
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
