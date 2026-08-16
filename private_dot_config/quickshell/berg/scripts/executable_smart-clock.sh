#!/bin/bash

# Smart clock that shows local time + Warsaw time when traveling

WARSAW_TZ="Europe/Warsaw"
WALLPAPER_METADATA="${ARTS_WALLPAPER_METADATA:-${XDG_DATA_HOME:-$HOME/.local/share}/arts-wallpaper/current.json}"
WEATHER_CACHE="${CLOCK_WEATHER_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/waybar-clock/weather.json}"
WEATHER_MAX_AGE="${CLOCK_WEATHER_MAX_AGE:-10800}"

# Get current timezone
current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || printf '%s' "$WARSAW_TZ")

# Get local time
local_time=$(date '+%a, %d.%m %H:%M')
time_tooltip="Time
Local · $(date '+%A, %d %B · %H:%M')"

# Check if we're in Warsaw timezone
if [ "$current_tz" = "$WARSAW_TZ" ]; then
    # Just show local time
    clock_text="$local_time"
else
    # Show local time + Warsaw time in parentheses
    warsaw_time=$(TZ="$WARSAW_TZ" date '+%d.%m %H:%M')
    clock_text="$local_time ($warsaw_time)"
    time_tooltip="$time_tooltip
Warsaw · $(TZ="$WARSAW_TZ" date '+%A, %d %B · %H:%M')"
fi

# Read only a recent, fully validated cache. Network updates happen out of band
# so the 30-second Waybar refresh can never be held up by a weather provider.
weather_tooltip=""
if [[ $WEATHER_MAX_AGE =~ ^[0-9]+$ && -f $WEATHER_CACHE ]]; then
    weather_modified=$(stat -c %Y -- "$WEATHER_CACHE" 2>/dev/null || printf '0')
    weather_age=$(($(date +%s) - weather_modified))

    if (( weather_age >= 0 && weather_age <= WEATHER_MAX_AGE )); then
        weather_tooltip=$(jq -er '
            def rounded: round | tostring;
            def hour_label:
                if type == "string" and test("T[0-9]{2}:[0-9]{2}$")
                then split("T")[1]
                else "Next hour"
                end;

            select(type == "object")
            | select(.location.city | type == "string" and length > 0)
            | select(.location.country_code | type == "string" and length == 2)
            | select(.current.condition | type == "string" and length > 0)
            | select(.current.temperature_c | type == "number")
            | select(.current.apparent_temperature_c | type == "number")
            | select(.current.wind_speed_kmh | type == "number")
            | select(.next_hour.time | type == "string" and length > 0)
            | select(.next_hour.condition | type == "string" and length > 0)
            | select(.next_hour.temperature_c | type == "number")
            | select(.next_hour.precipitation_probability | type == "number")
            | [
                "Weather · " + .location.city + ", " + .location.country_code,
                "Now · " + .current.condition
                    + " · " + (.current.temperature_c | rounded) + " °C"
                    + " · feels " + (.current.apparent_temperature_c | rounded) + " °C",
                (.next_hour.time | hour_label) + " · " + .next_hour.condition
                    + " · " + (.next_hour.temperature_c | rounded) + " °C"
                    + " · precip. " + (.next_hour.precipitation_probability | rounded) + "%",
                "Wind · " + (.current.wind_speed_kmh | rounded) + " km/h"
            ]
            | join("\n")
        ' "$WEATHER_CACHE" 2>/dev/null || true)
    fi
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

tooltip="$time_tooltip"

if [ -n "$weather_tooltip" ]; then
    tooltip="$tooltip

$weather_tooltip"
fi

if [ -n "$artwork_tooltip" ]; then
    tooltip="$tooltip

$artwork_tooltip"
fi

jq -cn --arg text "$clock_text" --arg tooltip "$tooltip" '{text: $text, tooltip: $tooltip}'
