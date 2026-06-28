from __future__ import annotations

import re
from pathlib import Path

from .constants import USEFUL_SIDECAR_EXTENSIONS
from .linker import link_file
from .media_files import extra_video_folder, is_special_video, is_video, season_from_entry
from .models import FileEntry, MediaLabel
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
    return re.sub(
        r"(?i)(?<![A-Z0-9-])E(\d{1,3})(?![A-Z0-9])",
        lambda match: f"S{season:02d}E{int(match.group(1)):02d}",
        filename,
    )



def sort_series(label: MediaLabel, torrent_name: str, entries: list[FileEntry], series_root: Path, dry_run: bool) -> bool:
    ok = True
    videos = [entry for entry in entries if is_video(entry)]
    if not videos:
        log("WARNING", f"no video files found for series={label.title!r}")
        return True

    for video in videos:
        special_video = is_special_video(video)
        extra_folder = extra_video_folder(video)
        if special_video:
            extra_folder = "extras"
        season = first_not_none(season_from_entry(video), parse_season(torrent_name), label.season)
        if season is None and not special_video:
            log("WARNING", f"needs season label, skipping source={video.source} series={label.title!r}")
            ok = False
            continue

        dest_dir = series_root / safe_component(label.title)
        if season is not None:
            dest_dir = dest_dir / f"Season {season:02d}"
        if extra_folder:
            dest_dir = dest_dir / extra_folder

        video_dest_name = jellyfin_series_name(video.source.name, season)
        ok = link_file(video.source, dest_dir / video_dest_name, dry_run) and ok

        for sidecar in same_stem_sidecars(video, entries):
            sidecar_dest_name = Path(video_dest_name).with_suffix(sidecar.source.suffix).name
            ok = link_file(sidecar.source, dest_dir / sidecar_dest_name, dry_run, required=False) and ok

    return ok
