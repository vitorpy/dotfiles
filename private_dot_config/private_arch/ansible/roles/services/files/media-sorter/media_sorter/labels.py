from __future__ import annotations

import re

from .models import MediaLabel
from .music_names import music_label_from_text
from .utils import safe_component


def normalize_labels(raw_labels: object) -> list[str]:
    if raw_labels is None:
        return []
    if isinstance(raw_labels, str):
        return [raw_labels]
    if isinstance(raw_labels, list):
        return [str(item) for item in raw_labels]
    return []



def parse_label(labels: list[str]) -> MediaLabel | None:
    kind = None
    title = None
    season = None
    album = None

    for label in labels:
        raw = label.strip()
        if ":" not in raw:
            continue
        prefix, value = raw.split(":", 1)
        prefix = prefix.strip().lower()
        value = value.strip()
        if prefix in {"series", "show"} and value:
            kind = "series"
            title = value
        elif prefix in {"film", "movie"} and value:
            kind = "film"
            title = value
        elif prefix == "music" and value:
            parsed = music_label_from_text(value, reject_obfuscated=False)
            if parsed:
                kind = "music"
                title = parsed.title
                album = parsed.album
        elif prefix in {"artist", "album_artist"} and value:
            kind = "music"
            title = value
        elif prefix == "album" and value:
            album = value
        elif prefix == "season" and value:
            season_match = re.search(r"\d{1,2}", value)
            if season_match:
                season = int(season_match.group(0))

    if kind == "music" and title and album:
        return MediaLabel(kind=kind, title=safe_component(title), album=safe_component(album))
    if kind and title:
        return MediaLabel(kind=kind, title=safe_component(title), season=season)
    return None
