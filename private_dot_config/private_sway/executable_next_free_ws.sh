#!/usr/bin/env bash
# Sway: Move window to next free workspace on current monitor

# Get current output
current_output=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused==true) | .name')

# Get all workspaces on current output
workspaces=$(swaymsg -t get_workspaces | jq -r --arg out "$current_output" \
  '.[] | select(.output==$out) | .num')

# Find first empty workspace or create new one
empty_ws=0
for i in {1..100}; do
  if ! echo "$workspaces" | grep -q "^$i$"; then
    empty_ws=$i
    break
  fi
done

# If no gap found, use next number after highest
if [ "$empty_ws" -eq 0 ]; then
  empty_ws=$(( $(echo "$workspaces" | sort -n | tail -n1) + 1 ))
fi

# Move window and follow it
swaymsg move container to workspace number "$empty_ws"
swaymsg workspace number "$empty_ws"
