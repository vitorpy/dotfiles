from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from .models import FileEntry
from .utils import log


def is_under(path: Path, root: Path) -> bool:
    try:
        path.resolve(strict=False).relative_to(root.resolve(strict=False))
        return True
    except ValueError:
        return False


def raw_root_from_relpaths(entries: list[FileEntry], source_root: Path) -> Path | None:
    candidates = []
    for entry in entries:
        parts = entry.relpath.parts
        if len(parts) <= 1:
            return None
        candidates.append(entry.source.parents[len(parts) - 1] / parts[0])

    first = candidates[0].resolve(strict=False)
    if not all(candidate.resolve(strict=False) == first for candidate in candidates):
        return None
    if first == source_root.resolve(strict=False) or not is_under(first, source_root):
        return None
    if not first.is_dir():
        return None
    return first


def raw_root_for_entries(entries: list[FileEntry], source_root: Path) -> Path | None:
    sources = [entry.source for entry in entries]
    if not sources:
        return None

    relpath_root = raw_root_from_relpaths(entries, source_root)
    if relpath_root is not None:
        return relpath_root

    try:
        common = Path(os.path.commonpath([str(source) for source in sources]))
    except ValueError:
        return None

    raw_root = common if common.is_dir() else common.parent
    source_root = source_root.resolve(strict=False)
    raw_root = raw_root.resolve(strict=False)
    if raw_root == source_root or not is_under(raw_root, source_root):
        return None
    if not raw_root.is_dir():
        return None
    return raw_root


def ignore_file_has_star(path: Path) -> bool:
    if not path.exists():
        return False
    try:
        return any(line.strip() == "*" for line in path.read_text(encoding="utf-8").splitlines())
    except OSError:
        return False


def write_raw_ignore(entries: list[FileEntry], source_root: Path, dry_run: bool = False) -> dict[str, Any] | None:
    raw_root = raw_root_for_entries(entries, source_root)
    if raw_root is None:
        return None

    ignore_path = raw_root / ".ignore"
    record: dict[str, Any] = {"path": str(ignore_path), "raw_root": str(raw_root)}
    if ignore_file_has_star(ignore_path):
        record["status"] = "already-present"
        return record
    if dry_run:
        record["status"] = "dry-run"
        return record

    try:
        if ignore_path.exists():
            existing = ignore_path.read_text(encoding="utf-8")
            separator = "" if existing.endswith("\n") or not existing else "\n"
            ignore_path.write_text(existing + separator + "*\n", encoding="utf-8")
            record["status"] = "updated"
        else:
            ignore_path.write_text("*\n", encoding="utf-8")
            record["status"] = "created"
        log("INFO", f"wrote raw download ignore file path={ignore_path}")
    except OSError as exc:
        record["status"] = "failed"
        record["error"] = str(exc)
        log("WARNING", f"could not write raw download ignore file path={ignore_path}: {exc}")
    return record
