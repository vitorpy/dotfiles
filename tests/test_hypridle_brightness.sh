#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper=$repo_root/private_dot_config/hypr/executable_hypridle-brightness.sh
test_root=$(mktemp -d)
fake_state=$test_root/devices
runtime_state=$test_root/runtime
fake_brightnessctl=$test_root/brightnessctl

cleanup() {
    rm -rf -- "$test_root"
}
trap cleanup EXIT

mkdir -p -- "$fake_state"

cat >"$fake_brightnessctl" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail

[[ ${1:-} == -d && $# -ge 3 ]]
device=$2
operation=$3
device_dir=$FAKE_BRIGHTNESS_DIR/$device

case $operation in
    get)
        cat "$device_dir/current"
        ;;
    max)
        cat "$device_dir/max"
        ;;
    set)
        [[ $# == 4 ]]
        if [[ ${FAKE_FAIL_SET_DEVICE:-} == "$device" ]]; then
            exit 9
        fi
        printf '%s\n' "$4" >"$device_dir/current"
        ;;
    *)
        exit 2
        ;;
esac
FAKE
chmod 700 "$fake_brightnessctl"

make_device() {
    local device=$1 current=$2 maximum=$3

    mkdir -p -- "$fake_state/$device"
    printf '%s\n' "$current" >"$fake_state/$device/current"
    printf '%s\n' "$maximum" >"$fake_state/$device/max"
}

run_helper() {
    FAKE_BRIGHTNESS_DIR=$fake_state \
        HYPRIDLE_BRIGHTNESSCTL_BIN=$fake_brightnessctl \
        HYPRIDLE_BRIGHTNESS_STATE_DIR=$runtime_state \
        bash "$helper" "$@"
}

assert_value() {
    local expected=$1 path=$2 actual

    actual=$(<"$path")
    if [[ $actual != "$expected" ]]; then
        printf 'Expected %s in %s, got %s\n' "$expected" "$path" "$actual" >&2
        exit 1
    fi
}

assert_absent() {
    if [[ -e $1 ]]; then
        printf 'Expected %s to be absent\n' "$1" >&2
        exit 1
    fi
}

make_device amdgpu_bl1 400 1000
make_device chromeos::kbd_backlight 50 100

run_helper dim-display
assert_value 10 "$fake_state/amdgpu_bl1/current"
assert_value 400 "$runtime_state/display"

# Repeated dimming must not replace the original snapshot.
printf '25\n' >"$fake_state/amdgpu_bl1/current"
run_helper dim-display
assert_value 10 "$fake_state/amdgpu_bl1/current"
assert_value 400 "$runtime_state/display"

run_helper restore-display
assert_value 400 "$fake_state/amdgpu_bl1/current"
assert_absent "$runtime_state/display"

run_helper dim-keyboard
assert_value 0 "$fake_state/chromeos::kbd_backlight/current"
assert_value 50 "$runtime_state/keyboard"
run_helper restore-keyboard
assert_value 50 "$fake_state/chromeos::kbd_backlight/current"
assert_absent "$runtime_state/keyboard"

# A lid-style wake restores both devices without listener resume callbacks.
printf '700\n' >"$fake_state/amdgpu_bl1/current"
printf '30\n' >"$fake_state/chromeos::kbd_backlight/current"
run_helper dim-display
run_helper dim-keyboard
run_helper restore-all
assert_value 700 "$fake_state/amdgpu_bl1/current"
assert_value 30 "$fake_state/chromeos::kbd_backlight/current"
assert_absent "$runtime_state/display"
assert_absent "$runtime_state/keyboard"

# With no saved state, a quick lid wake is a no-op.
run_helper restore-all
assert_value 700 "$fake_state/amdgpu_bl1/current"
assert_value 30 "$fake_state/chromeos::kbd_backlight/current"

# Corrupt state must fail closed and remain available for diagnosis.
printf 'invalid\n' >"$runtime_state/display"
if run_helper restore-display; then
    printf 'Expected corrupt display state to fail\n' >&2
    exit 1
fi
assert_value invalid "$runtime_state/display"
assert_value 700 "$fake_state/amdgpu_bl1/current"
rm -f -- "$runtime_state/display"

# restore-all must restore the healthy device even if the other write fails.
run_helper dim-display
run_helper dim-keyboard
if FAKE_FAIL_SET_DEVICE=amdgpu_bl1 run_helper restore-all; then
    printf 'Expected display restore failure\n' >&2
    exit 1
fi
assert_value 10 "$fake_state/amdgpu_bl1/current"
assert_value 30 "$fake_state/chromeos::kbd_backlight/current"
assert_value 700 "$runtime_state/display"
assert_absent "$runtime_state/keyboard"
run_helper restore-display
assert_value 700 "$fake_state/amdgpu_bl1/current"
assert_absent "$runtime_state/display"

if run_helper invalid-action; then
    printf 'Expected invalid action to fail\n' >&2
    exit 1
fi

printf 'hypridle brightness tests passed\n'
