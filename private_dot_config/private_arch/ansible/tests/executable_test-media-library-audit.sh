#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
audit="${repo_root}/roles/services/files/media-library-audit"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

downloads="${tmpdir}/downloads"
series="${tmpdir}/series"
films="${tmpdir}/films"
music="${tmpdir}/music"
queue_root="${tmpdir}/queue-root"
mkdir -p "${downloads}/radarr/Raw.Movie" "${downloads}/radarr/Ignored.Movie" "${downloads}/tv-sonarr" "${series}/Example/Season 01" "${films}/Clean Movie" "${music}" "${queue_root}/failed"
mkdir -p "${downloads}/radarr/Shin" "${films}/Shin Godzilla"
printf raw > "${downloads}/radarr/Raw.Movie/Raw.Movie.mkv"
printf ignored > "${downloads}/radarr/Ignored.Movie/Ignored.Movie.mkv"
printf shin-raw > "${downloads}/radarr/Shin/Shin.mkv"
printf shin-canonical > "${films}/Shin Godzilla/Shin.mkv"
printf episode > "${series}/Example/Season 01/Example.S01E01.mkv"
printf clean > "${films}/Clean Movie/Clean Movie.mkv"
: > "${downloads}/radarr/Ignored.Movie/.ignore"
printf '{}' > "${queue_root}/failed/example.json"

cat > "${tmpdir}/jellyfin-dirty.json" <<JSON
[
  {
    "Id": "movie-raw",
    "Name": "Shin Godzilla",
    "Type": "Movie",
    "Path": "${downloads}/radarr/Shin/Shin.mkv",
    "ProviderIds": {"Tmdb": "315011", "Imdb": "tt4262980"},
    "Overview": "ok",
    "MediaSources": [{"Path": "${downloads}/radarr/Shin/Shin.mkv"}]
  },
  {
    "Id": "movie-canonical",
    "Name": "Shin Godzilla",
    "Type": "Movie",
    "Path": "${films}/Shin Godzilla/Shin.mkv",
    "ProviderIds": {"Tmdb": "315011", "Imdb": "tt4262980"},
    "Overview": "ok",
    "MediaSources": [{"Path": "${films}/Shin Godzilla/Shin.mkv"}]
  },
  {
    "Id": "episode-empty",
    "Name": "Example.S01E01",
    "Type": "Episode",
    "Path": "${series}/Example/Season 01/Example.S01E01.mkv",
    "ProviderIds": {},
    "Overview": "",
    "MediaSources": [{"Path": "${series}/Example/Season 01/Example.S01E01.mkv"}]
  },
  {
    "Id": "stale-video",
    "Name": "Missing Video",
    "Type": "Video",
    "Path": "${series}/Missing/Missing.mkv",
    "ProviderIds": {},
    "Overview": "ok",
    "MediaSources": [{"Path": "${series}/Missing/Missing.mkv"}]
  }
]
JSON

cat > "${tmpdir}/sonarr-dirty.json" <<JSON
[
  {"id": 1, "title": "Wrong Show", "path": "${downloads}/tv-sonarr/Wrong.Show"}
]
JSON

cat > "${tmpdir}/radarr-dirty.json" <<JSON
[
  {"id": 1, "title": "Wrong Movie", "path": "${downloads}/radarr/Wrong.Movie"}
]
JSON

set +e
python3 "${audit}" \
  --download-root "${downloads}" \
  --series-root "${series}" \
  --films-root "${films}" \
  --music-root "${music}" \
  --queue-root "${queue_root}" \
  --jellyfin-items-json "${tmpdir}/jellyfin-dirty.json" \
  --sonarr-series-json "${tmpdir}/sonarr-dirty.json" \
  --radarr-movies-json "${tmpdir}/radarr-dirty.json" \
  --json > "${tmpdir}/dirty.out"
dirty_rc=$?
set -e
[[ "${dirty_rc}" -eq 1 ]]
jq -e '.counts.findings >= 8' "${tmpdir}/dirty.out" >/dev/null
jq -e '[.findings[].type] | index("jellyfin_download_path")' "${tmpdir}/dirty.out" >/dev/null
jq -e '[.findings[].type] | index("jellyfin_duplicate_provider_id")' "${tmpdir}/dirty.out" >/dev/null
jq -e '[.findings[].type] | index("jellyfin_missing_provider_ids")' "${tmpdir}/dirty.out" >/dev/null
jq -e '[.findings[].type] | index("jellyfin_missing_overview")' "${tmpdir}/dirty.out" >/dev/null
jq -e '[.findings[].type] | index("jellyfin_missing_path")' "${tmpdir}/dirty.out" >/dev/null
jq -e '[.findings[].type] | index("sonarr_download_path")' "${tmpdir}/dirty.out" >/dev/null
jq -e '[.findings[].type] | index("radarr_download_path")' "${tmpdir}/dirty.out" >/dev/null
jq -e '[.findings[].type] | index("raw_download_missing_ignore")' "${tmpdir}/dirty.out" >/dev/null
jq -e '[.findings[].type] | index("media_sorter_queue_attention")' "${tmpdir}/dirty.out" >/dev/null

clean_queue="${tmpdir}/clean-queue"
mkdir -p "${clean_queue}"
: > "${downloads}/radarr/Raw.Movie/.ignore"
: > "${downloads}/radarr/Shin/.ignore"
cat > "${tmpdir}/jellyfin-clean.json" <<JSON
[
  {
    "Id": "movie-clean",
    "Name": "Clean Movie",
    "Type": "Movie",
    "Path": "${films}/Clean Movie/Clean Movie.mkv",
    "ProviderIds": {"Tmdb": "1"},
    "Overview": "ok",
    "MediaSources": [{"Path": "${films}/Clean Movie/Clean Movie.mkv"}]
  },
  {
    "Id": "episode-clean",
    "Name": "Pilot",
    "Type": "Episode",
    "Path": "${series}/Example/Season 01/Example.S01E01.mkv",
    "ProviderIds": {"Tvdb": "2"},
    "Overview": "ok",
    "MediaSources": [{"Path": "${series}/Example/Season 01/Example.S01E01.mkv"}]
  }
]
JSON
printf '[]\n' > "${tmpdir}/empty.json"

python3 "${audit}" \
  --download-root "${downloads}" \
  --series-root "${series}" \
  --films-root "${films}" \
  --music-root "${music}" \
  --queue-root "${clean_queue}" \
  --jellyfin-items-json "${tmpdir}/jellyfin-clean.json" \
  --sonarr-series-json "${tmpdir}/empty.json" \
  --radarr-movies-json "${tmpdir}/empty.json" \
  --json > "${tmpdir}/clean.out"
jq -e '.counts.findings == 0' "${tmpdir}/clean.out" >/dev/null

echo "media library audit tests passed"
