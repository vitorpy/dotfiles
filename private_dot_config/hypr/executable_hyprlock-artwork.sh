#!/usr/bin/env bash

# Render the current wallpaper's title and creator as safe Pango markup.
# Hyprlock treats an empty result as a hidden label.

metadata_file="${ARTS_WALLPAPER_METADATA:-${XDG_DATA_HOME:-$HOME/.local/share}/arts-wallpaper/current.json}"

[[ -r "$metadata_file" ]] || exit 0

jq -er '
    def nonempty_string:
        type == "string" and length > 0;

    def clipped($limit):
        if length > $limit then .[0:($limit - 1)] + "…" else . end;

    if type != "object" or (.title | nonempty_string | not) then
        empty
    else
        "<span line_height=\"39936\"><b>\(.title | clipped(72) | @html)</b></span>"
        + (if .creator | nonempty_string
            then "\n<span size=\"smaller\" foreground=\"#d7d7d7\">\(.creator | clipped(56) | @html)</span>"
            else ""
        end)
    end
' "$metadata_file" 2>/dev/null || true
