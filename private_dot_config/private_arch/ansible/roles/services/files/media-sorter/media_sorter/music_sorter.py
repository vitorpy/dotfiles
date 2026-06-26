from __future__ import annotations

from pathlib import Path

from .constants import MUSIC_SIDECAR_EXTENSIONS
from .linker import link_file
from .media_files import is_audio
from .models import FileEntry, MediaLabel
from .utils import log, safe_component


def music_sidecars(entries: list[FileEntry]) -> list[FileEntry]:
    return [
        entry
        for entry in entries
        if entry.source.suffix.lower() in MUSIC_SIDECAR_EXTENSIONS
    ]



def strip_common_top_dir(entry: FileEntry, selected: list[FileEntry]) -> Path:
    selected_parts = [item.relpath.parts for item in selected if item.relpath.parts]
    if selected_parts and all(len(parts) > 1 for parts in selected_parts):
        first = selected_parts[0][0]
        if all(parts[0] == first for parts in selected_parts):
            return Path(*entry.relpath.parts[1:])
    return Path(entry.relpath.name)



def safe_relative_path(path: Path) -> Path:
    parts = [safe_component(part) for part in path.parts if part not in {"", "."}]
    if not parts:
        raise ValueError(f"unsafe relative path: {path}")
    return Path(*parts)



def sort_music(label: MediaLabel, entries: list[FileEntry], music_root: Path, dry_run: bool) -> bool:
    ok = True
    audio = [entry for entry in entries if is_audio(entry)]
    if not audio:
        log("WARNING", f"no audio files found for music={label.title!r}")
        return True
    if not label.album:
        log("WARNING", f"needs album label, skipping music artist={label.title!r}")
        return True

    dest_dir = music_root / safe_component(label.title) / safe_component(label.album)
    selected = audio + music_sidecars(entries)
    seen: set[Path] = set()
    for entry in selected:
        if entry.source in seen:
            continue
        seen.add(entry.source)
        dest_relpath = safe_relative_path(strip_common_top_dir(entry, selected))
        ok = link_file(entry.source, dest_dir / dest_relpath, dry_run) and ok
    return ok
