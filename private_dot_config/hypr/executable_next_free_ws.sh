#!/usr/bin/env bash
# Send the focused window to the next free workspace on the focused monitor.
# If that monitor has no empty workspace, create a new globally unused one so
# dual-monitor setups do not collide with workspace IDs that already exist
# elsewhere.
HYPRCTL=/usr/bin/hyprctl
JQ=/usr/bin/jq

mon_id="$($HYPRCTL monitors -j | $JQ -r '.[] | select(.focused==true) | .id')"

# Reuse an existing empty workspace on the current monitor when available.
empty_ws="$($HYPRCTL workspaces -j | $JQ -r \
  --argjson mid "$mon_id" '.[] | select(.id > 0 and .monitorID==$mid and .windows==0) | .id' | sort -n | head -n1)"

if [ -z "$empty_ws" ]; then
  # Otherwise create a workspace after the highest positive workspace ID in
  # the whole session so another monitor's workspace number is never reused.
  last="$($HYPRCTL workspaces -j | $JQ -r \
    '.[] | select(.id > 0) | .id' | sort -n | tail -n1)"
  empty_ws=$(( ${last:-0} + 1 ))
fi

# Move focused window silently, then follow it
$HYPRCTL dispatch movetoworkspacesilent "$empty_ws"
$HYPRCTL dispatch workspace "$empty_ws"
