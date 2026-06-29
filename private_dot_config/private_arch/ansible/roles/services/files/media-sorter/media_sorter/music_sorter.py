from __future__ import annotations

from pathlib import Path

from .constants import MUSIC_SIDECAR_EXTENSIONS
from .media_files import is_audio
from .models import FileEntry, MediaLabel
from .planner import SortPlan, apply_plan, preflight_plan
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



def plan_music(label: MediaLabel, entries: list[FileEntry], music_root: Path, torrent_name: str = "") -> SortPlan:
    plan = SortPlan(label_kind=label.kind, label_title=label.title, torrent_name=torrent_name)
    audio = [entry for entry in entries if is_audio(entry)]
    if not audio:
        plan.warnings.append(f"no audio files found for music={label.title!r}")
        return plan
    if not label.album:
        plan.errors.append(f"needs album label, skipping music artist={label.title!r}")
        return plan

    dest_dir = music_root / safe_component(label.title) / safe_component(label.album)
    selected = audio + music_sidecars(entries)
    seen: set[Path] = set()
    for entry in selected:
        if entry.source in seen:
            continue
        seen.add(entry.source)
        dest_relpath = safe_relative_path(strip_common_top_dir(entry, selected))
        audio_entry = is_audio(entry)
        plan.add(entry.source, dest_dir / dest_relpath, "audio" if audio_entry else "sidecar", required=audio_entry)
    return plan


def sort_music(label: MediaLabel, entries: list[FileEntry], music_root: Path, dry_run: bool) -> bool:
    plan = plan_music(label, entries, music_root)
    preflight = preflight_plan(plan, [music_root])
    for warning in preflight.warnings:
        log("WARNING", warning)
    for reason in preflight.reasons:
        log("ERROR", reason)
    if not preflight.ok:
        return False
    ok, _owned_links = apply_plan(plan, preflight, dry_run)
    return ok
