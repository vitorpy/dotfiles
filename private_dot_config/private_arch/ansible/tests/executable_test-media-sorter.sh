#!/usr/bin/env bash
set -euo pipefail

export PYTHONDONTWRITEBYTECODE=1

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
sorter="${repo_root}/roles/services/files/media-sort-transmission"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

downloads="${tmpdir}/downloads"
series="${tmpdir}/series"
films="${tmpdir}/films"
music="${tmpdir}/music"
books="${tmpdir}/books"
queue_root="${tmpdir}/queue-root"
mkdir -p "${downloads}" "${series}" "${films}" "${music}" "${books}" "${queue_root}"

run_sorter() {
  python3 "${sorter}" \
    --source-root "${downloads}" \
    --series-root "${series}" \
    --films-root "${films}" \
    --music-root "${music}" \
    --books-root "${books}" \
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
grep -qx '\*' "${downloads}/EwoksPack/.ignore"

mkdir -p "${downloads}/NasuExtras"
printf main-feature-video > "${downloads}/NasuExtras/Nasu Summer in Andalusia.mkv"
printf trailer > "${downloads}/NasuExtras/Nasu Trailer.avi"
printf trailersubs > "${downloads}/NasuExtras/Nasu Trailer.srt"
printf music > "${downloads}/NasuExtras/Nasu Bike Show Song Music Video.mp4"
write_metadata "${tmpdir}/movie-extras.json" "NasuExtras" '[]' \
  "NasuExtras/Nasu Summer in Andalusia.mkv" \
  "NasuExtras/Nasu Trailer.avi" \
  "NasuExtras/Nasu Trailer.srt" \
  "NasuExtras/Nasu Bike Show Song Music Video.mp4"
run_sorter --metadata-json "${tmpdir}/movie-extras.json" --label "film:Nasu Summer in Andalusia"
assert_samefile "${downloads}/NasuExtras/Nasu Summer in Andalusia.mkv" "${films}/Nasu Summer in Andalusia/Nasu Summer in Andalusia.mkv"
assert_samefile "${downloads}/NasuExtras/Nasu Trailer.avi" "${films}/Nasu Summer in Andalusia/trailers/Nasu Trailer.avi"
assert_samefile "${downloads}/NasuExtras/Nasu Trailer.srt" "${films}/Nasu Summer in Andalusia/trailers/Nasu Trailer.srt"
assert_samefile "${downloads}/NasuExtras/Nasu Bike Show Song Music Video.mp4" "${films}/Nasu Summer in Andalusia/extras/Nasu Bike Show Song Music Video.mp4"
assert_not_exists "${films}/Nasu Summer in Andalusia/Nasu Trailer.avi"
assert_not_exists "${films}/Nasu Summer in Andalusia/Nasu Bike Show Song Music Video.mp4"

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

mkdir -p "${downloads}/SelectedAmbient"
printf audio > "${downloads}/SelectedAmbient/01 - Xtal.flac"
write_metadata "${tmpdir}/music-label.json" "SelectedAmbient" '[]' \
  "SelectedAmbient/01 - Xtal.flac"
run_sorter --metadata-json "${tmpdir}/music-label.json" --label "music:Aphex Twin - Selected Ambient Works 85-92"
assert_samefile "${downloads}/SelectedAmbient/01 - Xtal.flac" "${music}/Aphex Twin/Selected Ambient Works 85-92/01 - Xtal.flac"

mkdir -p "${downloads}/Frank Sinatra - Love Songs My Way - 2-CD-[MP3-320]-[[TFM]/Disc 1"
mkdir -p "${downloads}/Frank Sinatra - Love Songs My Way - 2-CD-[MP3-320]-[[TFM]/Artwork"
printf audio > "${downloads}/Frank Sinatra - Love Songs My Way - 2-CD-[MP3-320]-[[TFM]/Disc 1/01 - Fly Me To The Moon.mp3"
printf cover > "${downloads}/Frank Sinatra - Love Songs My Way - 2-CD-[MP3-320]-[[TFM]/Artwork/Front.jpg"
printf tracker > "${downloads}/Frank Sinatra - Love Songs My Way - 2-CD-[MP3-320]-[[TFM]/tracker.txt"
write_jsonrpc_metadata "${tmpdir}/music-auto.json" "Frank Sinatra - Love Songs My Way - 2-CD-[MP3-320]-[[TFM]" "musichash"
run_sorter --metadata-json "${tmpdir}/music-auto.json"
TMDB_API_TOKEN= run_sorter --process-queue
assert_samefile "${downloads}/Frank Sinatra - Love Songs My Way - 2-CD-[MP3-320]-[[TFM]/Disc 1/01 - Fly Me To The Moon.mp3" "${music}/Frank Sinatra/Love Songs My Way/Disc 1/01 - Fly Me To The Moon.mp3"
assert_samefile "${downloads}/Frank Sinatra - Love Songs My Way - 2-CD-[MP3-320]-[[TFM]/Artwork/Front.jpg" "${music}/Frank Sinatra/Love Songs My Way/Artwork/Front.jpg"
assert_not_exists "${music}/Frank Sinatra/Love Songs My Way/tracker.txt"
test -f "${queue_root}/done/btih_musichash.json"
jq -e '.match.provider == "filename" and .match.artist == "Frank Sinatra" and .match.album == "Love Songs My Way"' "${queue_root}/done/btih_musichash.json" >/dev/null

mkdir -p "${downloads}/3l1s R3g1n4 3 T0m J0b1m- 3l1s 3 T0m"
printf audio > "${downloads}/3l1s R3g1n4 3 T0m J0b1m- 3l1s 3 T0m/01 - Aguas De Marco.mp3"
printf lyrics > "${downloads}/3l1s R3g1n4 3 T0m J0b1m- 3l1s 3 T0m/01 - Aguas De Marco.lrc"
write_jsonrpc_metadata "${tmpdir}/music-obfuscated.json" "3l1s R3g1n4 3 T0m J0b1m- 3l1s 3 T0m" "obfuscatedmusichash"
cat > "${tmpdir}/audiodb-fixture.json" <<JSON
{
  "album": {}
}
JSON
cat > "${tmpdir}/acoustid-fixture.json" <<JSON
{
  "fingerprints": {
    "elis-track-1": {
      "status": "ok",
      "results": [
        {
          "score": 0.98,
          "recordings": [
            {
              "title": "Aguas de Marco",
              "artists": [{"name": "Elis Regina"}],
              "releasegroups": [{"id": "rg-elis-tom", "title": "Elis & Tom", "type": "Album"}]
            }
          ]
        }
      ]
    }
  }
}
JSON
cat > "${tmpdir}/fpcalc" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"Aguas De Marco"*) printf '{"duration": 180, "fingerprint": "elis-track-1"}\n' ;;
  *) printf '{"duration": 180, "fingerprint": "unknown-track"}\n' ;;
esac
SH
chmod +x "${tmpdir}/fpcalc"
run_sorter --metadata-json "${tmpdir}/music-obfuscated.json"
TMDB_API_TOKEN= run_sorter --process-queue --audiodb-fixture-json "${tmpdir}/audiodb-fixture.json" --acoustid-fixture-json "${tmpdir}/acoustid-fixture.json" --fpcalc-path "${tmpdir}/fpcalc"
test -f "${queue_root}/done/btih_obfuscatedmusichash.json"
assert_samefile "${downloads}/3l1s R3g1n4 3 T0m J0b1m- 3l1s 3 T0m/01 - Aguas De Marco.mp3" "${music}/Elis Regina/Elis & Tom/01 - Aguas De Marco.mp3"
assert_samefile "${downloads}/3l1s R3g1n4 3 T0m J0b1m- 3l1s 3 T0m/01 - Aguas De Marco.lrc" "${music}/Elis Regina/Elis & Tom/01 - Aguas De Marco.lrc"
jq -e '.match.provider == "acoustid" and .match.selected.artist == "Elis Regina" and .match.selected.title == "Elis & Tom"' "${queue_root}/done/btih_obfuscatedmusichash.json" >/dev/null

mkdir -p "${downloads}/LooseTracks"
printf audio > "${downloads}/LooseTracks/track01.flac"
write_jsonrpc_metadata "${tmpdir}/music-unparsed.json" "LooseTracks" "unparsedmusichash"
run_sorter --metadata-json "${tmpdir}/music-unparsed.json"
TMDB_API_TOKEN= run_sorter --process-queue --audiodb-fixture-json "${tmpdir}/audiodb-fixture.json" --acoustid-fixture-json "${tmpdir}/acoustid-fixture.json" --fpcalc-path "${tmpdir}/fpcalc"
test -f "${queue_root}/needs-review/btih_unparsedmusichash.json"
run_sorter --queue > "${tmpdir}/music-queue-review.out"
grep -q "no AcoustID album candidates" "${tmpdir}/music-queue-review.out"
grep -q "\\[audio\\] LooseTracks/track01.flac" "${tmpdir}/music-queue-review.out"

mkdir -p "${downloads}/Artist Pack/Live/(1972) Album One" "${downloads}/Artist Pack/Studio/(1973) Album Two"
printf audio > "${downloads}/Artist Pack/Live/(1972) Album One/01 - One.mp3"
printf audio > "${downloads}/Artist Pack/Studio/(1973) Album Two/01 - Two.mp3"
write_jsonrpc_metadata "${tmpdir}/music-pack.json" "Artist Pack" "musicpackhash"
run_sorter --metadata-json "${tmpdir}/music-pack.json"
TMDB_API_TOKEN= run_sorter --process-queue --audiodb-fixture-json "${tmpdir}/audiodb-fixture.json" --acoustid-fixture-json "${tmpdir}/acoustid-fixture.json" --fpcalc-path "${tmpdir}/fpcalc"
test -f "${queue_root}/needs-review/btih_musicpackhash.json"
assert_not_exists "${music}/Elis Regina/Elis & Tom/Live"
run_sorter --queue > "${tmpdir}/music-pack-queue-review.out"
grep -q "multi-album music pack needs explicit review" "${tmpdir}/music-pack-queue-review.out"
grep -q "\\[audio\\] Artist Pack/Live/(1972) Album One/01 - One.mp3" "${tmpdir}/music-pack-queue-review.out"

mkdir -p "${downloads}/Comic Pack"
printf comic > "${downloads}/Comic Pack/Chainsaw Man Vol 01.cbz"
printf ebook > "${downloads}/Comic Pack/Chainsaw Man Vol 01.epub"
printf cover > "${downloads}/Comic Pack/cover.jpg"
printf tracker > "${downloads}/Comic Pack/tracker.txt"
write_metadata "${tmpdir}/book-label.json" "Comic Pack" '[]' \
  "Comic Pack/Chainsaw Man Vol 01.cbz" \
  "Comic Pack/Chainsaw Man Vol 01.epub" \
  "Comic Pack/cover.jpg" \
  "Comic Pack/tracker.txt"
run_sorter --metadata-json "${tmpdir}/book-label.json" --label "comic:Chainsaw Man"
assert_samefile "${downloads}/Comic Pack/Chainsaw Man Vol 01.cbz" "${books}/Comics/Chainsaw Man/Chainsaw Man Vol 01.cbz"
assert_samefile "${downloads}/Comic Pack/Chainsaw Man Vol 01.epub" "${books}/Comics/Chainsaw Man/Chainsaw Man Vol 01.epub"
assert_samefile "${downloads}/Comic Pack/cover.jpg" "${books}/Comics/Chainsaw Man/cover.jpg"
assert_not_exists "${books}/Comics/Chainsaw Man/tracker.txt"
grep -qx '\*' "${downloads}/Comic Pack/.ignore"

mkdir -p "${downloads}/Palomar"
printf comic > "${downloads}/Palomar/Palomar.cbz"
write_jsonrpc_metadata "${tmpdir}/book-auto.json" "Palomar" "bookhash"
run_sorter --metadata-json "${tmpdir}/book-auto.json"
TMDB_API_TOKEN= run_sorter --process-queue
assert_samefile "${downloads}/Palomar/Palomar.cbz" "${books}/Comics/Palomar/Palomar.cbz"
test -f "${queue_root}/done/btih_bookhash.json"
jq -e '.match.provider == "filename" and .plan.label_kind == "book" and .plan.label_title == "Palomar"' "${queue_root}/done/btih_bookhash.json" >/dev/null
jq -e '.plan.operations[0].dest | contains("/Comics/Palomar/Palomar.cbz")' "${queue_root}/done/btih_bookhash.json" >/dev/null

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

mkdir -p "${downloads}/Stargate Atlantis (2004) Season 1-5 S01-05"
printf atlantis1 > "${downloads}/Stargate Atlantis (2004) Season 1-5 S01-05/Stargate Atlantis - S01E01 - Rising.mkv"
printf atlantis2 > "${downloads}/Stargate Atlantis (2004) Season 1-5 S01-05/Stargate Atlantis - S02E01 - The Siege.mkv"
write_metadata "${tmpdir}/multi-season-parent-range.json" "Stargate Atlantis (2004) Season 1-5 S01-05" '[]' \
  "Stargate Atlantis (2004) Season 1-5 S01-05/Stargate Atlantis - S01E01 - Rising.mkv" \
  "Stargate Atlantis (2004) Season 1-5 S01-05/Stargate Atlantis - S02E01 - The Siege.mkv"
run_sorter --metadata-json "${tmpdir}/multi-season-parent-range.json" --label "series:Stargate Atlantis"
assert_samefile "${downloads}/Stargate Atlantis (2004) Season 1-5 S01-05/Stargate Atlantis - S01E01 - Rising.mkv" "${series}/Stargate Atlantis/Season 01/Stargate Atlantis - S01E01 - Rising.mkv"
assert_samefile "${downloads}/Stargate Atlantis (2004) Season 1-5 S01-05/Stargate Atlantis - S02E01 - The Siege.mkv" "${series}/Stargate Atlantis/Season 02/Stargate Atlantis - S02E01 - The Siege.mkv"
assert_not_exists "${series}/Stargate Atlantis/Season 01/Stargate Atlantis - S02E01 - The Siege.mkv"

mkdir -p "${downloads}/Battlestar Galactica (2003) Season 1-4 S01-S04/Featurettes/Season 2"
mkdir -p "${downloads}/Battlestar Galactica (2003) Season 1-4 S01-S04/Specials"
printf bsgfeature > "${downloads}/Battlestar Galactica (2003) Season 1-4 S01-S04/Featurettes/Season 2/Sizzle Reel.mkv"
printf bsgspecial > "${downloads}/Battlestar Galactica (2003) Season 1-4 S01-S04/Specials/Battlestar Galactica (2003) - S00E04-E05 - Razor.mkv"
write_metadata "${tmpdir}/bsg-specials-featurettes.json" "Battlestar Galactica (2003) Season 1-4 S01-S04" '[]' \
  "Battlestar Galactica (2003) Season 1-4 S01-S04/Featurettes/Season 2/Sizzle Reel.mkv" \
  "Battlestar Galactica (2003) Season 1-4 S01-S04/Specials/Battlestar Galactica (2003) - S00E04-E05 - Razor.mkv"
run_sorter --metadata-json "${tmpdir}/bsg-specials-featurettes.json" --label "series:Battlestar Galactica"
assert_samefile "${downloads}/Battlestar Galactica (2003) Season 1-4 S01-S04/Featurettes/Season 2/Sizzle Reel.mkv" "${series}/Battlestar Galactica/Season 02/featurettes/Sizzle Reel.mkv"
assert_samefile "${downloads}/Battlestar Galactica (2003) Season 1-4 S01-S04/Specials/Battlestar Galactica (2003) - S00E04-E05 - Razor.mkv" "${series}/Battlestar Galactica/Season 00/Battlestar Galactica (2003) - S00E04-E05 - Razor.mkv"
assert_not_exists "${series}/Battlestar Galactica/Season 01/Sizzle Reel.mkv"
assert_not_exists "${series}/Battlestar Galactica/Season 01/Battlestar Galactica (2003) - S00E04-E05 - Razor.mkv"

mkdir -p "${downloads}/SGU Stargate Universe Season 1 & 2"
printf sgu1 > "${downloads}/SGU Stargate Universe Season 1 & 2/Stargate Universe Season 1 Episode 01 - Air.avi"
printf sgu2 > "${downloads}/SGU Stargate Universe Season 1 & 2/Stargate Universe Season 2 Episode 01 - Intervention.avi"
printf kino > "${downloads}/SGU Stargate Universe Season 1 & 2/Kino 01 - Get Outta Here.avi"
printf interview > "${downloads}/SGU Stargate Universe Season 1 & 2/SGU Interviews 01.avi"
write_metadata "${tmpdir}/season-word-parent-range.json" "SGU Stargate Universe Season 1 & 2" '[]' \
  "SGU Stargate Universe Season 1 & 2/Stargate Universe Season 1 Episode 01 - Air.avi" \
  "SGU Stargate Universe Season 1 & 2/Stargate Universe Season 2 Episode 01 - Intervention.avi" \
  "SGU Stargate Universe Season 1 & 2/Kino 01 - Get Outta Here.avi" \
  "SGU Stargate Universe Season 1 & 2/SGU Interviews 01.avi"
run_sorter --metadata-json "${tmpdir}/season-word-parent-range.json" --label "series:Stargate Universe"
assert_samefile "${downloads}/SGU Stargate Universe Season 1 & 2/Stargate Universe Season 1 Episode 01 - Air.avi" "${series}/Stargate Universe/Season 01/Stargate Universe Season 1 Episode 01 - Air.avi"
assert_samefile "${downloads}/SGU Stargate Universe Season 1 & 2/Stargate Universe Season 2 Episode 01 - Intervention.avi" "${series}/Stargate Universe/Season 02/Stargate Universe Season 2 Episode 01 - Intervention.avi"
assert_samefile "${downloads}/SGU Stargate Universe Season 1 & 2/Kino 01 - Get Outta Here.avi" "${series}/Stargate Universe/Season 01/shorts/Kino 01 - Get Outta Here.avi"
assert_samefile "${downloads}/SGU Stargate Universe Season 1 & 2/SGU Interviews 01.avi" "${series}/Stargate Universe/Season 01/interviews/SGU Interviews 01.avi"
assert_not_exists "${series}/Stargate Universe/Season 01/Stargate Universe Season 2 Episode 01 - Intervention.avi"
assert_not_exists "${series}/Stargate Universe/Season 01/Kino 01 - Get Outta Here.avi"
assert_not_exists "${series}/Stargate Universe/Season 01/SGU Interviews 01.avi"

mkdir -p "${downloads}/Os normais/1a Temporada" "${downloads}/Os normais/2a Temporada" "${downloads}/Os normais/3a Temporada"
printf osn1 > "${downloads}/Os normais/1a Temporada/Os.Normais.01x01.avi"
printf osn2 > "${downloads}/Os normais/2a Temporada/Os.Normais.2x01 - Tudo normal como antes.avi"
printf osn3 > "${downloads}/Os normais/3a Temporada/301 Os Normais - A Volta Dos Que Não Foram.avi"
write_metadata "${tmpdir}/os-normais.json" "Os normais" '[]' \
  "Os normais/1a Temporada/Os.Normais.01x01.avi" \
  "Os normais/2a Temporada/Os.Normais.2x01 - Tudo normal como antes.avi" \
  "Os normais/3a Temporada/301 Os Normais - A Volta Dos Que Não Foram.avi"
run_sorter --metadata-json "${tmpdir}/os-normais.json" --label "series:Os Normais"
assert_samefile "${downloads}/Os normais/1a Temporada/Os.Normais.01x01.avi" "${series}/Os Normais/Season 01/Os.Normais.S01E01.avi"
assert_samefile "${downloads}/Os normais/2a Temporada/Os.Normais.2x01 - Tudo normal como antes.avi" "${series}/Os Normais/Season 02/Os.Normais.S02E01 - Tudo normal como antes.avi"
assert_samefile "${downloads}/Os normais/3a Temporada/301 Os Normais - A Volta Dos Que Não Foram.avi" "${series}/Os Normais/Season 03/S03E01 Os Normais - A Volta Dos Que Não Foram.avi"
assert_not_exists "${series}/Os Normais/Season 01/S01E301 Os Normais - A Volta Dos Que Não Foram.avi"

mkdir -p "${downloads}/Star Trek Enterprise S01"
printf enterprise > "${downloads}/Star Trek Enterprise S01/Star Trek Enterprise S01E01E02 Broken Bow.mkv"
write_metadata "${tmpdir}/multi-episode-file.json" "Star Trek Enterprise S01" '[]' \
  "Star Trek Enterprise S01/Star Trek Enterprise S01E01E02 Broken Bow.mkv"
run_sorter --metadata-json "${tmpdir}/multi-episode-file.json" --label "series:Star Trek Enterprise"
assert_samefile "${downloads}/Star Trek Enterprise S01/Star Trek Enterprise S01E01E02 Broken Bow.mkv" "${series}/Star Trek Enterprise/Season 01/Star Trek Enterprise S01E01-E02 Broken Bow.mkv"
assert_not_exists "${series}/Star Trek Enterprise/Season 01/Star Trek Enterprise S01E01E02 Broken Bow.mkv"

mkdir -p "${downloads}/NoLabel.S01E01"
printf episode > "${downloads}/NoLabel.S01E01/NoLabel.S01E01.mkv"
write_jsonrpc_metadata "${tmpdir}/queued.json" "NoLabel.S01E01" "abc123"
run_sorter --metadata-json "${tmpdir}/queued.json"
test -f "${queue_root}/queue/btih_abc123.json"
[[ "$(stat -c '%a' "${queue_root}/queue/btih_abc123.json")" == "640" ]]
run_sorter --metadata-json "${tmpdir}/queued.json"
[[ "$(find "${queue_root}/queue" -name 'btih_abc123.json' | wc -l)" -eq 1 ]]
run_sorter --ignore "btih:abc123" --ignore-reason "not part of the Jellyfin libraries"
test -f "${queue_root}/ignored/btih_abc123.json"
jq -e '.status == "ignored" and .reason == "not part of the Jellyfin libraries"' "${queue_root}/ignored/btih_abc123.json" >/dev/null

mkdir -p "${downloads}/Magazine PDF Pack"
printf pdf > "${downloads}/Magazine PDF Pack/Issue 001.pdf"
printf cover > "${downloads}/Magazine PDF Pack/Cover.jpg"
write_jsonrpc_metadata "${tmpdir}/magazine-pack.json" "Magazine PDF Pack" "magazinepackhash"
run_sorter --metadata-json "${tmpdir}/magazine-pack.json"
TMDB_API_TOKEN= run_sorter --process-queue
test -f "${queue_root}/ignored/btih_magazinepackhash.json"
jq -e '.status == "ignored" and .reason == "no sortable video, audio, or book files"' "${queue_root}/ignored/btih_magazinepackhash.json" >/dev/null
run_sorter --queue > "${tmpdir}/ignored-queue.out"
grep -q "ignored: 2 item(s)" "${tmpdir}/ignored-queue.out"
grep -q "\\[other\\] Magazine PDF Pack/Issue 001.pdf" "${tmpdir}/ignored-queue.out"
grep -q "\\[sidecar\\] Magazine PDF Pack/Cover.jpg" "${tmpdir}/ignored-queue.out"

mkdir -p "${downloads}/Grok.Approved.2020.1080p.WEBRip"
printf grokapproved > "${downloads}/Grok.Approved.2020.1080p.WEBRip/Grok.Approved.2020.1080p.WEBRip.mkv"
write_jsonrpc_metadata "${tmpdir}/grok-approved.json" "Grok.Approved.2020.1080p.WEBRip" "grokapprovedhash"
cat > "${tmpdir}/grok-tmdb-fixture.json" <<JSON
{
  "movie": {
    "Grok Approved": {
      "results": [
        {"id": 901, "title": "Grok Approved", "release_date": "2020-01-01", "vote_count": 50}
      ]
    },
    "Grok Rejected": {
      "results": [
        {"id": 902, "title": "Grok Rejected", "release_date": "2020-01-01", "vote_count": 50}
      ]
    }
  },
  "tv": {}
}
JSON
cat > "${tmpdir}/grok-review-fixture.json" <<JSON
{
  "btih:grokapprovedhash": {
    "decision": "approve",
    "reason": "title and destination layout are coherent",
    "concerns": [],
    "confidence": 0.95
  },
  "btih:grokrejecthash": {
    "decision": "reject",
    "reason": "destination title does not look trustworthy",
    "concerns": ["suspicious title"],
    "confidence": 0.7
  }
}
JSON
run_sorter --metadata-json "${tmpdir}/grok-approved.json"
run_sorter --preflight "btih:grokapprovedhash" --tmdb-fixture-json "${tmpdir}/grok-tmdb-fixture.json" > "${tmpdir}/grok-preflight.json"
jq -e '.preflight.ok == true and (.plan.operations[0].dest | contains("Grok Approved"))' "${tmpdir}/grok-preflight.json" >/dev/null
run_sorter --process-queue --tmdb-fixture-json "${tmpdir}/grok-tmdb-fixture.json" --grok-review --xai-fixture-json "${tmpdir}/grok-review-fixture.json"
assert_samefile "${downloads}/Grok.Approved.2020.1080p.WEBRip/Grok.Approved.2020.1080p.WEBRip.mkv" "${films}/Grok Approved/Grok.Approved.2020.1080p.WEBRip.mkv"
test -f "${queue_root}/done/btih_grokapprovedhash.json"
jq -e '.grok_review.approved == true and .plan.grok_review_reason == "title and destination layout are coherent" and (.owned_links | length) == 1' "${queue_root}/done/btih_grokapprovedhash.json" >/dev/null
run_sorter --audit > "${tmpdir}/audit-clean.out"
grep -q "owned-link findings: 0" "${tmpdir}/audit-clean.out"

rm "${downloads}/Grok.Approved.2020.1080p.WEBRip/Grok.Approved.2020.1080p.WEBRip.mkv"
printf grokapproved-new > "${downloads}/Grok.Approved.2020.1080p.WEBRip/Grok.Approved.2020.1080p.WEBRip.mkv"
set +e
run_sorter --audit > "${tmpdir}/audit-stale.out"
audit_stale_rc=$?
set -e
[[ "${audit_stale_rc}" -eq 1 ]]
grep -q "stale-owned-link" "${tmpdir}/audit-stale.out"
run_sorter --reconcile > "${tmpdir}/reconcile-dry-run.out"
grep -q "stale-owned-links=1" "${tmpdir}/reconcile-dry-run.out"
[[ -e "${films}/Grok Approved/Grok.Approved.2020.1080p.WEBRip.mkv" ]]
run_sorter --reconcile --apply > "${tmpdir}/reconcile-apply.out"
assert_not_exists "${films}/Grok Approved/Grok.Approved.2020.1080p.WEBRip.mkv"
[[ -e "${downloads}/Grok.Approved.2020.1080p.WEBRip/Grok.Approved.2020.1080p.WEBRip.mkv" ]]

mkdir -p "${downloads}/Grok.Rejected.2020.1080p.WEBRip"
printf grokrejected > "${downloads}/Grok.Rejected.2020.1080p.WEBRip/Grok.Rejected.2020.1080p.WEBRip.mkv"
write_jsonrpc_metadata "${tmpdir}/grok-rejected.json" "Grok.Rejected.2020.1080p.WEBRip" "grokrejecthash"
run_sorter --metadata-json "${tmpdir}/grok-rejected.json"
run_sorter --process-queue --tmdb-fixture-json "${tmpdir}/grok-tmdb-fixture.json" --grok-review --xai-fixture-json "${tmpdir}/grok-review-fixture.json"
test -f "${queue_root}/needs-review/btih_grokrejecthash.json"
jq -e '.reason == "Grok rejected plan: destination title does not look trustworthy" and .grok_review.approved == false' "${queue_root}/needs-review/btih_grokrejecthash.json" >/dev/null
assert_not_exists "${films}/Grok Rejected/Grok.Rejected.2020.1080p.WEBRip.mkv"

mkdir -p "${downloads}/Perfect.Blue.1997.JAPANESE.REMASTERED.1080p.BluRay.x265-GalaxyRG265[TGx]"
printf perfect > "${downloads}/Perfect.Blue.1997.JAPANESE.REMASTERED.1080p.BluRay.x265-GalaxyRG265[TGx]/Perfect.Blue.1997.JAPANESE.REMASTERED.1080p.BluRay.x265-GalaxyRG265.mkv"
write_jsonrpc_metadata "${tmpdir}/perfect.json" "Perfect.Blue.1997.JAPANESE.REMASTERED.1080p.BluRay.x265-GalaxyRG265[TGx]" "perfecthash"

mkdir -p "${downloads}/Patriot Season 2 Complete 720p WEBRip x264 [i_c]"
printf patriot > "${downloads}/Patriot Season 2 Complete 720p WEBRip x264 [i_c]/Patriot S02E01 American Dimes.mkv"
write_jsonrpc_metadata "${tmpdir}/patriot.json" "Patriot Season 2 Complete 720p WEBRip x264 [i_c]" "patriothash"

mkdir -p "${downloads}/[Kanavid] Serial Experiments Lain 1-13(END) [BD][1080p][AAC][MP4]"
printf lain01 > "${downloads}/[Kanavid] Serial Experiments Lain 1-13(END) [BD][1080p][AAC][MP4]/[Kanavid] Serial Experiments Lain - 01 [BD][1080p][AAC].mp4"
printf lain02 > "${downloads}/[Kanavid] Serial Experiments Lain 1-13(END) [BD][1080p][AAC][MP4]/[Kanavid] Serial Experiments Lain - 02 [BD][1080p][AAC].mp4"
printf laincleanop > "${downloads}/[Kanavid] Serial Experiments Lain 1-13(END) [BD][1080p][AAC][MP4]/[Kanavid] Serial Experiments Lain Clean OP [BD][1080p][AAC].mp4"
printf lainop > "${downloads}/[Kanavid] Serial Experiments Lain 1-13(END) [BD][1080p][AAC][MP4]/[Kanavid] Serial Experiments Lain NCOP [BD][1080p][AAC].mp4"
printf lained > "${downloads}/[Kanavid] Serial Experiments Lain 1-13(END) [BD][1080p][AAC][MP4]/[Kanavid] Serial Experiments Lain NCED [BD][1080p][AAC].mp4"
write_jsonrpc_metadata "${tmpdir}/lain.json" "[Kanavid] Serial Experiments Lain 1-13(END) [BD][1080p][AAC][MP4]" "lainhash"

mkdir -p "${downloads}/Короткий фильм о любви.1988.BDRip 720p msltel"
printf russian > "${downloads}/Короткий фильм о любви.1988.BDRip 720p msltel/Короткий фильм о любви.1988.BDRip 720p msltel.mkv"
write_jsonrpc_metadata "${tmpdir}/russian-movie.json" "Короткий фильм о любви.1988.BDRip 720p msltel" "russianmoviehash"

mkdir -p "${downloads}/Andrei Tarkovsky's Stalker (1979) - 1080p x265 HEVC - RUS (ENG SUBS) [BRSHNKV]"
printf stalker > "${downloads}/Andrei Tarkovsky's Stalker (1979) - 1080p x265 HEVC - RUS (ENG SUBS) [BRSHNKV]/Stalker .mkv"
printf stalkersubs > "${downloads}/Andrei Tarkovsky's Stalker (1979) - 1080p x265 HEVC - RUS (ENG SUBS) [BRSHNKV]/Stalker.srt"
write_jsonrpc_metadata "${tmpdir}/stalker.json" "Andrei Tarkovsky's Stalker (1979) - 1080p x265 HEVC - RUS (ENG SUBS) [BRSHNKV]" "stalkerhash"

mkdir -p "${downloads}/Love.Letter.1995.1080p.BluRay.x264.DTS-WiKi [PublicHD]"
printf loveletter > "${downloads}/Love.Letter.1995.1080p.BluRay.x264.DTS-WiKi [PublicHD]/Love.Letter.1995.1080p.BluRay.x264.DTS-WiKi.mkv"
write_jsonrpc_metadata "${tmpdir}/love-letter.json" "Love.Letter.1995.1080p.BluRay.x264.DTS-WiKi [PublicHD]" "loveletterhash"

mkdir -p "${downloads}/Initial D Complete"
printf initiald1 > "${downloads}/Initial D Complete/Initial D S05E01 A New Battlefield.mkv"
printf initiald2 > "${downloads}/Initial D Complete/Initial D - 5x02 - Ryosuke's Fury.mkv"
write_jsonrpc_metadata "${tmpdir}/initial-d.json" "Initial D Complete" "initialdhash"

mkdir -p "${downloads}/[SNSbu] Long Riders! (BD 1920x1080 HEVC FLAC)/Extras"
printf nced > "${downloads}/[SNSbu] Long Riders! (BD 1920x1080 HEVC FLAC)/Extras/[SNSbu] Long Riders! - NCED (BD 1920x1080 HEVC FLAC).mkv"
printf ncop1 > "${downloads}/[SNSbu] Long Riders! (BD 1920x1080 HEVC FLAC)/Extras/[SNSbu] Long Riders! - NCOP 01 (BD 1920x1080 HEVC FLAC).mkv"
printf longriders01 > "${downloads}/[SNSbu] Long Riders! (BD 1920x1080 HEVC FLAC)/[SNSbu] Long Riders! - 01 (BD 1920x1080 HEVC FLAC).mkv"
printf longriders02 > "${downloads}/[SNSbu] Long Riders! (BD 1920x1080 HEVC FLAC)/[SNSbu] Long Riders! - 02 (BD 1920x1080 HEVC FLAC).mkv"
printf longriders03 > "${downloads}/[SNSbu] Long Riders! (BD 1920x1080 HEVC FLAC)/[SNSbu] Long Riders! - 03 (BD 1920x1080 HEVC FLAC).mkv"
write_jsonrpc_metadata "${tmpdir}/long-riders.json" "[SNSbu] Long Riders! (BD 1920x1080 HEVC FLAC)" "longridershash"

mkdir -p "${downloads}/Seasonless Anime"
printf seasonless01 > "${downloads}/Seasonless Anime/Seasonless Anime E01.mkv"
printf seasonless02 > "${downloads}/Seasonless Anime/Seasonless Anime E02.mkv"
write_jsonrpc_metadata "${tmpdir}/seasonless-anime.json" "Seasonless Anime" "seasonlessanimehash"

mkdir -p "${downloads}/Danger.5.S01"
printf dangertrailer > "${downloads}/Danger.5.S01/1Danger.5.Trailer.Show.WEBRip.x264-mOt.mp4"
printf dangerslogan > "${downloads}/Danger.5.S01/1KABLAM!!!-Slogan.avi"
printf dangerspecial > "${downloads}/Danger.5.S01/Danger.5.S01E00.WS.WEBRip.x264-mOt.The.Diamond.Girls.mp4"
printf danger01 > "${downloads}/Danger.5.S01/Danger.5.S01E01.HDTV.XviD-tellymad.I.Danced.for.Hitler.avi"
write_jsonrpc_metadata "${tmpdir}/danger-5.json" "Danger.5.S01" "danger5hash"

cat > "${tmpdir}/tmdb-fixture.json" <<JSON
{
  "movie": {
    "Perfect Blue": {
      "results": [
        {"id": 10494, "title": "Perfect Blue", "release_date": "1997-07-25"}
      ]
    },
    "Короткий Фильм О Любви": {
      "results": [
        {"id": 31056, "title": "A Short Film About Love", "original_title": "Krótki film o miłości", "release_date": "1988-08-21"}
      ]
    },
    "Andrei Tarkovsky's Stalker": {
      "results": []
    },
    "Stalker": {
      "results": [
        {"id": 1398, "title": "Stalker", "release_date": "1979-05-25"},
        {"id": 1444232, "title": "Stalker", "release_date": "2025-05-23"},
        {"id": 401218, "title": "Stalker", "release_date": "2014-08-27"}
      ]
    },
    "Love Letter": {
      "results": [
        {"id": 1370985, "title": "love letter", "release_date": "1995-02-05", "vote_count": 0, "popularity": 0.0461},
        {"id": 47002, "title": "Love Letter", "release_date": "1995-03-25", "vote_count": 265, "popularity": 5.2822}
      ]
    },
    "Initial D": {
      "results": [
        {"id": 9659, "title": "Initial D", "release_date": "2005-06-23", "vote_count": 450, "popularity": 12.2}
      ]
    },
    "Extras": {
      "results": [
        {"id": 386277, "title": "Extras", "release_date": "2006-10-27", "vote_count": 6, "popularity": 1.1}
      ]
    },
    "Fury": {
      "results": [
        {"id": 228150, "title": "Fury", "release_date": "2014-10-15", "vote_count": 12961, "popularity": 41.2}
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
    "Serial Experiments Lain": {
      "results": [
        {"id": 1087, "name": "Serial Experiments Lain", "first_air_date": "1998-07-06"}
      ]
    },
    "Patriot": {
      "results": [
        {"id": 64396, "name": "Patriot", "first_air_date": "2015-11-05"}
      ]
    },
    "Stalker": {
      "results": [
        {"id": 60796, "name": "Stalker", "first_air_date": "2014-10-01"}
      ]
    },
    "Initial D": {
      "results": [
        {"id": 40424, "name": "Initial D", "first_air_date": "1998-04-19", "vote_count": 132, "popularity": 18.4}
      ]
    },
    "Extras": {
      "results": [
        {"id": 2693, "name": "Extras", "first_air_date": "2005-07-21", "vote_count": 420, "popularity": 8.8}
      ]
    },
    "Long Riders!": {
      "results": [
        {"id": 65337, "name": "Long Riders!", "first_air_date": "2016-10-08", "vote_count": 5, "popularity": 2.5}
      ]
    },
    "Danger 5": {
      "results": [
        {"id": 43199, "name": "Danger 5", "first_air_date": "2012-02-27", "vote_count": 70, "popularity": 2.1811}
      ]
    },
    "Seasonless Anime": {
      "results": [
        {"id": 424242, "name": "Seasonless Anime", "first_air_date": "2020-01-01"}
      ]
    }
  },
  "alternative_titles": {
    "movie": {
      "31056": {
        "titles": [
          {"iso_3166_1": "RU", "title": "Короткий фильм о любви", "type": ""}
        ]
      }
    }
  }
}
JSON

run_sorter --metadata-json "${tmpdir}/perfect.json"
run_sorter --metadata-json "${tmpdir}/patriot.json"
run_sorter --metadata-json "${tmpdir}/lain.json"
run_sorter --metadata-json "${tmpdir}/russian-movie.json"
run_sorter --metadata-json "${tmpdir}/stalker.json"
run_sorter --metadata-json "${tmpdir}/love-letter.json"
run_sorter --metadata-json "${tmpdir}/initial-d.json"
run_sorter --metadata-json "${tmpdir}/long-riders.json"
run_sorter --metadata-json "${tmpdir}/seasonless-anime.json"
run_sorter --metadata-json "${tmpdir}/danger-5.json"
run_sorter --process-queue --tmdb-fixture-json "${tmpdir}/tmdb-fixture.json"
assert_samefile "${downloads}/Perfect.Blue.1997.JAPANESE.REMASTERED.1080p.BluRay.x265-GalaxyRG265[TGx]/Perfect.Blue.1997.JAPANESE.REMASTERED.1080p.BluRay.x265-GalaxyRG265.mkv" "${films}/Perfect Blue/Perfect.Blue.1997.JAPANESE.REMASTERED.1080p.BluRay.x265-GalaxyRG265.mkv"
grep -qx '\*' "${downloads}/Perfect.Blue.1997.JAPANESE.REMASTERED.1080p.BluRay.x265-GalaxyRG265[TGx]/.ignore"
assert_samefile "${downloads}/Patriot Season 2 Complete 720p WEBRip x264 [i_c]/Patriot S02E01 American Dimes.mkv" "${series}/Patriot/Season 02/Patriot S02E01 American Dimes.mkv"
assert_samefile "${downloads}/[Kanavid] Serial Experiments Lain 1-13(END) [BD][1080p][AAC][MP4]/[Kanavid] Serial Experiments Lain - 01 [BD][1080p][AAC].mp4" "${series}/Serial Experiments Lain/Season 01/[Kanavid] Serial Experiments Lain - S01E01 [BD][1080p][AAC].mp4"
assert_samefile "${downloads}/[Kanavid] Serial Experiments Lain 1-13(END) [BD][1080p][AAC][MP4]/[Kanavid] Serial Experiments Lain Clean OP [BD][1080p][AAC].mp4" "${series}/Serial Experiments Lain/Season 01/extras/[Kanavid] Serial Experiments Lain Clean OP [BD][1080p][AAC].mp4"
assert_samefile "${downloads}/[Kanavid] Serial Experiments Lain 1-13(END) [BD][1080p][AAC][MP4]/[Kanavid] Serial Experiments Lain NCOP [BD][1080p][AAC].mp4" "${series}/Serial Experiments Lain/Season 01/extras/[Kanavid] Serial Experiments Lain NCOP [BD][1080p][AAC].mp4"
assert_samefile "${downloads}/[Kanavid] Serial Experiments Lain 1-13(END) [BD][1080p][AAC][MP4]/[Kanavid] Serial Experiments Lain NCED [BD][1080p][AAC].mp4" "${series}/Serial Experiments Lain/Season 01/extras/[Kanavid] Serial Experiments Lain NCED [BD][1080p][AAC].mp4"
assert_samefile "${downloads}/Короткий фильм о любви.1988.BDRip 720p msltel/Короткий фильм о любви.1988.BDRip 720p msltel.mkv" "${films}/A Short Film About Love/Короткий фильм о любви.1988.BDRip 720p msltel.mkv"
assert_samefile "${downloads}/Andrei Tarkovsky's Stalker (1979) - 1080p x265 HEVC - RUS (ENG SUBS) [BRSHNKV]/Stalker .mkv" "${films}/Stalker/Stalker .mkv"
assert_samefile "${downloads}/Andrei Tarkovsky's Stalker (1979) - 1080p x265 HEVC - RUS (ENG SUBS) [BRSHNKV]/Stalker.srt" "${films}/Stalker/Stalker.srt"
assert_samefile "${downloads}/Love.Letter.1995.1080p.BluRay.x264.DTS-WiKi [PublicHD]/Love.Letter.1995.1080p.BluRay.x264.DTS-WiKi.mkv" "${films}/Love Letter/Love.Letter.1995.1080p.BluRay.x264.DTS-WiKi.mkv"
assert_samefile "${downloads}/Initial D Complete/Initial D S05E01 A New Battlefield.mkv" "${series}/Initial D/Season 05/Initial D S05E01 A New Battlefield.mkv"
assert_samefile "${downloads}/Initial D Complete/Initial D - 5x02 - Ryosuke's Fury.mkv" "${series}/Initial D/Season 05/Initial D - S05E02 - Ryosuke's Fury.mkv"
assert_not_exists "${films}/Fury"
assert_not_exists "${films}/Initial D"
assert_samefile "${downloads}/[SNSbu] Long Riders! (BD 1920x1080 HEVC FLAC)/[SNSbu] Long Riders! - 01 (BD 1920x1080 HEVC FLAC).mkv" "${series}/Long Riders!/Season 01/[SNSbu] Long Riders! - S01E01 (BD 1920x1080 HEVC FLAC).mkv"
assert_samefile "${downloads}/[SNSbu] Long Riders! (BD 1920x1080 HEVC FLAC)/Extras/[SNSbu] Long Riders! - NCOP 01 (BD 1920x1080 HEVC FLAC).mkv" "${series}/Long Riders!/Season 01/extras/[SNSbu] Long Riders! - NCOP 01 (BD 1920x1080 HEVC FLAC).mkv"
assert_samefile "${downloads}/Danger.5.S01/Danger.5.S01E01.HDTV.XviD-tellymad.I.Danced.for.Hitler.avi" "${series}/Danger 5/Season 01/Danger.5.S01E01.HDTV.XviD-tellymad.I.Danced.for.Hitler.avi"
assert_samefile "${downloads}/Danger.5.S01/Danger.5.S01E00.WS.WEBRip.x264-mOt.The.Diamond.Girls.mp4" "${series}/Danger 5/Season 00/Danger.5.S01E00.WS.WEBRip.x264-mOt.The.Diamond.Girls.mp4"
assert_samefile "${downloads}/Danger.5.S01/1Danger.5.Trailer.Show.WEBRip.x264-mOt.mp4" "${series}/Danger 5/Season 01/trailers/1Danger.5.Trailer.Show.WEBRip.x264-mOt.mp4"
assert_samefile "${downloads}/Danger.5.S01/1KABLAM!!!-Slogan.avi" "${series}/Danger 5/Season 01/clips/1KABLAM!!!-Slogan.avi"
assert_not_exists "${series}/Danger 5/Season 01/Danger.5.S01E00.WS.WEBRip.x264-mOt.The.Diamond.Girls.mp4"
assert_not_exists "${series}/Danger 5/Season 01/1Danger.5.Trailer.Show.WEBRip.x264-mOt.mp4"
assert_not_exists "${series}/Danger 5/Season 01/1KABLAM!!!-Slogan.avi"
assert_not_exists "${series}/Extras"
assert_not_exists "${series}/Seasonless Anime"
test -f "${queue_root}/needs-review/btih_seasonlessanimehash.json"
jq -e '.reason == "series season ambiguous" and .match.candidates[0].provider_id == 424242' "${queue_root}/needs-review/btih_seasonlessanimehash.json" >/dev/null
assert_not_exists "${series}/Serial Experiments Lain/Season 01/[Kanavid] Serial Experiments Lain Clean OP [BD][1080p][AAC].mp4"
assert_not_exists "${series}/Serial Experiments Lain/Season 01/[Kanavid] Serial Experiments Lain NCOP [BD][1080p][AAC].mp4"
assert_not_exists "${series}/Serial Experiments Lain/Season 00"
test -f "${queue_root}/done/btih_perfecthash.json"
jq -e '.raw_ignore.status == "created" and (.raw_ignore.path | endswith("/.ignore"))' "${queue_root}/done/btih_perfecthash.json" >/dev/null
test -f "${queue_root}/done/btih_patriothash.json"
test -f "${queue_root}/done/btih_lainhash.json"
test -f "${queue_root}/done/btih_russianmoviehash.json"
test -f "${queue_root}/done/btih_stalkerhash.json"
test -f "${queue_root}/done/btih_loveletterhash.json"
test -f "${queue_root}/done/btih_initialdhash.json"
test -f "${queue_root}/done/btih_longridershash.json"
test -f "${queue_root}/done/btih_danger5hash.json"
jq -e '.match.query == "Serial Experiments Lain" and .match.hints.season == 1' "${queue_root}/done/btih_lainhash.json" >/dev/null
jq -e '.match.selected.matched_title_source == "alternative_title" and .match.selected.provider_id == 31056' "${queue_root}/done/btih_russianmoviehash.json" >/dev/null
jq -e '.match.query == "Stalker" and .match.selected.query_source == "file-stem" and .match.selected.provider_id == 1398' "${queue_root}/done/btih_stalkerhash.json" >/dev/null
jq -e '.match.selected.provider_id == 47002 and .match.tie_breaker.type == "vote_count" and .match.tie_breaker.vote_gap == 265' "${queue_root}/done/btih_loveletterhash.json" >/dev/null
jq -e '.match.selected.media_type == "tv" and .match.selected.provider_id == 40424' "${queue_root}/done/btih_initialdhash.json" >/dev/null
jq -e '.match.query == "Long Riders!" and .match.selected.provider_id == 65337 and .match.hints.season == 1' "${queue_root}/done/btih_longridershash.json" >/dev/null
jq -e '.match.query == "Danger 5" and .match.selected.provider_id == 43199 and .match.hints.season == 1' "${queue_root}/done/btih_danger5hash.json" >/dev/null

mkdir -p "${downloads}/Ambiguous.2020.1080p.WEBRip"
printf ambiguous > "${downloads}/Ambiguous.2020.1080p.WEBRip/Ambiguous.2020.1080p.WEBRip.mkv"
write_jsonrpc_metadata "${tmpdir}/ambiguous.json" "Ambiguous.2020.1080p.WEBRip" "ambiguoushash"
run_sorter --metadata-json "${tmpdir}/ambiguous.json"
run_sorter --process-queue --tmdb-fixture-json "${tmpdir}/tmdb-fixture.json"
test -f "${queue_root}/needs-review/btih_ambiguoushash.json"
[[ "$(stat -c '%a' "${queue_root}/needs-review/btih_ambiguoushash.json")" == "640" ]]
assert_not_exists "${films}/Ambiguous"
assert_not_exists "${downloads}/Ambiguous.2020.1080p.WEBRip/.ignore"
run_sorter --queue > "${tmpdir}/queue-review.out"
grep -q "needs-review:" "${tmpdir}/queue-review.out"
grep -q "btih_ambiguoushash.json" "${tmpdir}/queue-review.out"
grep -q "torrent: Ambiguous.2020.1080p.WEBRip" "${tmpdir}/queue-review.out"
grep -q "reason: ambiguous TMDB match" "${tmpdir}/queue-review.out"
grep -q "\\[video\\] Ambiguous.2020.1080p.WEBRip/Ambiguous.2020.1080p.WEBRip.mkv" "${tmpdir}/queue-review.out"

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
set +e
run_sorter --metadata-json "${tmpdir}/conflict.json" --label "series:Conflict Show" > "${tmpdir}/conflict.out" 2>&1
conflict_rc=$?
set -e
[[ "${conflict_rc}" -eq 1 ]]
grep -q "destination conflict" "${tmpdir}/conflict.out"
[[ "$(cat "${series}/Conflict Show/Season 01/Conflict.S01E01.mkv")" == "different" ]]

mkdir -p "${downloads}/Corporate.S01"
printf corporate > "${downloads}/Corporate.S01/Corporate.S01E01.mkv"
run_sorter --backfill-current-downloads --dry-run > "${tmpdir}/backfill-dry-run.out" 2>&1
grep -q "would hardlink" "${tmpdir}/backfill-dry-run.out"
assert_not_exists "${series}/Corporate/Season 01/Corporate.S01E01.mkv"
run_sorter --backfill-current-downloads --apply
assert_samefile "${downloads}/Corporate.S01/Corporate.S01E01.mkv" "${series}/Corporate/Season 01/Corporate.S01E01.mkv"
grep -qx '\*' "${downloads}/Corporate.S01/.ignore"
assert_not_exists "${books}/Comics/Comic Pack"

echo "media sorter tests passed"
