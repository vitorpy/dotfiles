#!/bin/bash

# Smart clock that shows local time + Warsaw time when traveling

WARSAW_TZ="Europe/Warsaw"
WALLPAPER_METADATA="${ARTS_WALLPAPER_METADATA:-${XDG_DATA_HOME:-$HOME/.local/share}/arts-wallpaper/current.json}"

# Get current timezone
current_tz=$(timedatectl show --property=Timezone --value)

# Get local time
local_time=$(date '+%a, %d.%m %H:%M')
tooltip=$(date '+%A, %d %B %Y')

# Check if we're in Warsaw timezone
if [ "$current_tz" = "$WARSAW_TZ" ]; then
    # Just show local time
    clock_text="$local_time"
else
    # Show local time + Warsaw time in parentheses
    warsaw_time=$(TZ="$WARSAW_TZ" date '+%d.%m %H:%M')
    clock_text="$local_time ($warsaw_time)"
fi

# Add the current wallpaper's metadata when it is available and valid.
artwork_tooltip=$(jq -er '
    if type != "object" or (.title | type) != "string" or (.title | length) == 0 then
        empty
    else
        [
            "Artwork",
            .title,
            ([.creator, .date]
                | map(select(type == "string" and length > 0))
                | join(" — ")),
            .provider_name,
            (if (.attribution | type) == "string"
                    and (.attribution | length) > 0
                    and .attribution != .provider_name
                then "Credit: " + .attribution
                else empty
            end),
            (if (.rights | type) == "string" and (.rights | length) > 0
                then "Rights: " + .rights
                else empty
            end)
        ]
        | map(select(type == "string" and length > 0))
        | join("\n")
    end
' "$WALLPAPER_METADATA" 2>/dev/null || true)

if [ -n "$artwork_tooltip" ]; then
    tooltip="$tooltip

$artwork_tooltip"
fi

jq -cn --arg text "$clock_text" --arg tooltip "$tooltip" '{text: $text, tooltip: $tooltip}'
