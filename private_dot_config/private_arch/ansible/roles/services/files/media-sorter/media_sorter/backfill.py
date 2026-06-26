from __future__ import annotations

import argparse
from pathlib import Path

from .constants import BACKFILL_SERIES_MAP
from .media_files import collect_files
from .models import MediaLabel
from .sorters import sort_entries
from .utils import log


def backfill_label(name: str) -> MediaLabel | None:
    for pattern, series in BACKFILL_SERIES_MAP:
        if pattern.search(name):
            return MediaLabel(kind="series", title=series)
    return None



def run_backfill(args: argparse.Namespace) -> int:
    source_root = Path(args.source_root)
    if not source_root.exists():
        raise RuntimeError(f"source root does not exist: {source_root}")

    ok = True
    for item in sorted(source_root.iterdir()):
        if item.name in {"films", "movies", "series", "tv"}:
            continue
        label = backfill_label(item.name)
        if not label:
            log("INFO", f"backfill needs explicit label, skipping path={item}")
            continue
        entries = collect_files(item, source_root)
        if not entries:
            log("INFO", f"backfill item has no files, skipping path={item}")
            continue
        ok = sort_entries(label, item.name, entries, args) and ok
    return 0 if ok else 1
