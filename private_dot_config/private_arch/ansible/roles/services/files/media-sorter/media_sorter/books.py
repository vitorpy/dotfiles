from __future__ import annotations

import argparse
import re
from pathlib import Path
from typing import Any

from .constants import BOOK_EXTENSIONS, BOOK_SIDECAR_EXTENSIONS, COMIC_EXTENSIONS
from .media_files import entries_from_record, is_audio, is_book, is_video
from .models import FileEntry, MatchDecision, MediaLabel
from .planner import SortPlan, apply_plan, preflight_plan
from .utils import log, safe_component, strip_bracketed


def book_label_from_text(value: str, book_type: str = "book") -> MediaLabel | None:
    cleaned = Path(value).stem if Path(value).suffix.lower() in BOOK_EXTENSIONS else value
    cleaned = strip_bracketed(cleaned)
    cleaned = re.sub(r"[\._]+", " ", cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned).strip(" -_.")
    if not cleaned:
        return None
    return MediaLabel(kind="book", title=safe_component(cleaned), book_type=book_type)


def book_type_from_entries(entries: list[FileEntry]) -> str:
    if any(entry.source.suffix.lower() in COMIC_EXTENSIONS for entry in entries):
        return "comic"
    return "book"


def book_type_folder(label: MediaLabel) -> str:
    if label.book_type == "comic":
        return "Comics"
    return "Books"


def book_sidecars(entries: list[FileEntry]) -> list[FileEntry]:
    return [entry for entry in entries if entry.source.suffix.lower() in BOOK_SIDECAR_EXTENSIONS]


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


def plan_books(label: MediaLabel, entries: list[FileEntry], books_root: Path, torrent_name: str = "") -> SortPlan:
    plan = SortPlan(label_kind=label.kind, label_title=label.title, torrent_name=torrent_name)
    books = [entry for entry in entries if is_book(entry)]
    if not books:
        plan.warnings.append(f"no book files found for book={label.title!r}")
        return plan

    dest_dir = books_root / book_type_folder(label) / safe_component(label.title)
    selected = books + book_sidecars(entries)
    seen: set[Path] = set()
    for entry in selected:
        if entry.source in seen:
            continue
        seen.add(entry.source)
        dest_relpath = safe_relative_path(strip_common_top_dir(entry, selected))
        book_entry = is_book(entry)
        plan.add(entry.source, dest_dir / dest_relpath, "book" if book_entry else "sidecar", required=book_entry)
    return plan


def sort_books(label: MediaLabel, entries: list[FileEntry], books_root: Path, dry_run: bool) -> bool:
    plan = plan_books(label, entries, books_root)
    preflight = preflight_plan(plan, [books_root])
    for warning in preflight.warnings:
        log("WARNING", warning)
    for reason in preflight.reasons:
        log("ERROR", reason)
    if not preflight.ok:
        return False
    ok, _owned_links = apply_plan(plan, preflight, dry_run)
    return ok


def book_match(record: dict[str, Any], args: argparse.Namespace) -> MatchDecision | None:
    entries = entries_from_record(record)
    books = [entry for entry in entries if is_book(entry)]
    if not books or any(is_video(entry) or is_audio(entry) for entry in entries):
        return None

    torrent_name = record["torrent"]["name"]
    candidates = [torrent_name]
    candidates.extend(entry.relpath.parts[0] for entry in books if len(entry.relpath.parts) > 1)
    candidates.extend(entry.relpath.stem for entry in books)

    seen: set[str] = set()
    for candidate in candidates:
        if candidate in seen:
            continue
        seen.add(candidate)
        label = book_label_from_text(candidate, book_type=book_type_from_entries(books))
        if label:
            return MatchDecision(
                label,
                "matched",
                "matched via book filename heuristic",
                {
                    "provider": "filename",
                    "query": candidate,
                    "book_count": len(books),
                },
            )
    return MatchDecision(None, "needs_review", "could not infer book title", {"provider": "filename", "query": torrent_name})
