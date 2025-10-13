#!/usr/bin/env bash
# Sway workspace navigation with auto-creation

direction="$1"  # "next" or "prev"

# Get current workspace number
current=$(swaymsg -t get_workspaces | jq -r '.[] | select(.focused==true) | .num')

if [ "$direction" = "next" ]; then
  next=$((current + 1))
  swaymsg workspace number "$next"
elif [ "$direction" = "prev" ]; then
  if [ "$current" -gt 1 ]; then
    prev=$((current - 1))
    swaymsg workspace number "$prev"
  fi
fi
