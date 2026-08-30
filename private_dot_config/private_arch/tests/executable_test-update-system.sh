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

assert_single_interactive_sudo() {
    [[ $(grep -Fxc -- "sudo -v" "${calls_file}") -eq 1 ]] ||
        fail "expected exactly one interactive sudo validation"

    while IFS= read -r call; do
        case "${call}" in
            "sudo -v"|"sudo -n "*) ;;
            *) fail "privileged call was allowed to prompt: ${call}" ;;
        esac
    done < <(grep -E '^sudo ' "${calls_file}" || true)
}

cat > "${mock_bin}/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "${TEST_UPDATE_CALLS}"
if [[ ${TEST_PACCACHE_FAIL:-0} == "1" && $* == "-n paccache -rk3" ]]; then
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
if [[ ${1:-} == "-Syu" ]]; then
    sudo_command="sudo"
    sudo_flags=()
    while (($# > 0)); do
        case "$1" in
            --sudo)
                sudo_command="$2"
                shift 2
                ;;
            --sudoflags=*)
                read -r -a sudo_flags <<< "${1#*=}"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    "${sudo_command}" "${sudo_flags[@]}" pacman -U --noconfirm /tmp/mock-aur-package.pkg.tar.zst
fi
EOF

cat > "${mock_bin}/fwupdmgr" <<'EOF'
#!/usr/bin/env bash
printf 'fwupdmgr %s\n' "$*" >> "${TEST_UPDATE_CALLS}"
if [[ ${1:-} == "get-updates" && -n ${TEST_FIRMWARE_OUTPUT:-} ]]; then
    printf '%s\n' "${TEST_FIRMWARE_OUTPUT}"
fi
EOF

chmod +x "${mock_bin}"/*

run_fixture() {
    local available_bytes="$1"
    local output_file="$2"
    local paccache_fail="${3:-0}"
    local confirmation="${4:-}"

    printf '%s' "${confirmation}" | env \
        PATH="${mock_bin}:/usr/bin" \
        TEST_UPDATE_CALLS="${calls_file}" \
        TEST_DF_AVAILABLE="${available_bytes}" \
        TEST_PACCACHE_FAIL="${paccache_fail}" \
        TEST_OFFICIAL_OUTPUT="${TEST_OFFICIAL_OUTPUT:-}" \
        TEST_AUR_OUTPUT="${TEST_AUR_OUTPUT:-}" \
        TEST_FIRMWARE_OUTPUT="${TEST_FIRMWARE_OUTPUT:-}" \
        TEST_ORPHANS="${TEST_ORPHANS:-}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=${tmpdir}/no-user-bus" \
        XDG_RUNTIME_DIR="${tmpdir}/no-user-bus" \
        bash "${update_script}" > "${output_file}" 2>&1
}

# A no-op update must complete discovery without requesting authorization.
: > "${calls_file}"
zero_output="${tmpdir}/zero-update.out"
run_fixture "$((20 * 1024 * 1024 * 1024))" "${zero_output}"
mapfile -t zero_calls < "${calls_file}"
[[ ${zero_calls[0]:-} == "checkupdates" ]] ||
    fail "zero-update path did not begin with unprivileged discovery"
grep -Fq -- "System is up to date" "${zero_output}" ||
    fail "zero-update path did not finish as a no-op"
if grep -Eq -- '^(sudo|pkexec) |paccache|pacman -Syu|yay -Syu|fwupdmgr update' "${calls_file}"; then
    fail "zero-update path requested authorization or attempted a transaction"
fi

# Declining the single top-level confirmation must not request authorization.
: > "${calls_file}"
cancel_output="${tmpdir}/cancel.out"
TEST_OFFICIAL_OUTPUT="linux 6.11 -> 6.12" \
    run_fixture "$((20 * 1024 * 1024 * 1024))" "${cancel_output}" 0 n
grep -Fq -- "Update cancelled" "${cancel_output}" ||
    fail "declined update did not cancel"
if grep -Eq -- '^(sudo|pkexec) ' "${calls_file}"; then
    fail "declined update requested authorization"
fi

# Cache pruning is opportunistic. After the one approval and authentication, a
# prune failure stays visible but may not block a transaction with enough room.
: > "${calls_file}"
prune_failure_output="${tmpdir}/prune-failure.out"
TEST_OFFICIAL_OUTPUT="linux 6.11 -> 6.12" \
    run_fixture \
        "$((20 * 1024 * 1024 * 1024))" \
        "${prune_failure_output}" \
        1 \
        y
assert_single_interactive_sudo
require_exact_call "sudo -n paccache -rk3"
grep -Fq -- "Could not prune the package cache" "${prune_failure_output}" ||
    fail "package-cache failure was not reported"
grep -Fq -- "System update complete" "${prune_failure_output}" ||
    fail "package-cache failure incorrectly blocked a safe update"

# Pruning may recover space, but the update must stop before the transaction
# when the root filesystem remains below the 10 GiB safety floor. Discovery and
# the one approved authentication have already completed at this point.
: > "${calls_file}"
low_output="${tmpdir}/low-space.out"
if TEST_OFFICIAL_OUTPUT="linux 6.11 -> 6.12" \
    run_fixture "$((10 * 1024 * 1024 * 1024 - 1))" "${low_output}" 0 y; then
    fail "low-space preflight unexpectedly succeeded"
fi
assert_single_interactive_sudo
require_exact_call "sudo -n paccache -rk3"
require_exact_call "df --output=avail --block-size=1 /"
if grep -Eq -- '^yay -Syu|pacman -Syu|fwupdmgr update' "${calls_file}"; then
    fail "low-space path continued into a transaction"
fi
grep -Fq -- "At least 10 GiB must be free on /" "${low_output}" ||
    fail "low-space path did not explain the safety floor"

# Exercise the complete package, firmware, orphan, and cache path. Yay models
# its internal privileged Pacman callback using the configured sudo command and
# flags, proving that only the initial sudo validation may prompt.
: > "${calls_file}"
full_output="${tmpdir}/full-update.out"
TEST_OFFICIAL_OUTPUT="linux 6.11 -> 6.12" \
TEST_AUR_OUTPUT="roam 1.0-1 -> 1.1-1" \
TEST_FIRMWARE_OUTPUT="  ├─ Test firmware" \
TEST_ORPHANS="old-library" \
    run_fixture "$((20 * 1024 * 1024 * 1024))" "${full_output}" 0 y

assert_single_interactive_sudo
require_exact_call "sudo -n paccache -rk3"
require_exact_call "yay -Syu --combinedupgrade --batchinstall --noconfirm --answerclean None --answerdiff None --answerupgrade None --noremovemake --sudo sudo --sudoflags=-n --sudoloop"
require_exact_call "sudo -n pacman -U --noconfirm /tmp/mock-aur-package.pkg.tar.zst"
require_exact_call "sudo -n fwupdmgr update --assume-yes"
require_exact_call "sudo -n pacman -Rns --noconfirm old-library"
require_exact_call "yay -Sc --aur --noconfirm"
grep -Fq -- "System update complete" "${full_output}" ||
    fail "fixture full update did not complete"
[[ $(grep -Ec -- '^[[:space:]]*read ' "${update_script}") -eq 1 ]] ||
    fail "updater does not contain exactly one top-level confirmation read"
if grep -Eq -- 'pkexec|yay -Sua|sudo pacman|sudo fwupdmgr' "${calls_file}"; then
    fail "full update used a second privilege mechanism or interactive privileged call"
fi
[[ $(grep -Ec -- '^yay -Syu ' "${calls_file}") -eq 1 ]] ||
    fail "official and AUR updates were not combined into one Yay transaction"

mapfile -t full_calls < "${calls_file}"
package_update_index=-1
aur_cleanup_index=-1
for index in "${!full_calls[@]}"; do
    case "${full_calls[index]}" in
        "yay -Syu "*) package_update_index="${index}" ;;
        "yay -Sc --aur --noconfirm") aur_cleanup_index="${index}" ;;
    esac
done
((package_update_index >= 0 && aur_cleanup_index > package_update_index)) ||
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
