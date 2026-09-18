#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="${script_dir}/../scripts/update-timezone.sh"
test_root="$(mktemp -d /tmp/auto-timezone-test.XXXXXX)"
trap 'rm -rf -- "${test_root}"' EXIT

mkdir -p "${test_root}/home/.cache/quickshell-berg" \
    "${test_root}/home/.local/share" "${test_root}/bin"

cat > "${test_root}/bin/timedatectl" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "show" ]]; then
    printf '%s\n' 'Europe/Istanbul'
    exit 0
fi
printf 'unexpected timedatectl call: %s\n' "$*" >&2
exit 1
EOF

cat > "${test_root}/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'network lookup must not run when Berg cache is fresh' >&2
exit 99
EOF
chmod 0755 "${test_root}/bin/timedatectl" "${test_root}/bin/curl"

jq -n --argjson updated_at "$(date +%s)" '{
    updated_at: $updated_at,
    timezone: "Europe/Istanbul"
}' > "${test_root}/home/.cache/quickshell-berg/location.json"

HOME="${test_root}/home" \
PATH="${test_root}/bin:/usr/bin" \
BERG_LOCATION_CACHE="${test_root}/home/.cache/quickshell-berg/location.json" \
    bash "${script}"

grep -Fq 'Using Berg location cache timezone Europe/Istanbul' \
    "${test_root}/home/.local/share/auto-timezone.log"
grep -Fqx 'Europe/Istanbul' "${test_root}/home/.cache/detected-timezone"

printf '%s\n' 'Auto-timezone Berg cache test passed'
