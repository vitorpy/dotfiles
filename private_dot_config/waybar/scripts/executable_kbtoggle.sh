#!/usr/bin/env bash
KB="$(/usr/bin/hyprctl devices -j | /usr/bin/jq -r \
  '.keyboards[] | select(.main==true) | .name' | head -n1)"
exec /usr/bin/hyprctl switchxkblayout "$KB" next

