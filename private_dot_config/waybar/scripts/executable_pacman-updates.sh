#!/bin/bash

# Check for available pacman and AUR updates
# Counts updates from official repos and AUR separately

# Check official repo updates
if command -v checkupdates &>/dev/null; then
    official_updates=$(checkupdates 2>/dev/null | wc -l)
else
    # Fallback if pacman-contrib not installed
    official_updates=$(pacman -Qu 2>/dev/null | wc -l)
fi

# Check AUR updates (if yay is available)
if command -v yay &>/dev/null; then
    aur_updates=$(yay -Qua 2>/dev/null | wc -l)
else
    aur_updates=0
fi

# Total updates
total_updates=$((official_updates + aur_updates))

if [ "$total_updates" -gt 0 ]; then
    if [ "$aur_updates" -gt 0 ]; then
        tooltip="$official_updates official, $aur_updates AUR updates"
    else
        tooltip="$official_updates updates available"
    fi
    echo "{\"text\":\"\\uf02d $total_updates\", \"tooltip\":\"$tooltip\", \"class\":\"updates-available\"}"
else
    echo "{\"text\":\"\", \"tooltip\":\"System up to date\", \"class\":\"up-to-date\"}"
fi
