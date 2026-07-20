#!/bin/bash

# Automatic timezone detection based on IP geolocation
# Updates system timezone if it differs from detected location

LOG_FILE="$HOME/.local/share/auto-timezone.log"
CACHE_FILE="$HOME/.cache/detected-timezone"
MAX_AGE=3600  # Cache for 1 hour

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to check that a provider returned an installed IANA timezone name.
is_valid_timezone() {
    local tz="$1"

    if [ -z "$tz" ] || [ "$tz" = "Undefined" ]; then
        return 1
    fi

    case "$tz" in
        /*|*..*|*//*|*[[:space:]]*|*\{*|*\}*|*\'*|*\"*)
            return 1
            ;;
    esac

    [ -f "/usr/share/zoneinfo/$tz" ]
}

# Function to query one IP geolocation provider.
detect_timezone() {
    local provider="$1"
    local url="$2"
    local tz

    tz=$(curl -s --connect-timeout 5 --max-time 10 "$url" 2>/dev/null)

    if is_valid_timezone "$tz"; then
        echo "$tz"
        return 0
    fi

    if [ -n "$tz" ]; then
        log "Ignoring invalid timezone response from $provider: ${tz:0:120}"
    else
        log "No timezone response from $provider"
    fi

    return 1
}

# Function to get timezone from IP geolocation
get_timezone_from_ip() {
    # Using ipapi.co which doesn't require an API key
    detect_timezone "ipapi.co" "https://ipapi.co/timezone/" && return 0

    # Fallback to ip-api.com
    detect_timezone "ip-api.com" "http://ip-api.com/line/?fields=timezone" && return 0

    return 1
}

# Check if cache exists and is recent
if [ -f "$CACHE_FILE" ]; then
    cache_age=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))
    if [ $cache_age -lt $MAX_AGE ]; then
        cached_tz=$(cat "$CACHE_FILE")
        if is_valid_timezone "$cached_tz"; then
            log "Using cached timezone $cached_tz (age: ${cache_age}s)"
            exit 0
        fi
        log "Ignoring invalid cached timezone: ${cached_tz:0:120}"
    fi
fi

# Get current system timezone
current_tz=$(timedatectl show --property=Timezone --value)

# Detect timezone from IP
detected_tz=$(get_timezone_from_ip)

if [ -z "$detected_tz" ]; then
    log "Failed to detect timezone from IP"
    exit 1
fi

log "Detected timezone: $detected_tz (current: $current_tz)"

# Update if different
if [ "$detected_tz" != "$current_tz" ]; then
    log "Updating timezone from $current_tz to $detected_tz"

    # Update timezone
    if output=$(timedatectl set-timezone "$detected_tz" 2>&1); then
        if [ -n "$output" ]; then
            echo "$output" >> "$LOG_FILE"
        fi
        log "Timezone updated successfully"
        echo "$detected_tz" > "$CACHE_FILE"

        # Trigger waybar reload to update clock
        pkill -RTMIN+1 waybar 2>/dev/null
    else
        if [ -n "$output" ]; then
            echo "$output" >> "$LOG_FILE"
        fi
        log "Failed to update timezone"
        exit 1
    fi
else
    log "Timezone unchanged"
    echo "$detected_tz" > "$CACHE_FILE"
fi
