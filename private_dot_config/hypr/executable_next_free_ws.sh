#!/usr/bin/env bash
# ~/.config/hypr/send_to_next_free_ws.sh
HYPRCTL=/usr/bin/hyprctl
JQ=/usr/bin/jq

mon_id="$($HYPRCTL monitors -j | $JQ -r '.[] | select(.focused==true) | .id')"

# next empty ws on this monitor
empty_ws="$($HYPRCTL workspaces -j | $JQ -r \
  --argjson mid "$mon_id" '.[] | select(.monitorID==$mid and .windows==0) | .id' | sort -n | head -n1)"

if [ -z "$empty_ws" ]; then
  # make a new one after the highest existing on this monitor
  last="$($HYPRCTL workspaces -j | $JQ -r \
    --argjson mid "$mon_id" '.[] | select(.monitorID==$mid) | .id' | sort -n | tail -n1)"
  empty_ws=$(( ${last:-0} + 1 ))
fi

# Move focused window silently, then follow it
$HYPRCTL dispatch movetoworkspacesilent "$empty_ws"
$HYPRCTL dispatch workspace "$empty_ws"

