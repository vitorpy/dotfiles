#!/bin/bash

# Get list of available sources
sources=$(pactl list short sources | grep -v ".monitor" | awk '{print $2}')

# Get current default source
current_source=$(pactl info | grep "Default Source:" | cut -d: -f2 | xargs)

# Create menu options for wofi/rofi
menu_items=""
while IFS= read -r source; do
    # Get source description
    description=$(pactl list sources | grep -A1 "Name: $source" | grep "Description:" | cut -d: -f2- | xargs)
    
    # Mark current source
    if [ "$source" = "$current_source" ]; then
        menu_items="$menu_items● $description\n"
    else
        menu_items="$menu_items  $description\n"
    fi
done <<< "$sources"

# Show menu using wofi (or rofi if you prefer)
# Try wofi first, fall back to rofi if not available
if command -v wofi &> /dev/null; then
    selected=$(echo -e "$menu_items" | wofi --dmenu --prompt "Select Audio Input" --width 600 --height 400)
elif command -v rofi &> /dev/null; then
    selected=$(echo -e "$menu_items" | rofi -dmenu -p "Select Audio Input" -width 600)
else
    # Fallback to zenity if neither wofi nor rofi is available
    selected=$(echo -e "$menu_items" | zenity --list --column="Audio Inputs" --title="Select Audio Input" --width=600 --height=400)
fi

# If user selected something
if [ -n "$selected" ]; then
    # Remove the marker (● or spaces) from the selection
    selected_clean=$(echo "$selected" | sed 's/^[● ]*//')
    
    # Find the source name from description
    while IFS= read -r source; do
        description=$(pactl list sources | grep -A1 "Name: $source" | grep "Description:" | cut -d: -f2- | xargs)
        if [ "$description" = "$selected_clean" ]; then
            # Set as default source
            pactl set-default-source "$source"
            # Move all recording streams to the new source
            pactl list short source-outputs | while read stream; do
                stream_id=$(echo $stream | awk '{print $1}')
                pactl move-source-output "$stream_id" "$source"
            done
            break
        fi
    done <<< "$sources"
fi