#!/bin/bash

# Check for available DNF updates
updates=$(dnf check-update 2>/dev/null | grep -v gstreamer | grep -E '^[a-zA-Z]' | wc -l)

if [ "$updates" -gt 0 ]; then
    echo "{\"text\":\"\\uf02d $updates\", \"tooltip\":\"$updates updates available\", \"class\":\"updates-available\"}"
else
    echo "{\"text\":\"\", \"tooltip\":\"System up to date\", \"class\":\"up-to-date\"}"
fi
