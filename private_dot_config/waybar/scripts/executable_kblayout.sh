#!/usr/bin/env bash
# Requires: jq (or gojq). Use absolute path to avoid PATH issues under Waybar.
HYPRCTL="/usr/bin/hyprctl"
JQ="/usr/bin/jq"

# Get the active keymap of the main keyboard
active="$($HYPRCTL devices -j | $JQ -r '.keyboards[] | select(.main==true) | .active_keymap' | head -n1)"

case "$active" in
  *Polish*|*Polski*|pl*) echo "PL" ;;
  *intl*|*English*|*US*) echo "EN" ;;   # shows EN for US-Intl
  *)                     echo "${active:-?}" ;;
esac

