#!/usr/bin/env bash

# Render the current wallpaper's title and creator as safe Pango markup.
# Each line is ellipsized to the card's 496px content width (544px - 2x24px).
# Hyprlock treats an empty result as a hidden label.

metadata_file="${ARTS_WALLPAPER_METADATA:-${XDG_DATA_HOME:-$HOME/.local/share}/arts-wallpaper/current.json}"

[[ -r "$metadata_file" ]] || exit 0

python3 - "$metadata_file" 2>/dev/null <<'PY' || true
import html
import json
import sys

import cairo
import gi

gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Pango, PangoCairo

FONT = "Avenir Next M for BBG Medium 20"
MAX_WIDTH = 496
ELLIPSIS = "…"


def title_markup(text):
    return f'<span line_height="39936"><b>{html.escape(text)}</b></span>'


def creator_markup(text):
    return f'<span size="smaller" foreground="#d7d7d7">{html.escape(text)}</span>'


surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1)
layout = PangoCairo.create_layout(cairo.Context(surface))
layout.set_font_description(Pango.FontDescription(FONT))


def width(text, markup):
    layout.set_markup(markup(text), -1)
    return layout.get_pixel_size().width


def ellipsize(text, markup):
    if width(text, markup) <= MAX_WIDTH:
        return text

    low, high = 0, len(text)
    while low < high:
        midpoint = (low + high + 1) // 2
        candidate = text[:midpoint].rstrip() + ELLIPSIS
        if width(candidate, markup) <= MAX_WIDTH:
            low = midpoint
        else:
            high = midpoint - 1

    result = text[:low].rstrip() + ELLIPSIS
    while low > 0 and width(result, markup) > MAX_WIDTH:
        low -= 1
        result = text[:low].rstrip() + ELLIPSIS

    return result


try:
    with open(sys.argv[1], encoding="utf-8") as metadata_stream:
        metadata = json.load(metadata_stream)

    if not isinstance(metadata, dict):
        raise ValueError("metadata is not an object")

    title = metadata.get("title")
    if not isinstance(title, str) or not title:
        raise ValueError("metadata has no title")

    output = title_markup(ellipsize(title, title_markup))
    creator = metadata.get("creator")
    if isinstance(creator, str) and creator:
        output += "\n" + creator_markup(ellipsize(creator, creator_markup))

    sys.stdout.write(output)
except (OSError, UnicodeError, ValueError, json.JSONDecodeError):
    pass
PY
