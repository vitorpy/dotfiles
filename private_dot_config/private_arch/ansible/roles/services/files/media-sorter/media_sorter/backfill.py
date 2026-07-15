from __future__ import annotations

import argparse
from pathlib import Path

from .books import book_label_from_text
from .books import book_type_from_entries
from .constants import BACKFILL_SERIES_MAP
from .media_files import collect_files
from .media_files import is_audio
from .media_files import is_book
from .media_files import is_video
from .models import FileEntry
from .models import MediaLabel
from .sorters import sort_entries
from .utils import log


def backfill_label(name: str) -> MediaLabel | None:
    for pattern, series in BACKFILL_SERIES_MAP:
        if pattern.search(name):
            return MediaLabel(kind="series", title=series)
    return None



def backfill_book_label(name: str, entries: list[FileEntry]) -> MediaLabel | None:
    books = [entry for entry in entries if is_book(entry)]
    if books and not any(is_video(entry) or is_audio(entry) for entry in entries):
        return book_label_from_text(name, book_type=book_type_from_entries(books))
    return None



def run_backfill(args: argparse.Namespace) -> int:
    source_root = Path(args.source_root)
    if not source_root.exists():
        raise RuntimeError(f"source root does not exist: {source_root}")

    ok = True
    for item in sorted(source_root.iterdir()):
        if item.name in {"films", "movies", "series", "tv"}:
            continue
        if item.is_dir() and (item / ".ignore").exists():
            log("INFO", f"backfill raw download already ignored, skipping path={item}")
            continue
        entries = collect_files(item, source_root)
        if not entries:
            log("INFO", f"backfill item has no files, skipping path={item}")
            continue
        label = backfill_label(item.name) or backfill_book_label(item.name, entries)
        if not label:
            log("INFO", f"backfill needs explicit label, skipping path={item}")
            continue
        ok = sort_entries(label, item.name, entries, args) and ok
    return 0 if ok else 1
