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

# Function to get timezone from IP geolocation
get_timezone_from_ip() {
    # Using ipapi.co which doesn't require an API key
    local tz=$(curl -s --connect-timeout 5 --max-time 10 "https://ipapi.co/timezone/" 2>/dev/null)

    if [ -n "$tz" ] && [ "$tz" != "Undefined" ]; then
        echo "$tz"
        return 0
    fi

    # Fallback to ip-api.com
    tz=$(curl -s --connect-timeout 5 --max-time 10 "http://ip-api.com/line/?fields=timezone" 2>/dev/null)

    if [ -n "$tz" ] && [ "$tz" != "Undefined" ]; then
        echo "$tz"
        return 0
    fi

    return 1
}

# Check if cache exists and is recent
if [ -f "$CACHE_FILE" ]; then
    cache_age=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))
    if [ $cache_age -lt $MAX_AGE ]; then
        log "Using cached timezone (age: ${cache_age}s)"
        exit 0
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
    timedatectl set-timezone "$detected_tz" 2>&1 | tee -a "$LOG_FILE"

    if [ $? -eq 0 ]; then
        log "Timezone updated successfully"
        echo "$detected_tz" > "$CACHE_FILE"

        # Trigger waybar reload to update clock
        pkill -RTMIN+1 waybar 2>/dev/null
    else
        log "Failed to update timezone"
        exit 1
    fi
else
    log "Timezone unchanged"
    echo "$detected_tz" > "$CACHE_FILE"
fi