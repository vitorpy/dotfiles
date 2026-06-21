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
queue_root="${tmpdir}/queue-root"
mkdir -p "${downloads}" "${series}" "${films}" "${queue_root}"

run_sorter() {
  python3 "${sorter}" \
    --source-root "${downloads}" \
    --series-root "${series}" \
    --films-root "${films}" \
    --queue-root "${queue_root}" \
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

write_jsonrpc_metadata() {
  local path="$1"
  local name="$2"
  local hash="$3"
  cat > "${path}" <<JSON
{
  "id": 3,
  "jsonrpc": "2.0",
  "result": {
    "torrents": [
      {
        "id": 99,
        "hash_string": "${hash}",
        "download_dir": "${downloads}",
        "labels": [],
        "name": "${name}",
        "total_size": 1
      }
    ]
  }
}
JSON
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
write_metadata "${tmpdir}/movie.json" "EwoksPack" '[]' \
  "EwoksPack/Ewoks.mkv" \
  "EwoksPack/Ewoks.srt" \
  "EwoksPack/tracker.txt"
run_sorter --metadata-json "${tmpdir}/movie.json" --label "film:Ewoks The Battle for Endor"
assert_samefile "${downloads}/EwoksPack/Ewoks.mkv" "${films}/Ewoks The Battle for Endor/Ewoks.mkv"
assert_samefile "${downloads}/EwoksPack/Ewoks.srt" "${films}/Ewoks The Battle for Endor/Ewoks.srt"
assert_not_exists "${films}/Ewoks The Battle for Endor/tracker.txt"

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
write_metadata "${tmpdir}/show.json" "South.Park.S01E01" '[]' \
  "South.Park.S01E01/South.Park.S01E01.mkv" \
  "South.Park.S01E01/South.Park.S01E01.srt" \
  "South.Park.S01E01/South.Park.S01E01.nfo"
run_sorter --metadata-json "${tmpdir}/show.json" --label "series:South Park" > "${tmpdir}/optional-sidecar.out" 2>&1
grep -q "hardlink failed" "${tmpdir}/optional-sidecar.out"
assert_samefile "${downloads}/South.Park.S01E01/South.Park.S01E01.mkv" "${series}/South Park/Season 01/South.Park.S01E01.mkv"
assert_samefile "${downloads}/South.Park.S01E01/South.Park.S01E01.srt" "${series}/South Park/Season 01/South.Park.S01E01.srt"
run_sorter --metadata-json "${tmpdir}/show.json" --label "series:South Park"

mkdir -p "${downloads}/NoLabel.S01E01"
printf episode > "${downloads}/NoLabel.S01E01/NoLabel.S01E01.mkv"
write_jsonrpc_metadata "${tmpdir}/queued.json" "NoLabel.S01E01" "abc123"
run_sorter --metadata-json "${tmpdir}/queued.json"
test -f "${queue_root}/queue/btih_abc123.json"
run_sorter --metadata-json "${tmpdir}/queued.json"
[[ "$(find "${queue_root}/queue" -name 'btih_abc123.json' | wc -l)" -eq 1 ]]

mkdir -p "${downloads}/Perfect.Blue.1997.JAPANESE.REMASTERED.1080p.BluRay.x265-GalaxyRG265[TGx]"
printf perfect > "${downloads}/Perfect.Blue.1997.JAPANESE.REMASTERED.1080p.BluRay.x265-GalaxyRG265[TGx]/Perfect.Blue.1997.JAPANESE.REMASTERED.1080p.BluRay.x265-GalaxyRG265.mkv"
write_jsonrpc_metadata "${tmpdir}/perfect.json" "Perfect.Blue.1997.JAPANESE.REMASTERED.1080p.BluRay.x265-GalaxyRG265[TGx]" "perfecthash"

mkdir -p "${downloads}/Patriot Season 2 Complete 720p WEBRip x264 [i_c]"
printf patriot > "${downloads}/Patriot Season 2 Complete 720p WEBRip x264 [i_c]/Patriot S02E01 American Dimes.mkv"
write_jsonrpc_metadata "${tmpdir}/patriot.json" "Patriot Season 2 Complete 720p WEBRip x264 [i_c]" "patriothash"

cat > "${tmpdir}/tmdb-fixture.json" <<JSON
{
  "movie": {
    "Perfect Blue": {
      "results": [
        {"id": 10494, "title": "Perfect Blue", "release_date": "1997-07-25"}
      ]
    },
    "Ambiguous": {
      "results": [
        {"id": 1, "title": "Something Else", "release_date": "2020-01-01"},
        {"id": 2, "title": "Another Thing", "release_date": "2020-01-01"}
      ]
    }
  },
  "tv": {
    "Patriot": {
      "results": [
        {"id": 64396, "name": "Patriot", "first_air_date": "2015-11-05"}
      ]
    }
  }
}
JSON

run_sorter --metadata-json "${tmpdir}/perfect.json"
run_sorter --metadata-json "${tmpdir}/patriot.json"
run_sorter --process-queue --tmdb-fixture-json "${tmpdir}/tmdb-fixture.json"
assert_samefile "${downloads}/Perfect.Blue.1997.JAPANESE.REMASTERED.1080p.BluRay.x265-GalaxyRG265[TGx]/Perfect.Blue.1997.JAPANESE.REMASTERED.1080p.BluRay.x265-GalaxyRG265.mkv" "${films}/Perfect Blue/Perfect.Blue.1997.JAPANESE.REMASTERED.1080p.BluRay.x265-GalaxyRG265.mkv"
assert_samefile "${downloads}/Patriot Season 2 Complete 720p WEBRip x264 [i_c]/Patriot S02E01 American Dimes.mkv" "${series}/Patriot/Season 02/Patriot S02E01 American Dimes.mkv"
test -f "${queue_root}/done/btih_perfecthash.json"
test -f "${queue_root}/done/btih_patriothash.json"

mkdir -p "${downloads}/Ambiguous.2020.1080p.WEBRip"
printf ambiguous > "${downloads}/Ambiguous.2020.1080p.WEBRip/Ambiguous.2020.1080p.WEBRip.mkv"
write_jsonrpc_metadata "${tmpdir}/ambiguous.json" "Ambiguous.2020.1080p.WEBRip" "ambiguoushash"
run_sorter --metadata-json "${tmpdir}/ambiguous.json"
run_sorter --process-queue --tmdb-fixture-json "${tmpdir}/tmdb-fixture.json"
test -f "${queue_root}/needs-review/btih_ambiguoushash.json"
assert_not_exists "${films}/Ambiguous"

mkdir -p "${downloads}/Needs.Token.2020.1080p.WEBRip"
printf needstoken > "${downloads}/Needs.Token.2020.1080p.WEBRip/Needs.Token.2020.1080p.WEBRip.mkv"
write_jsonrpc_metadata "${tmpdir}/needs-token.json" "Needs.Token.2020.1080p.WEBRip" "needstokenhash"
run_sorter --metadata-json "${tmpdir}/needs-token.json"
set +e
TMDB_API_TOKEN= run_sorter --process-queue > "${tmpdir}/missing-token.out" 2>&1
missing_token_rc=$?
set -e
[[ "${missing_token_rc}" -eq 1 ]]
grep -q "TMDB_API_TOKEN is not set" "${tmpdir}/missing-token.out"
test -f "${queue_root}/failed/btih_needstokenhash.json"

mkdir -p "${downloads}/Conflict.S01E01" "${series}/Conflict Show/Season 01"
printf source > "${downloads}/Conflict.S01E01/Conflict.S01E01.mkv"
printf different > "${series}/Conflict Show/Season 01/Conflict.S01E01.mkv"
write_metadata "${tmpdir}/conflict.json" "Conflict.S01E01" '[]' "Conflict.S01E01/Conflict.S01E01.mkv"
run_sorter --metadata-json "${tmpdir}/conflict.json" --label "series:Conflict Show" > "${tmpdir}/conflict.out" 2>&1
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
