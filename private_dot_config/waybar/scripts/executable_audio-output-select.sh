#!/bin/bash

# Get list of available sinks
sinks=$(pactl list short sinks | awk '{print $2}')

# Get current default sink
current_sink=$(pactl info | grep "Default Sink:" | cut -d: -f2 | xargs)

# Create menu options for wofi/rofi
menu_items=""
while IFS= read -r sink; do
    # Get sink description
    description=$(pactl list sinks | grep -A1 "Name: $sink" | grep "Description:" | cut -d: -f2- | xargs)
    
    # Mark current sink
    if [ "$sink" = "$current_sink" ]; then
        menu_items="$menu_items● $description\n"
    else
        menu_items="$menu_items  $description\n"
    fi
done <<< "$sinks"

# Show menu using wofi (or rofi if you prefer)
# Try wofi first, fall back to rofi if not available
if command -v wofi &> /dev/null; then
    selected=$(echo -e "$menu_items" | wofi --dmenu --prompt "Select Audio Output" --width 600 --height 400)
elif command -v rofi &> /dev/null; then
    selected=$(echo -e "$menu_items" | rofi -dmenu -p "Select Audio Output" -width 600)
else
    # Fallback to zenity if neither wofi nor rofi is available
    selected=$(echo -e "$menu_items" | zenity --list --column="Audio Outputs" --title="Select Audio Output" --width=600 --height=400)
fi

# If user selected something
if [ -n "$selected" ]; then
    # Remove the marker (● or spaces) from the selection
    selected_clean=$(echo "$selected" | sed 's/^[● ]*//')
    
    # Find the sink name from description
    while IFS= read -r sink; do
        description=$(pactl list sinks | grep -A1 "Name: $sink" | grep "Description:" | cut -d: -f2- | xargs)
        if [ "$description" = "$selected_clean" ]; then
            # Set as default sink
            pactl set-default-sink "$sink"
            # Move all playing streams to the new sink
            pactl list short sink-inputs | while read stream; do
                stream_id=$(echo $stream | awk '{print $1}')
                pactl move-sink-input "$stream_id" "$sink"
            done
            break
        fi
    done <<< "$sinks"
fi