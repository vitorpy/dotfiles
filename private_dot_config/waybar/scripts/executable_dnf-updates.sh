#!/bin/bash

# Check for available DNF updates
updates=$(dnf check-update 2>/dev/null | grep -v gstreamer | grep -E '^[a-zA-Z]' | wc -l)

ICON=$(printf '\U00100079')

if [ "$updates" -gt 0 ]; then
    echo "{\"text\":\"$ICON $updates\", \"tooltip\":\"$updates updates available\", \"class\":\"updates-available\"}"
else
    echo "{\"text\":\"\", \"tooltip\":\"System up to date\", \"class\":\"up-to-date\"}"
fi
