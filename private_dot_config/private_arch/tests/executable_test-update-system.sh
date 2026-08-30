#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${script_dir}/../update-system.sh" ]]; then
    update_script="${script_dir}/../update-system.sh"
else
    update_script="${script_dir}/../executable_update-system.sh"
fi
[[ -f ${update_script} ]] || {
    echo "FAIL: unable to locate the managed update script" >&2
    exit 1
}
real_yay="$(command -v yay)"

tmpdir="$(mktemp -d /tmp/arch-update-system-test.XXXXXX)"
trap 'rm -rf -- "${tmpdir}"' EXIT

mock_bin="${tmpdir}/bin"
calls_file="${tmpdir}/calls"
mkdir -p "${mock_bin}"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

require_exact_call() {
    local expected="$1"

    grep -Fxq -- "${expected}" "${calls_file}" ||
        fail "missing call: ${expected}"
}

cat > "${mock_bin}/pkexec" <<'EOF'
#!/usr/bin/env bash
printf 'pkexec %s\n' "$*" >> "${TEST_UPDATE_CALLS}"
if [[ ${TEST_PACCACHE_FAIL:-0} == "1" && $* == "paccache -rk3" ]]; then
    exit 1
fi
exit 0
EOF

cat > "${mock_bin}/df" <<'EOF'
#!/usr/bin/env bash
printf 'df %s\n' "$*" >> "${TEST_UPDATE_CALLS}"
printf 'Avail\n%s\n' "${TEST_DF_AVAILABLE}"
EOF

cat > "${mock_bin}/checkupdates" <<'EOF'
#!/usr/bin/env bash
printf 'checkupdates\n' >> "${TEST_UPDATE_CALLS}"
if [[ -n ${TEST_OFFICIAL_OUTPUT:-} ]]; then
    printf '%s\n' "${TEST_OFFICIAL_OUTPUT}"
fi
EOF

cat > "${mock_bin}/pacman" <<'EOF'
#!/usr/bin/env bash
printf 'pacman %s\n' "$*" >> "${TEST_UPDATE_CALLS}"
if [[ ${1:-} == "-Qtdq" && -n ${TEST_ORPHANS:-} ]]; then
    printf '%s\n' "${TEST_ORPHANS}"
fi
EOF

cat > "${mock_bin}/yay" <<'EOF'
#!/usr/bin/env bash
printf 'yay %s\n' "$*" >> "${TEST_UPDATE_CALLS}"
if [[ ${1:-} == "-Qua" && -n ${TEST_AUR_OUTPUT:-} ]]; then
    printf '%s\n' "${TEST_AUR_OUTPUT}"
fi
EOF

cat > "${mock_bin}/fwupdmgr" <<'EOF'
#!/usr/bin/env bash
printf 'fwupdmgr %s\n' "$*" >> "${TEST_UPDATE_CALLS}"
EOF

chmod +x "${mock_bin}"/*

run_fixture() {
    local available_bytes="$1"
    local output_file="$2"
    local paccache_fail="${3:-0}"

    env \
        PATH="${mock_bin}:/usr/bin" \
        TEST_UPDATE_CALLS="${calls_file}" \
        TEST_DF_AVAILABLE="${available_bytes}" \
        TEST_PACCACHE_FAIL="${paccache_fail}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=${tmpdir}/no-user-bus" \
        XDG_RUNTIME_DIR="${tmpdir}/no-user-bus" \
        bash "${update_script}" > "${output_file}" 2>&1
}

# A no-op update must still prune exactly once before it checks for updates.
: > "${calls_file}"
zero_output="${tmpdir}/zero-update.out"
run_fixture "$((20 * 1024 * 1024 * 1024))" "${zero_output}"
mapfile -t zero_calls < "${calls_file}"
[[ ${zero_calls[0]:-} == "pkexec paccache -rk3" ]] ||
    fail "zero-update preflight did not prune first"
[[ ${zero_calls[1]:-} == "df --output=avail --block-size=1 /" ]] ||
    fail "zero-update preflight did not check root space second"
[[ $(grep -Fxc -- "pkexec paccache -rk3" "${calls_file}") -eq 1 ]] ||
    fail "zero-update path did not retain exactly three versions once"
grep -Fq -- "System is up to date" "${zero_output}" ||
    fail "zero-update path did not finish as a no-op"
if grep -Eq -- 'pacman -Syu|yay -Sua|fwupdmgr update' "${calls_file}"; then
    fail "zero-update path attempted a package transaction"
fi

# Cache pruning is opportunistic. A failure must stay visible but may not block
# discovery when the filesystem still has enough room for a safe update.
: > "${calls_file}"
prune_failure_output="${tmpdir}/prune-failure.out"
run_fixture \
    "$((20 * 1024 * 1024 * 1024))" \
    "${prune_failure_output}" \
    1
require_exact_call "checkupdates"
grep -Fq -- "Could not prune the package cache" "${prune_failure_output}" ||
    fail "package-cache failure was not reported"
grep -Fq -- "System is up to date" "${prune_failure_output}" ||
    fail "package-cache failure incorrectly blocked a safe no-op run"

# Pruning may recover space, but the update must stop before discovery when the
# root filesystem remains below the 10 GiB safety floor.
: > "${calls_file}"
low_output="${tmpdir}/low-space.out"
if run_fixture "$((10 * 1024 * 1024 * 1024 - 1))" "${low_output}"; then
    fail "low-space preflight unexpectedly succeeded"
fi
mapfile -t low_calls < "${calls_file}"
[[ ${#low_calls[@]} -eq 2 ]] ||
    fail "low-space path continued past storage preflight"
[[ ${low_calls[0]:-} == "pkexec paccache -rk3" ]] ||
    fail "low-space path did not prune before measuring"
[[ ${low_calls[1]:-} == "df --output=avail --block-size=1 /" ]] ||
    fail "low-space path did not measure root space"
grep -Fq -- "At least 10 GiB must be free on /" "${low_output}" ||
    fail "low-space path did not explain the safety floor"

# Exercise the full AUR path with fixtures so the repaired noninteractive
# cleanup remains wired after the transaction.
: > "${calls_file}"
aur_output="${tmpdir}/aur-update.out"
printf 'y' | env \
    PATH="${mock_bin}:/usr/bin" \
    TEST_UPDATE_CALLS="${calls_file}" \
    TEST_DF_AVAILABLE="$((20 * 1024 * 1024 * 1024))" \
    TEST_AUR_OUTPUT="roam 1.0-1 -> 1.1-1" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=${tmpdir}/no-user-bus" \
    XDG_RUNTIME_DIR="${tmpdir}/no-user-bus" \
    bash "${update_script}" > "${aur_output}" 2>&1
require_exact_call "yay -Sua"
require_exact_call "yay -Sc --aur --noconfirm"
grep -Fq -- "System update complete" "${aur_output}" ||
    fail "fixture AUR update did not complete"

mapfile -t aur_calls < "${calls_file}"
aur_update_index=-1
aur_cleanup_index=-1
for index in "${!aur_calls[@]}"; do
    case "${aur_calls[index]}" in
        "yay -Sua") aur_update_index="${index}" ;;
        "yay -Sc --aur --noconfirm") aur_cleanup_index="${index}" ;;
    esac
done
((aur_update_index >= 0 && aur_cleanup_index > aur_update_index)) ||
    fail "AUR cache cleanup did not follow the AUR transaction"

# Use Yay itself with an empty build directory and a deliberately failing
# Pacman executable. Success proves --aur still prevents redundant Pacman work.
[[ -x ${real_yay} ]] || fail "yay is required for the isolation check"
yay_builddir="${tmpdir}/yay-build"
mkdir -p "${yay_builddir}"
"${real_yay}" -Sc --aur --noconfirm \
    --builddir "${yay_builddir}" \
    --pacman /usr/bin/false > "${tmpdir}/real-yay.out"

echo "Updater preflight policy tests passed"
