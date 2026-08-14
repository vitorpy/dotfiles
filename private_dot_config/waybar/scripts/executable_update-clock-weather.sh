#!/usr/bin/env bash

set -u

CACHE_DIR="${CLOCK_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/waybar-clock}"
LOCATION_CACHE="${CLOCK_LOCATION_CACHE:-$CACHE_DIR/location.json}"
WEATHER_CACHE="${CLOCK_WEATHER_CACHE:-$CACHE_DIR/weather.json}"
LOCATION_MAX_AGE="${CLOCK_LOCATION_MAX_AGE:-3600}"

IPAPI_URL="${CLOCK_IPAPI_URL:-https://ipapi.co/json/}"
IP_API_URL="${CLOCK_IP_API_URL:-http://ip-api.com/json/?fields=status,message,city,countryCode,lat,lon,timezone}"
WEATHER_URL="${CLOCK_WEATHER_URL:-https://api.open-meteo.com/v1/forecast}"

DEFAULT_CITY="${CLOCK_DEFAULT_CITY:-Poznań}"
DEFAULT_COUNTRY_CODE="${CLOCK_DEFAULT_COUNTRY_CODE:-PL}"
DEFAULT_LATITUDE="${CLOCK_DEFAULT_LATITUDE:-52.4064}"
DEFAULT_LONGITUDE="${CLOCK_DEFAULT_LONGITUDE:-16.9252}"
DEFAULT_TIMEZONE="${CLOCK_DEFAULT_TIMEZONE:-Europe/Warsaw}"

umask 077
mkdir -p -- "$CACHE_DIR" "$(dirname -- "$LOCATION_CACHE")" "$(dirname -- "$WEATHER_CACHE")"
chmod 700 -- "$CACHE_DIR"

is_nonnegative_integer() {
    [[ $1 =~ ^[0-9]+$ ]]
}

cache_is_fresh() {
    local path="$1"
    local max_age="$2"
    local modified_at age

    [[ -f $path ]] || return 1
    is_nonnegative_integer "$max_age" || return 1

    modified_at=$(stat -c %Y -- "$path" 2>/dev/null) || return 1
    age=$(($(date +%s) - modified_at))
    (( age >= 0 && age < max_age ))
}

valid_location_file() {
    jq -e '
        type == "object"
        and (.city | type == "string" and length > 0)
        and (.country_code | type == "string" and length == 2)
        and (.latitude | type == "number" and . >= -90 and . <= 90)
        and (.longitude | type == "number" and . >= -180 and . <= 180)
        and (.timezone | type == "string" and length > 0)
    ' "$1" >/dev/null 2>&1
}

atomic_write() {
    local path="$1"
    local contents="$2"
    local temporary

    temporary=$(mktemp "${path}.tmp.XXXXXX") || return 1
    if printf '%s\n' "$contents" >"$temporary" &&
        chmod 600 -- "$temporary" &&
        mv -f -- "$temporary" "$path"; then
        return 0
    fi

    rm -f -- "$temporary"
    return 1
}

normalize_ipapi_location() {
    local response="$1"
    local now="$2"

    jq -ce --argjson now "$now" '
        select(type == "object" and (.error // false) != true)
        | {
            updated_at: $now,
            city: (if .city == "Poznan" then "Poznań" else .city end),
            country_code: (.country_code // .country | ascii_upcase),
            latitude: .latitude,
            longitude: .longitude,
            timezone: .timezone,
            source: "ipapi.co"
        }
        | select(
            (.city | type == "string" and length > 0)
            and (.country_code | type == "string" and length == 2)
            and (.latitude | type == "number" and . >= -90 and . <= 90)
            and (.longitude | type == "number" and . >= -180 and . <= 180)
            and (.timezone | type == "string" and length > 0)
        )
    ' <<<"$response" 2>/dev/null
}

normalize_ip_api_location() {
    local response="$1"
    local now="$2"

    jq -ce --argjson now "$now" '
        select(type == "object" and .status == "success")
        | {
            updated_at: $now,
            city: (if .city == "Poznan" then "Poznań" else .city end),
            country_code: (.countryCode | ascii_upcase),
            latitude: .lat,
            longitude: .lon,
            timezone: .timezone,
            source: "ip-api.com"
        }
        | select(
            (.city | type == "string" and length > 0)
            and (.country_code | type == "string" and length == 2)
            and (.latitude | type == "number" and . >= -90 and . <= 90)
            and (.longitude | type == "number" and . >= -180 and . <= 180)
            and (.timezone | type == "string" and length > 0)
        )
    ' <<<"$response" 2>/dev/null
}

detect_location() {
    local now="$1"
    local response normalized

    if response=$(curl --fail --silent --connect-timeout 5 --max-time 10 "$IPAPI_URL") &&
        normalized=$(normalize_ipapi_location "$response" "$now"); then
        printf '%s\n' "$normalized"
        return 0
    fi

    if response=$(curl --fail --silent --connect-timeout 5 --max-time 10 "$IP_API_URL") &&
        normalized=$(normalize_ip_api_location "$response" "$now"); then
        printf '%s\n' "$normalized"
        return 0
    fi

    return 1
}

default_location() {
    local now="$1"

    jq -cn \
        --argjson now "$now" \
        --arg city "$DEFAULT_CITY" \
        --arg country_code "$DEFAULT_COUNTRY_CODE" \
        --argjson latitude "$DEFAULT_LATITUDE" \
        --argjson longitude "$DEFAULT_LONGITUDE" \
        --arg timezone "$DEFAULT_TIMEZONE" \
        '{
            updated_at: $now,
            city: $city,
            country_code: ($country_code | ascii_upcase),
            latitude: $latitude,
            longitude: $longitude,
            timezone: $timezone,
            source: "default"
        }'
}

normalize_weather() {
    local response="$1"
    local location="$2"
    local now="$3"

    jq -ce --argjson location "$location" --argjson now "$now" '
        def condition:
            if . == 0 then "Clear"
            elif . == 1 then "Mostly clear"
            elif . == 2 then "Partly cloudy"
            elif . == 3 then "Overcast"
            elif . == 45 or . == 48 then "Fog"
            elif . == 51 then "Light drizzle"
            elif . == 53 then "Drizzle"
            elif . == 55 then "Heavy drizzle"
            elif . == 56 or . == 57 then "Freezing drizzle"
            elif . == 61 then "Light rain"
            elif . == 63 then "Rain"
            elif . == 65 then "Heavy rain"
            elif . == 66 or . == 67 then "Freezing rain"
            elif . == 71 then "Light snow"
            elif . == 73 then "Snow"
            elif . == 75 then "Heavy snow"
            elif . == 77 then "Snow grains"
            elif . == 80 then "Light showers"
            elif . == 81 then "Showers"
            elif . == 82 then "Heavy showers"
            elif . == 85 or . == 86 then "Snow showers"
            elif . == 95 then "Thunderstorm"
            elif . == 96 or . == 99 then "Thunderstorm with hail"
            else "Unknown conditions"
            end;

        select(type == "object")
        | select(.current | type == "object")
        | select(.hourly | type == "object")
        | select(.hourly.time | type == "array" and length >= 2)
        | select(.hourly.temperature_2m | type == "array" and length >= 2)
        | select(.hourly.apparent_temperature | type == "array" and length >= 2)
        | select(.hourly.precipitation_probability | type == "array" and length >= 2)
        | select(.hourly.weather_code | type == "array" and length >= 2)
        | select(.hourly.wind_speed_10m | type == "array" and length >= 2)
        | {
            updated_at: $now,
            source: "open-meteo.com",
            location: $location,
            current: {
                time: .current.time,
                temperature_c: .current.temperature_2m,
                apparent_temperature_c: .current.apparent_temperature,
                precipitation_probability: .current.precipitation_probability,
                weather_code: .current.weather_code,
                condition: (.current.weather_code | condition),
                wind_speed_kmh: .current.wind_speed_10m
            },
            next_hour: {
                time: .hourly.time[1],
                temperature_c: .hourly.temperature_2m[1],
                apparent_temperature_c: .hourly.apparent_temperature[1],
                precipitation_probability: .hourly.precipitation_probability[1],
                weather_code: .hourly.weather_code[1],
                condition: (.hourly.weather_code[1] | condition),
                wind_speed_kmh: .hourly.wind_speed_10m[1]
            }
        }
        | select(
            (.current.time | type == "string" and length > 0)
            and (.current.temperature_c | type == "number")
            and (.current.apparent_temperature_c | type == "number")
            and (.current.precipitation_probability | type == "number")
            and (.current.weather_code | type == "number")
            and (.current.wind_speed_kmh | type == "number")
            and (.next_hour.time | type == "string" and length > 0)
            and (.next_hour.temperature_c | type == "number")
            and (.next_hour.apparent_temperature_c | type == "number")
            and (.next_hour.precipitation_probability | type == "number")
            and (.next_hour.weather_code | type == "number")
            and (.next_hour.wind_speed_kmh | type == "number")
        )
    ' <<<"$response" 2>/dev/null
}

now=$(date +%s)

if cache_is_fresh "$LOCATION_CACHE" "$LOCATION_MAX_AGE" && valid_location_file "$LOCATION_CACHE"; then
    location=$(jq -c . "$LOCATION_CACHE")
elif detected_location=$(detect_location "$now"); then
    location="$detected_location"
    atomic_write "$LOCATION_CACHE" "$location" || {
        printf 'Unable to update clock location cache\n' >&2
        exit 1
    }
elif valid_location_file "$LOCATION_CACHE"; then
    location=$(jq -c . "$LOCATION_CACHE")
else
    location=$(default_location "$now") || exit 1
    atomic_write "$LOCATION_CACHE" "$location" || {
        printf 'Unable to write default clock location cache\n' >&2
        exit 1
    }
fi

latitude=$(jq -r '.latitude' <<<"$location")
longitude=$(jq -r '.longitude' <<<"$location")

if ! weather_response=$(curl \
    --fail \
    --silent \
    --show-error \
    --connect-timeout 5 \
    --max-time 10 \
    --get "$WEATHER_URL" \
    --data-urlencode "latitude=$latitude" \
    --data-urlencode "longitude=$longitude" \
    --data-urlencode 'current=temperature_2m,apparent_temperature,precipitation_probability,weather_code,wind_speed_10m' \
    --data-urlencode 'hourly=temperature_2m,apparent_temperature,precipitation_probability,weather_code,wind_speed_10m' \
    --data-urlencode 'forecast_hours=2' \
    --data-urlencode 'timezone=auto'); then
    printf 'Unable to refresh clock weather cache\n' >&2
    exit 1
fi

if ! weather=$(normalize_weather "$weather_response" "$location" "$now"); then
    printf 'Weather provider returned an invalid response\n' >&2
    exit 1
fi

atomic_write "$WEATHER_CACHE" "$weather" || {
    printf 'Unable to update clock weather cache\n' >&2
    exit 1
}
