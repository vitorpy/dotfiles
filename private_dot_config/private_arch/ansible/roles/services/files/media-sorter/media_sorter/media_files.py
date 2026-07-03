from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from .constants import AUDIO_EXTENSIONS, EXTRA_VIDEO_PATTERNS, MUSIC_SIDECAR_EXTENSIONS, SPECIAL_VIDEO_PATTERNS, USEFUL_SIDECAR_EXTENSIONS, VIDEO_EXTENSIONS
from .models import FileEntry
from .utils import parse_season


def collect_files(path: Path, root: Path) -> list[FileEntry]:
    if path.is_file():
        return [FileEntry(relpath=path.relative_to(root), source=path)]
    entries = []
    if not path.exists():
        return entries
    for file_path in sorted(path.rglob("*")):
        if file_path.is_file():
            entries.append(FileEntry(relpath=file_path.relative_to(root), source=file_path))
    return entries



def is_video(entry: FileEntry) -> bool:
    return entry.source.suffix.lower() in VIDEO_EXTENSIONS



def is_audio(entry: FileEntry) -> bool:
    return entry.source.suffix.lower() in AUDIO_EXTENSIONS



def is_special_video(entry: FileEntry) -> bool:
    name = entry.source.stem
    return any(pattern.search(name) for pattern in SPECIAL_VIDEO_PATTERNS)


def is_episode_zero_video(entry: FileEntry) -> bool:
    name = entry.source.stem
    patterns = (
        r"(?i)(?:^|[^a-z0-9])s\d{1,2}e0{1,3}(?:[^a-z0-9]|$)",
        r"(?i)(?:^|[^a-z0-9])\d{1,2}x0{1,3}(?:[^a-z0-9]|$)",
    )
    return any(re.search(pattern, name) for pattern in patterns)



def extra_video_folder(entry: FileEntry) -> str | None:
    values = [entry.source.stem, *entry.relpath.parent.parts]
    for value in values:
        for pattern, folder in EXTRA_VIDEO_PATTERNS:
            if pattern.search(value):
                return folder
    return None



def season_from_entry(entry: FileEntry) -> int | None:
    values = [entry.relpath.name, *reversed(entry.relpath.parent.parts)]
    for value in values:
        lower = value.lower()
        if lower in {"special", "specials"}:
            return 0
        season = parse_season(value)
        if season is not None:
            return season
    return None



def file_kind(entry: FileEntry) -> str:
    suffix = entry.source.suffix.lower()
    if suffix in VIDEO_EXTENSIONS:
        return "video"
    if suffix in AUDIO_EXTENSIONS:
        return "audio"
    if suffix in USEFUL_SIDECAR_EXTENSIONS:
        return "sidecar"
    if suffix in MUSIC_SIDECAR_EXTENSIONS:
        return "sidecar"
    return "other"



def record_item_kind(item: dict[str, Any]) -> str:
    kind = item.get("kind")
    if kind and kind != "other":
        return str(kind)

    suffix = Path(str(item.get("path") or "")).suffix.lower()
    if suffix in VIDEO_EXTENSIONS:
        return "video"
    if suffix in AUDIO_EXTENSIONS:
        return "audio"
    if suffix in USEFUL_SIDECAR_EXTENSIONS or suffix in MUSIC_SIDECAR_EXTENSIONS:
        return "sidecar"
    return "other"



def file_records(entries: list[FileEntry]) -> list[dict[str, Any]]:
    records = []
    for entry in entries:
        try:
            size = entry.source.stat().st_size
        except OSError:
            size = None
        records.append(
            {
                "path": str(entry.relpath),
                "size": size,
                "kind": file_kind(entry),
            }
        )
    return records



def entries_from_record(record: dict[str, Any]) -> list[FileEntry]:
    download_dir = Path(record["torrent"]["download_dir"])
    return [
        FileEntry(relpath=Path(item["path"]), source=download_dir / item["path"])
        for item in record.get("files", [])
        if item.get("path")
    ]
