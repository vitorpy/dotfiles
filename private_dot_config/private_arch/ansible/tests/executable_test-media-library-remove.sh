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
books="${tmpdir}/books"
queue_root="${tmpdir}/queue-root"
mkdir -p "${downloads}" "${series}" "${films}" "${music}" "${books}/Books" "${books}/Comics" "${queue_root}"
jellyfin_items_json="${tmpdir}/jellyfin-items.json"
sonarr_series_json="${tmpdir}/sonarr-series.json"
api_log="${tmpdir}/api.log"
: > "${api_log}"

run_remover() {
  python3 "${remover}" \
    --download-root "${downloads}" \
    --series-root "${series}" \
    --films-root "${films}" \
    --music-root "${music}" \
    --books-root "${books}" \
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

run_remover_api() {
  python3 "${remover}" \
    --download-root "${downloads}" \
    --series-root "${series}" \
    --films-root "${films}" \
    --music-root "${music}" \
    --books-root "${books}" \
    --queue-root "${queue_root}" \
    "$@"
}

jelly_show="${series}/Jelly Show"
mkdir -p "${jelly_show}/Season 01"
printf episode > "${jelly_show}/Season 01/Jelly.Show.S01E01.mkv"
cat > "${jellyfin_items_json}" <<JSON
{
  "Items": [
    {
      "Id": "jf-episode",
      "Name": "Jelly Show S01E01",
      "Type": "Episode",
      "Path": "${jelly_show}/Season 01/Jelly.Show.S01E01.mkv",
      "CanDelete": true,
      "MediaSources": [{"Path": "${jelly_show}/Season 01/Jelly.Show.S01E01.mkv"}]
    }
  ]
}
JSON
run_remover_api \
  --path "${jelly_show}" \
  --no-sonarr \
  --no-radarr \
  --no-transmission \
  --jellyfin-api-key test-key \
  --jellyfin-items-json "${jellyfin_items_json}" \
  --jellyfin-delete-log "${api_log}" \
  --apply > "${tmpdir}/jellyfin-apply.out"
grep -q "deleted jellyfin item id=jf-episode" "${tmpdir}/jellyfin-apply.out"
grep -q "  jellyfin: 0" "${tmpdir}/jellyfin-apply.out"
grep -q "jellyfin jf-episode" "${api_log}"
assert_not_exists "${jelly_show}"

defer_show="${series}/Deferred Show"
mkdir -p "${defer_show}"
printf episode > "${defer_show}/Deferred.mkv"
cat > "${jellyfin_items_json}" <<JSON
{
  "Items": [
    {
      "Id": "jf-deferred",
      "Name": "Deferred Item",
      "Type": "Movie",
      "Path": "${defer_show}/Deferred.mkv",
      "CanDelete": true,
      "FailWhenPresent": true,
      "MediaSources": [{"Path": "${defer_show}/Deferred.mkv"}]
    }
  ]
}
JSON
run_remover_api \
  --path "${defer_show}" \
  --no-sonarr \
  --no-radarr \
  --no-transmission \
  --jellyfin-api-key test-key \
  --jellyfin-items-json "${jellyfin_items_json}" \
  --jellyfin-delete-log "${api_log}" \
  --apply > "${tmpdir}/deferred-apply.out" 2>&1
grep -q "item delete deferred id=jf-deferred" "${tmpdir}/deferred-apply.out"
grep -q "deleted stale jellyfin item id=jf-deferred" "${tmpdir}/deferred-apply.out"
grep -q "  jellyfin: 0" "${tmpdir}/deferred-apply.out"
assert_not_exists "${defer_show}"

stale_show="${series}/Stale Show"
cat > "${jellyfin_items_json}" <<JSON
{
  "Items": [
    {
      "Id": "jf-stale",
      "Name": "Stale Extra",
      "Type": "Video",
      "Path": "${stale_show}/extras/Stale.mkv",
      "CanDelete": true,
      "FailWhenMissing": true,
      "MediaSources": [{"Path": "${stale_show}/extras/Stale.mkv"}]
    }
  ]
}
JSON
run_remover_api \
  --path "${stale_show}" \
  --no-sonarr \
  --no-radarr \
  --no-transmission \
  --jellyfin-api-key test-key \
  --jellyfin-items-json "${jellyfin_items_json}" \
  --jellyfin-delete-log "${api_log}" \
  --apply > "${tmpdir}/stale-apply.out"
grep -q "deleted stale jellyfin item with placeholder id=jf-stale" "${tmpdir}/stale-apply.out"
grep -q "  jellyfin: 0" "${tmpdir}/stale-apply.out"
assert_not_exists "${stale_show}"

sonarr_config="${tmpdir}/sonarr.xml"
cat > "${sonarr_config}" <<XML
<Config><ApiKey>test-key</ApiKey></Config>
XML
arr_show="${series}/Arr Show"
mkdir -p "${arr_show}/Season 01"
printf episode > "${arr_show}/Season 01/Arr.Show.S01E01.mkv"
cat > "${sonarr_series_json}" <<JSON
[
  {"id": 42, "title": "Arr Show", "path": "${arr_show}"}
]
JSON
run_remover_api \
  --sonarr-id 42 \
  --no-radarr \
  --no-transmission \
  --no-jellyfin \
  --sonarr-series-json "${sonarr_series_json}" \
  --sonarr-delete-log "${api_log}" \
  --apply > "${tmpdir}/sonarr-apply.out"
grep -q "sonarr 42 deleteFiles=false" "${api_log}"
assert_not_exists "${arr_show}"

book_dir="${books}/Books/William Gibson/Neuromancer Series/001 - Neuromancer (34)"
mkdir -p "${book_dir}"
printf ebook > "${book_dir}/Neuromancer - William Gibson.epub"
printf cover > "${book_dir}/cover.jpg"
cat > "${book_dir}/metadata.opf" <<XML
<?xml version="1.0" encoding="utf-8"?>
<package xmlns:dc="http://purl.org/dc/elements/1.1/">
  <metadata><dc:title>Neuromancer</dc:title></metadata>
</package>
XML
cat > "${jellyfin_items_json}" <<JSON
{
  "Items": [
    {
      "Id": "jf-book",
      "Name": "1 - Neuromancer",
      "Type": "Book",
      "Path": "${book_dir}/Neuromancer - William Gibson.epub",
      "CanDelete": true,
      "MediaSources": [{"Path": "${book_dir}/Neuromancer - William Gibson.epub"}]
    }
  ]
}
JSON
run_remover_api \
  "Neuromancer" \
  --no-sonarr \
  --no-radarr \
  --no-transmission \
  --jellyfin-api-key test-key \
  --jellyfin-items-json "${jellyfin_items_json}" \
  --jellyfin-delete-log "${api_log}" > "${tmpdir}/book-dry-run.out"
grep -q "book: Neuromancer" "${tmpdir}/book-dry-run.out"
grep -q "${book_dir}" "${tmpdir}/book-dry-run.out"
assert_exists "${book_dir}"

run_remover_api \
  "Neuromancer" \
  --no-sonarr \
  --no-radarr \
  --no-transmission \
  --jellyfin-api-key test-key \
  --jellyfin-items-json "${jellyfin_items_json}" \
  --jellyfin-delete-log "${api_log}" \
  --apply > "${tmpdir}/book-apply.out"
grep -q "deleted jellyfin item id=jf-book" "${tmpdir}/book-apply.out"
grep -q "  jellyfin: 0" "${tmpdir}/book-apply.out"
assert_not_exists "${book_dir}"
assert_exists "${books}/Books"

comic_dir="${books}/Comics/Home Office Romance"
comic_download="${downloads}/comic-payload-84"
mkdir -p "${comic_dir}" "${comic_download}"
printf comic > "${comic_download}/Home Office Romance (2024).cbz"
ln "${comic_download}/Home Office Romance (2024).cbz" "${comic_dir}/Home Office Romance (2024).cbz"
printf cover > "${comic_dir}/cover.png"
cat > "${comic_dir}/ComicInfo.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<ComicInfo><Title>Home Office Romance</Title></ComicInfo>
XML
cat > "${jellyfin_items_json}" <<JSON
{
  "Items": [
    {
      "Id": "jf-comic",
      "Name": "Home Office Romance",
      "Type": "Book",
      "Path": "${comic_dir}/Home Office Romance (2024).cbz",
      "CanDelete": true,
      "MediaSources": [{"Path": "${comic_dir}/Home Office Romance (2024).cbz"}]
    }
  ]
}
JSON
run_remover_api \
  "Home Office Romance" \
  --no-sonarr \
  --no-radarr \
  --no-transmission \
  --jellyfin-api-key test-key \
  --jellyfin-items-json "${jellyfin_items_json}" \
  --jellyfin-delete-log "${api_log}" > "${tmpdir}/comic-dry-run.out"
grep -q "comic: Home Office Romance" "${tmpdir}/comic-dry-run.out"
grep -q "${comic_dir}" "${tmpdir}/comic-dry-run.out"
assert_exists "${comic_dir}"

run_remover_api \
  "Home Office Romance" \
  --no-sonarr \
  --no-radarr \
  --no-transmission \
  --jellyfin-api-key test-key \
  --jellyfin-items-json "${jellyfin_items_json}" \
  --jellyfin-delete-log "${api_log}" \
  --apply > "${tmpdir}/comic-apply.out"
grep -q "deleted jellyfin item id=jf-comic" "${tmpdir}/comic-apply.out"
grep -q "  jellyfin: 0" "${tmpdir}/comic-apply.out"
assert_not_exists "${comic_dir}"
assert_not_exists "${comic_download}"
assert_exists "${books}/Comics"

duplicate_one="${books}/Books/Author One/Shared Title (70)"
duplicate_two="${books}/Books/Author Two/Shared Title (71)"
mkdir -p "${duplicate_one}" "${duplicate_two}"
printf ebook > "${duplicate_one}/Shared Title - Author One.epub"
printf ebook > "${duplicate_two}/Shared Title - Author Two.pdf"
if run_remover "Shared Title" > "${tmpdir}/book-ambiguous.out" 2>&1; then
  echo "expected duplicate book title query to require refinement" >&2
  exit 1
fi
grep -q "multiple media entries matched" "${tmpdir}/book-ambiguous.out"
grep -q "${duplicate_one}" "${tmpdir}/book-ambiguous.out"
grep -q "${duplicate_two}" "${tmpdir}/book-ambiguous.out"

if run_remover --path "${books}/Books" > "${tmpdir}/books-root-guard.out" 2>&1; then
  echo "expected Books container deletion to fail" >&2
  exit 1
fi
grep -q "refusing unmanaged or root path" "${tmpdir}/books-root-guard.out"
