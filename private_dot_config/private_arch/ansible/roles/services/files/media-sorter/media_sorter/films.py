from __future__ import annotations

from pathlib import Path

from .constants import MOVIE_EXTRA_VIDEO_PATTERNS, USEFUL_SIDECAR_EXTENSIONS
from .linker import link_file
from .media_files import extra_video_folder, is_video
from .models import FileEntry, MediaLabel
from .utils import log, safe_component


def film_sidecars(entries: list[FileEntry]) -> list[FileEntry]:
    return [
        entry
        for entry in entries
        if entry.source.suffix.lower() in USEFUL_SIDECAR_EXTENSIONS
        and not entry.source.name.lower().endswith(".txt")
    ]


def same_stem_sidecars(video: FileEntry, entries: list[FileEntry]) -> list[FileEntry]:
    return [
        entry
        for entry in entries
        if entry.source.suffix.lower() in USEFUL_SIDECAR_EXTENSIONS
        and entry.relpath.parent == video.relpath.parent
        and entry.source.stem == video.source.stem
    ]


def entry_size(entry: FileEntry) -> int:
    try:
        return entry.source.stat().st_size
    except OSError:
        return 0


def movie_extra_folder(entry: FileEntry) -> str | None:
    values = [entry.source.stem, *entry.relpath.parent.parts]
    for value in values:
        for pattern, folder in MOVIE_EXTRA_VIDEO_PATTERNS:
            if pattern.search(value):
                return folder
    return extra_video_folder(entry)



def sort_film(label: MediaLabel, entries: list[FileEntry], films_root: Path, dry_run: bool) -> bool:
    ok = True
    videos = [entry for entry in entries if is_video(entry)]
    if not videos:
        log("WARNING", f"no video files found for film={label.title!r}")
        return True

    dest_dir = films_root / safe_component(label.title)
    primary_video = max(videos, key=entry_size)
    seen: set[Path] = set()
    for video in videos:
        video_dest_dir = dest_dir
        if video != primary_video:
            extra_folder = movie_extra_folder(video)
            if extra_folder:
                video_dest_dir = dest_dir / extra_folder

        if video.source in seen:
            continue
        seen.add(video.source)
        ok = link_file(video.source, video_dest_dir / video.source.name, dry_run) and ok

        for sidecar in same_stem_sidecars(video, entries):
            if sidecar.source in seen:
                continue
            seen.add(sidecar.source)
            ok = link_file(sidecar.source, video_dest_dir / sidecar.source.name, dry_run, required=False) and ok

    for sidecar in film_sidecars(entries):
        if sidecar.source in seen:
            continue
        seen.add(sidecar.source)
        ok = link_file(sidecar.source, dest_dir / sidecar.source.name, dry_run, required=False) and ok
    return ok
