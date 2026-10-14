#!/bin/sh
# Avoid taking Plasma's notification bus name when both desktops are installed.
case ":${XDG_CURRENT_DESKTOP:-}:" in
    *:Hyprland:*|*:hyprland:*) exit 0 ;;
    *) exit 1 ;;
esac
