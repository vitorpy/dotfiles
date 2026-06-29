from __future__ import annotations

import argparse
from pathlib import Path

from .films import sort_film
from .films import plan_film
from .models import FileEntry, MediaLabel
from .planner import SortPlan
from .music_sorter import sort_music
from .music_sorter import plan_music
from .series import sort_series
from .series import plan_series
from .utils import log


def plan_entries(label: MediaLabel, torrent_name: str, entries: list[FileEntry], args: argparse.Namespace) -> SortPlan:
    if label.kind == "series":
        return plan_series(label, torrent_name, entries, Path(args.series_root))
    if label.kind == "film":
        return plan_film(label, entries, Path(args.films_root), torrent_name)
    if label.kind == "music":
        return plan_music(label, entries, Path(args.music_root), torrent_name)
    plan = SortPlan(label_kind=label.kind, label_title=label.title, torrent_name=torrent_name)
    plan.warnings.append(f"unsupported label kind={label.kind!r}")
    return plan


def sort_entries(label: MediaLabel, torrent_name: str, entries: list[FileEntry], args: argparse.Namespace) -> bool:
    if label.kind == "series":
        return sort_series(label, torrent_name, entries, Path(args.series_root), args.dry_run)
    if label.kind == "film":
        return sort_film(label, entries, Path(args.films_root), args.dry_run)
    if label.kind == "music":
        return sort_music(label, entries, Path(args.music_root), args.dry_run)
    log("WARNING", f"unsupported label kind={label.kind!r}")
    return True
