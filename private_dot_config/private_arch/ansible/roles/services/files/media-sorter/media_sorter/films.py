from __future__ import annotations

from pathlib import Path

from .constants import MOVIE_EXTRA_VIDEO_PATTERNS, USEFUL_SIDECAR_EXTENSIONS
from .media_files import extra_video_folder, is_video
from .models import FileEntry, MediaLabel
from .planner import SortPlan, apply_plan, preflight_plan
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



def plan_film(label: MediaLabel, entries: list[FileEntry], films_root: Path, torrent_name: str = "") -> SortPlan:
    plan = SortPlan(label_kind=label.kind, label_title=label.title, torrent_name=torrent_name)
    videos = [entry for entry in entries if is_video(entry)]
    if not videos:
        plan.warnings.append(f"no video files found for film={label.title!r}")
        return plan

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
        plan.add(video.source, video_dest_dir / video.source.name, "video", required=True)

        for sidecar in same_stem_sidecars(video, entries):
            if sidecar.source in seen:
                continue
            seen.add(sidecar.source)
            plan.add(sidecar.source, video_dest_dir / sidecar.source.name, "sidecar", required=False)

    for sidecar in film_sidecars(entries):
        if sidecar.source in seen:
            continue
        seen.add(sidecar.source)
        plan.add(sidecar.source, dest_dir / sidecar.source.name, "sidecar", required=False)
    return plan


def sort_film(label: MediaLabel, entries: list[FileEntry], films_root: Path, dry_run: bool) -> bool:
    plan = plan_film(label, entries, films_root)
    preflight = preflight_plan(plan, [films_root])
    for warning in preflight.warnings:
        log("WARNING", warning)
    for reason in preflight.reasons:
        log("ERROR", reason)
    if not preflight.ok:
        return False
    ok, _owned_links = apply_plan(plan, preflight, dry_run)
    return ok
