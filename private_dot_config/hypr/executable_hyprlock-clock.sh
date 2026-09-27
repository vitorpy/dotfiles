#!/usr/bin/env bash
set -euo pipefail

# Share Berg's timezone validation and offline fallback without changing the
# system timezone. Keep the lock screen's existing Pango layout and date format.
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
epoch=$(date +%s)
local_timezone=$(/usr/bin/python3 "$config_home/quickshell/berg/scripts/clock-time.py" \
    --epoch "$epoch" \
    --location-cache "$cache_home/quickshell-berg/location.json" \
    | jq -er '.local.timezone')

TZ="$local_timezone" date --date="@$epoch" \
    +"<span size='78pt' line_height='87040'>%H:%M</span>%n<span size='24pt'>%A, %d %B %Y</span>"
