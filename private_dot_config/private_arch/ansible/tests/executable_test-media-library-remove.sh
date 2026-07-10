#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
remover="${repo_root}/roles/services/files/media-library-remove"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

downloads="${tmpdir}/downloads"
series="${tmpdir}/series"
films="${tmpdir}/films"
music="${tmpdir}/music"
queue_root="${tmpdir}/queue-root"
mkdir -p "${downloads}" "${series}" "${films}" "${music}" "${queue_root}"

run_remover() {
  python3 "${remover}" \
    --download-root "${downloads}" \
    --series-root "${series}" \
    --films-root "${films}" \
    --music-root "${music}" \
    --queue-root "${queue_root}" \
    --no-sonarr \
    --no-radarr \
    --no-transmission \
    --no-jellyfin \
    "$@"
}

assert_exists() {
  local path="$1"
  [[ -e "${path}" ]] || { echo "missing expected path: ${path}" >&2; exit 1; }
}

assert_not_exists() {
  local path="$1"
  [[ ! -e "${path}" ]] || { echo "unexpected path exists: ${path}" >&2; exit 1; }
}

mkdir -p "${downloads}/Example.Show.S01" "${series}/Example Show/Season 01"
printf episode > "${downloads}/Example.Show.S01/Example.Show.S01E01.mkv"
printf subtitle > "${downloads}/Example.Show.S01/Example.Show.S01E01.srt"
ln "${downloads}/Example.Show.S01/Example.Show.S01E01.mkv" "${series}/Example Show/Season 01/Example.Show.S01E01.mkv"
ln "${downloads}/Example.Show.S01/Example.Show.S01E01.srt" "${series}/Example Show/Season 01/Example.Show.S01E01.srt"

run_remover --path "${series}/Example Show" > "${tmpdir}/dry-run.out"
grep -q "mode: DRY-RUN" "${tmpdir}/dry-run.out"
grep -q "hardlink-peer" "${tmpdir}/dry-run.out"
assert_exists "${downloads}/Example.Show.S01/Example.Show.S01E01.mkv"
assert_exists "${series}/Example Show/Season 01/Example.Show.S01E01.mkv"

run_remover --path "${series}/Example Show" --apply > "${tmpdir}/apply.out"
grep -q "mode: APPLY" "${tmpdir}/apply.out"
assert_not_exists "${series}/Example Show"
assert_not_exists "${downloads}/Example.Show.S01"

if run_remover --path "${series}" > "${tmpdir}/root-guard.out" 2>&1; then
  echo "expected media root deletion to fail" >&2
  exit 1
fi
grep -q "refusing unmanaged or root path" "${tmpdir}/root-guard.out"
