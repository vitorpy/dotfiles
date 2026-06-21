#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
sorter="${repo_root}/roles/services/files/media-sort-transmission"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

downloads="${tmpdir}/downloads"
series="${tmpdir}/series"
films="${tmpdir}/films"
mkdir -p "${downloads}" "${series}" "${films}"

run_sorter() {
  python3 "${sorter}" \
    --source-root "${downloads}" \
    --series-root "${series}" \
    --films-root "${films}" \
    "$@"
}

write_metadata() {
  local path="$1"
  local name="$2"
  local labels_json="$3"
  shift 3

  {
    printf '{"arguments":{"torrents":[{"name":%s,"downloadDir":%s,"labels":%s,"files":[' \
      "$(printf '%s' "${name}" | jq -Rs .)" \
      "$(printf '%s' "${downloads}" | jq -Rs .)" \
      "${labels_json}"
    local first=1
    for relpath in "$@"; do
      if [[ "${first}" -eq 0 ]]; then
        printf ','
      fi
      first=0
      printf '{"name":%s}' "$(printf '%s' "${relpath}" | jq -Rs .)"
    done
    printf '] }]}}'
  } > "${path}"
}

assert_samefile() {
  local left="$1"
  local right="$2"
  [[ -e "${left}" ]] || { echo "missing ${left}" >&2; exit 1; }
  [[ -e "${right}" ]] || { echo "missing ${right}" >&2; exit 1; }
  [[ "$(stat -c '%d:%i' "${left}")" == "$(stat -c '%d:%i' "${right}")" ]] || {
    echo "not same inode: ${left} ${right}" >&2
    exit 1
  }
}

assert_not_exists() {
  local path="$1"
  [[ ! -e "${path}" ]] || { echo "unexpected path exists: ${path}" >&2; exit 1; }
}

mkdir -p "${downloads}/EwoksPack"
printf movie > "${downloads}/EwoksPack/Ewoks.mkv"
printf subs > "${downloads}/EwoksPack/Ewoks.srt"
printf tracker > "${downloads}/EwoksPack/tracker.txt"
write_metadata "${tmpdir}/movie.json" "EwoksPack" '["film:Ewoks The Battle for Endor"]' \
  "EwoksPack/Ewoks.mkv" \
  "EwoksPack/Ewoks.srt" \
  "EwoksPack/tracker.txt"
run_sorter --metadata-json "${tmpdir}/movie.json"
assert_samefile "${downloads}/EwoksPack/Ewoks.mkv" "${films}/Ewoks The Battle for Endor/Ewoks.mkv"
assert_samefile "${downloads}/EwoksPack/Ewoks.srt" "${films}/Ewoks The Battle for Endor/Ewoks.srt"
assert_not_exists "${films}/Ewoks The Battle for Endor/tracker.txt"

write_metadata "${tmpdir}/manual-label-movie.json" "EwoksPack" '[]' \
  "EwoksPack/Ewoks.mkv"
run_sorter --metadata-json "${tmpdir}/manual-label-movie.json" --label "film:Ewoks Manual"
assert_samefile "${downloads}/EwoksPack/Ewoks.mkv" "${films}/Ewoks Manual/Ewoks.mkv"

cat > "${tmpdir}/json-rpc-movie.json" <<JSON
{
  "id": 3,
  "jsonrpc": "2.0",
  "result": {
    "torrents": [
      {
        "download_dir": "${downloads}",
        "labels": [],
        "name": "EwoksPack"
      }
    ]
  }
}
JSON
run_sorter --metadata-json "${tmpdir}/json-rpc-movie.json" --label "film:Ewoks Jsonrpc"
assert_samefile "${downloads}/EwoksPack/Ewoks.mkv" "${films}/Ewoks Jsonrpc/Ewoks.mkv"

mkdir -p "${downloads}/South.Park.S01E01"
printf episode > "${downloads}/South.Park.S01E01/South.Park.S01E01.mkv"
printf subs > "${downloads}/South.Park.S01E01/South.Park.S01E01.srt"
mkdir "${downloads}/South.Park.S01E01/South.Park.S01E01.nfo"
write_metadata "${tmpdir}/show.json" "South.Park.S01E01" '["series:South Park"]' \
  "South.Park.S01E01/South.Park.S01E01.mkv" \
  "South.Park.S01E01/South.Park.S01E01.srt" \
  "South.Park.S01E01/South.Park.S01E01.nfo"
run_sorter --metadata-json "${tmpdir}/show.json" > "${tmpdir}/optional-sidecar.out" 2>&1
grep -q "hardlink failed" "${tmpdir}/optional-sidecar.out"
assert_samefile "${downloads}/South.Park.S01E01/South.Park.S01E01.mkv" "${series}/South Park/Season 01/South.Park.S01E01.mkv"
assert_samefile "${downloads}/South.Park.S01E01/South.Park.S01E01.srt" "${series}/South Park/Season 01/South.Park.S01E01.srt"
run_sorter --metadata-json "${tmpdir}/show.json"

mkdir -p "${downloads}/RickPack"
printf s1 > "${downloads}/RickPack/Rick.and.Morty.S01E01.mkv"
printf s2 > "${downloads}/RickPack/Rick.and.Morty.S02E01.mkv"
write_metadata "${tmpdir}/multi-season.json" "RickPack" '["series:Rick and Morty"]' \
  "RickPack/Rick.and.Morty.S01E01.mkv" \
  "RickPack/Rick.and.Morty.S02E01.mkv"
run_sorter --metadata-json "${tmpdir}/multi-season.json"
assert_samefile "${downloads}/RickPack/Rick.and.Morty.S01E01.mkv" "${series}/Rick and Morty/Season 01/Rick.and.Morty.S01E01.mkv"
assert_samefile "${downloads}/RickPack/Rick.and.Morty.S02E01.mkv" "${series}/Rick and Morty/Season 02/Rick.and.Morty.S02E01.mkv"

mkdir -p "${downloads}/NoLabel.S01E01"
printf episode > "${downloads}/NoLabel.S01E01/NoLabel.S01E01.mkv"
write_metadata "${tmpdir}/missing-label.json" "NoLabel.S01E01" '[]' "NoLabel.S01E01/NoLabel.S01E01.mkv"
run_sorter --metadata-json "${tmpdir}/missing-label.json" > "${tmpdir}/missing-label.out" 2>&1
grep -q "needs label" "${tmpdir}/missing-label.out"
assert_not_exists "${series}/NoLabel"

mkdir -p "${downloads}/Conflict.S01E01" "${series}/Conflict Show/Season 01"
printf source > "${downloads}/Conflict.S01E01/Conflict.S01E01.mkv"
printf different > "${series}/Conflict Show/Season 01/Conflict.S01E01.mkv"
write_metadata "${tmpdir}/conflict.json" "Conflict.S01E01" '["series:Conflict Show"]' "Conflict.S01E01/Conflict.S01E01.mkv"
run_sorter --metadata-json "${tmpdir}/conflict.json" > "${tmpdir}/conflict.out" 2>&1
grep -q "destination conflict" "${tmpdir}/conflict.out"
[[ "$(cat "${series}/Conflict Show/Season 01/Conflict.S01E01.mkv")" == "different" ]]

mkdir -p "${downloads}/Corporate.S01"
printf corporate > "${downloads}/Corporate.S01/Corporate.S01E01.mkv"
run_sorter --backfill-current-downloads --dry-run > "${tmpdir}/backfill-dry-run.out" 2>&1
grep -q "would hardlink" "${tmpdir}/backfill-dry-run.out"
assert_not_exists "${series}/Corporate/Season 01/Corporate.S01E01.mkv"
run_sorter --backfill-current-downloads --apply
assert_samefile "${downloads}/Corporate.S01/Corporate.S01E01.mkv" "${series}/Corporate/Season 01/Corporate.S01E01.mkv"

echo "media sorter tests passed"
