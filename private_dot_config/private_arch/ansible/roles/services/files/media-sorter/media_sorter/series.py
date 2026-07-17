from __future__ import annotations

import re
from pathlib import Path

from .constants import USEFUL_SIDECAR_EXTENSIONS
from .media_files import extra_video_folder, is_episode_zero_video, is_special_video, is_video, season_from_entry
from .models import FileEntry, MediaLabel
from .planner import SortPlan, apply_plan, preflight_plan
from .utils import first_not_none, log, parse_season, safe_component


def same_stem_sidecars(video: FileEntry, entries: list[FileEntry]) -> list[FileEntry]:
    return [
        entry
        for entry in entries
        if entry.source.suffix.lower() in USEFUL_SIDECAR_EXTENSIONS
        and entry.relpath.parent == video.relpath.parent
        and entry.source.stem == video.source.stem
    ]



def jellyfin_series_name(filename: str, season: int | None = None) -> str:
    filename = re.sub(
        r"(?i)\bS(\d{1,2})E(\d{1,3})((?:E\d{1,3})+)\b",
        lambda match: f"S{int(match.group(1)):02d}E{int(match.group(2)):02d}"
        + "".join(f"-E{int(episode):02d}" for episode in re.findall(r"(?i)E(\d{1,3})", match.group(3))),
        filename,
    )
    filename = re.sub(
        r"(?i)(?<![A-Z0-9])(\d{1,2})x(\d{1,3})(?![A-Z0-9])",
        lambda match: f"S{int(match.group(1)):02d}E{int(match.group(2)):02d}",
        filename,
    )
    if season is None:
        return filename
    filename = re.sub(
        r"(?i)^(\d{1,2})(\d{2})(?=[ ._-])",
        lambda match: f"S{season:02d}E{int(match.group(2)):02d}"
        if int(match.group(1)) == season
        else match.group(0),
        filename,
        count=1,
    )
    filename = re.sub(
        r"(?i)(?<![A-Z0-9-])E(\d{1,3})(?![A-Z0-9])",
        lambda match: f"S{season:02d}E{int(match.group(1)):02d}",
        filename,
    )
    if not re.search(r"(?i)Season[ ._-]*\d{1,2}[ ._-]*Episode[ ._-]*\d{1,3}", filename):
        filename = re.sub(
            r"(?i)(?<![A-Z0-9])Episode[ ._-]*(\d{1,3})(?![A-Z0-9])",
            lambda match: f"S{season:02d}E{int(match.group(1)):02d}",
            filename,
        )
    return re.sub(
        r"(?i)([ ._]*-[ ._]*)(\d{1,3})(?![A-Z0-9])",
        lambda match: f"{match.group(1)}S{season:02d}E{int(match.group(2)):02d}",
        filename,
        count=1,
    )



def plan_series(label: MediaLabel, torrent_name: str, entries: list[FileEntry], series_root: Path) -> SortPlan:
    plan = SortPlan(label_kind=label.kind, label_title=label.title, torrent_name=torrent_name)
    videos = [entry for entry in entries if is_video(entry)]
    if not videos:
        plan.warnings.append(f"no video files found for series={label.title!r}")
        return plan

    for video in videos:
        special_video = is_special_video(video)
        episode_zero_video = is_episode_zero_video(video)
        extra_folder = extra_video_folder(video)
        if special_video:
            extra_folder = "extras"
        season = (
            0
            if episode_zero_video
            else first_not_none(season_from_entry(video), parse_season(torrent_name), label.season)
        )
        if season is None and not special_video:
            plan.errors.append(f"needs season label, skipping source={video.source} series={label.title!r}")
            continue

        dest_dir = series_root / safe_component(label.title)
        if season is not None:
            dest_dir = dest_dir / f"Season {season:02d}"
        if extra_folder:
            dest_dir = dest_dir / extra_folder

        video_dest_name = video.source.name if special_video or extra_folder else jellyfin_series_name(video.source.name, season)
        plan.add(video.source, dest_dir / video_dest_name, "video", required=True)

        for sidecar in same_stem_sidecars(video, entries):
            sidecar_dest_name = Path(video_dest_name).with_suffix(sidecar.source.suffix).name
            plan.add(sidecar.source, dest_dir / sidecar_dest_name, "sidecar", required=False)

    return plan


def sort_series(label: MediaLabel, torrent_name: str, entries: list[FileEntry], series_root: Path, dry_run: bool) -> bool:
    plan = plan_series(label, torrent_name, entries, series_root)
    preflight = preflight_plan(plan, [series_root])
    for warning in preflight.warnings:
        log("WARNING", warning)
    for reason in preflight.reasons:
        log("ERROR", reason)
    if not preflight.ok:
        return False
    ok, _owned_links = apply_plan(plan, preflight, dry_run)
    return ok
