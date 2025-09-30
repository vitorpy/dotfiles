#!/bin/bash

# Smart clock that shows local time + Warsaw time when traveling

WARSAW_TZ="Europe/Warsaw"

# Get current timezone
current_tz=$(timedatectl show --property=Timezone --value)

# Get local time
local_time=$(date '+%a, %d.%m %H:%M')

# Check if we're in Warsaw timezone
if [ "$current_tz" = "$WARSAW_TZ" ]; then
    # Just show local time
    echo "$local_time"
else
    # Show local time + Warsaw time in parentheses
    warsaw_time=$(TZ="$WARSAW_TZ" date '+%d.%m %H:%M')
    echo "$local_time ($warsaw_time)"
fi