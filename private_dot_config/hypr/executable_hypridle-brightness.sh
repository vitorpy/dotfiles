#!/usr/bin/env bash

set -euo pipefail

brightnessctl_bin=${HYPRIDLE_BRIGHTNESSCTL_BIN:-/usr/bin/brightnessctl}
state_dir=${HYPRIDLE_BRIGHTNESS_STATE_DIR:-${XDG_RUNTIME_DIR:?}/hypridle-brightness}
display_device=${HYPRIDLE_DISPLAY_DEVICE:-amdgpu_bl1}
keyboard_device=${HYPRIDLE_KEYBOARD_DEVICE:-chromeos::kbd_backlight}

umask 077
mkdir -p -- "$state_dir"
chmod 700 -- "$state_dir"

exec 9>"$state_dir/lock"
flock -x 9

fail() {
    printf 'hypridle-brightness: %s\n' "$*" >&2
    return 1
}

read_device_value() {
    local device=$1 operation=$2 value

    if ! value=$("$brightnessctl_bin" -d "$device" "$operation"); then
        fail "unable to read $operation for $device"
        return 1
    fi
    if [[ ! $value =~ ^[0-9]+$ ]]; then
        fail "invalid $operation value for $device: $value"
        return 1
    fi

    printf '%s\n' "$value"
}

save_device() {
    local device=$1 state_file=$2 current temporary

    [[ -e $state_file ]] && return 0

    current=$(read_device_value "$device" get) || return 1
    temporary=$(mktemp "$state_dir/.snapshot.XXXXXX") || return 1
    if ! printf '%s\n' "$current" >"$temporary"; then
        rm -f -- "$temporary"
        return 1
    fi
    if ! mv -- "$temporary" "$state_file"; then
        rm -f -- "$temporary"
        return 1
    fi
}

dim_device() {
    local device=$1 state_file=$2 target=$3

    save_device "$device" "$state_file" || return 1
    if ! "$brightnessctl_bin" -d "$device" set "$target"; then
        fail "unable to dim $device"
        return 1
    fi
}

restore_device() {
    local device=$1 state_file=$2 saved maximum

    [[ -e $state_file ]] || return 0

    if ! saved=$(<"$state_file") || [[ ! $saved =~ ^[0-9]+$ ]]; then
        fail "invalid saved brightness for $device"
        return 1
    fi
    maximum=$(read_device_value "$device" max) || return 1
    if (( 10#$saved > 10#$maximum )); then
        fail "saved brightness for $device exceeds its maximum"
        return 1
    fi
    if ! "$brightnessctl_bin" -d "$device" set "$saved"; then
        fail "unable to restore $device"
        return 1
    fi

    rm -f -- "$state_file"
}

restore_all() {
    local status=0

    restore_device "$display_device" "$state_dir/display" || status=1
    restore_device "$keyboard_device" "$state_dir/keyboard" || status=1
    return "$status"
}

case ${1:-} in
    dim-display)
        dim_device "$display_device" "$state_dir/display" 10
        ;;
    dim-keyboard)
        dim_device "$keyboard_device" "$state_dir/keyboard" 0
        ;;
    restore-display)
        restore_device "$display_device" "$state_dir/display"
        ;;
    restore-keyboard)
        restore_device "$keyboard_device" "$state_dir/keyboard"
        ;;
    restore-all)
        restore_all
        ;;
    *)
        printf 'Usage: %s dim-display|dim-keyboard|restore-display|restore-keyboard|restore-all\n' "${0##*/}" >&2
        exit 2
        ;;
esac
