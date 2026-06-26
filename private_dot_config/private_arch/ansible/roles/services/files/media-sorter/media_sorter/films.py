from __future__ import annotations

from pathlib import Path

from .constants import USEFUL_SIDECAR_EXTENSIONS
from .linker import link_file
from .media_files import is_video
from .models import FileEntry, MediaLabel
from .utils import log, safe_component


def film_sidecars(entries: list[FileEntry]) -> list[FileEntry]:
    return [
        entry
        for entry in entries
        if entry.source.suffix.lower() in USEFUL_SIDECAR_EXTENSIONS
        and not entry.source.name.lower().endswith(".txt")
    ]



def sort_film(label: MediaLabel, entries: list[FileEntry], films_root: Path, dry_run: bool) -> bool:
    ok = True
    videos = [entry for entry in entries if is_video(entry)]
    if not videos:
        log("WARNING", f"no video files found for film={label.title!r}")
        return True

    dest_dir = films_root / safe_component(label.title)
    selected = videos + film_sidecars(entries)
    seen: set[Path] = set()
    for entry in selected:
        if entry.source in seen:
            continue
        seen.add(entry.source)
        ok = link_file(entry.source, dest_dir / entry.source.name, dry_run) and ok
    return ok
