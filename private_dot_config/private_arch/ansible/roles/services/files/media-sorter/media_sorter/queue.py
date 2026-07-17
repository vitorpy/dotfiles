from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path
from typing import Any

from .books import book_match
from .grok import review_plan_with_grok
from .labels import normalize_labels, parse_label
from .media_files import entries_from_record, file_records, record_item_kind
from .models import FileEntry, MatchDecision
from .music import music_match
from .planner import apply_plan, plan_to_record, preflight_plan, preflight_to_record
from .raw_ignore import write_raw_ignore
from .sorters import plan_entries
from .tmdb import tmdb_match
from .transmission import download_key, files_from_torrent, load_transmission_metadata, torrent_hash, transmission_torrent
from .utils import log, now_ts, send_telegram_notification


def key_filename(key: str) -> str:
    return key.replace(":", "_")



def queue_dirs(queue_root: Path) -> dict[str, Path]:
    return {
        "queue": queue_root / "queue",
        "done": queue_root / "done",
        "needs_review": queue_root / "needs-review",
        "ignored": queue_root / "ignored",
        "failed": queue_root / "failed",
    }



def ensure_queue_dirs(queue_root: Path) -> None:
    for directory in queue_dirs(queue_root).values():
        directory.mkdir(parents=True, exist_ok=True)


def record_path(queue_root: Path, record_or_key: str) -> Path:
    raw_path = Path(record_or_key)
    if raw_path.exists():
        return raw_path

    filename = record_or_key if record_or_key.endswith(".json") else f"{key_filename(record_or_key)}.json"
    for directory in queue_dirs(queue_root).values():
        candidate = directory / filename
        if candidate.exists():
            return candidate
    raise RuntimeError(f"queue record not found: {record_or_key}")


def load_record(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def library_roots(args: argparse.Namespace) -> list[Path]:
    return [Path(args.series_root), Path(args.films_root), Path(args.music_root), Path(args.books_root)]



def atomic_write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        json.dump(data, handle, indent=2, sort_keys=True)
        handle.write("\n")
        temp_name = handle.name
    os.chmod(temp_name, 0o640)
    os.replace(temp_name, path)



def make_queue_record(torrent: dict[str, Any], name: str, download_dir: Path, entries: list[FileEntry]) -> dict[str, Any]:
    key = download_key(torrent, download_dir, name, entries)
    timestamp = now_ts()
    return {
        "schema_version": 2,
        "download_key": key,
        "created_at": timestamp,
        "updated_at": timestamp,
        "status": "queued",
        "torrent": {
            "id": torrent.get("id"),
            "hash_string": torrent_hash(torrent) or None,
            "name": name,
            "download_dir": str(download_dir),
            "labels": normalize_labels(torrent.get("labels")),
            "done_date": torrent.get("done_date") or torrent.get("doneDate"),
            "total_size": torrent.get("total_size") or torrent.get("totalSize") or torrent.get("size_when_done"),
        },
        "files": file_records(entries),
        "match": None,
        "plan": None,
        "preflight": None,
        "grok_review": None,
        "owned_links": [],
        "reason": None,
    }



def enqueue_torrent(args: argparse.Namespace) -> int:
    metadata = load_transmission_metadata(args)
    torrent = transmission_torrent(metadata)
    name, download_dir, entries = files_from_torrent(torrent, Path(args.source_root) if args.source_root else None)
    record = make_queue_record(torrent, name, download_dir, entries)
    queue_path = queue_dirs(Path(args.queue_root))["queue"] / f"{key_filename(record['download_key'])}.json"

    if queue_path.exists():
        existing = json.loads(queue_path.read_text(encoding="utf-8"))
        record["created_at"] = existing.get("created_at", record["created_at"])
    atomic_write_json(queue_path, record)
    log("INFO", f"queued torrent={name!r} key={record['download_key']} path={queue_path}")
    send_telegram_notification(f"Download complete: {name}")
    return 0



def move_record(path: Path, queue_root: Path, status: str, record: dict[str, Any]) -> None:
    record["status"] = status
    record["updated_at"] = now_ts()
    target_dir = queue_dirs(queue_root)[status]
    target = target_dir / path.name
    if path == target:
        atomic_write_json(target, record)
        return
    atomic_write_json(target, record)
    if path.exists():
        path.unlink()


def has_sortable_media(record: dict[str, Any], args: argparse.Namespace) -> bool:
    sortable_kinds = {"video", "book"}
    if args.enable_music_sorting:
        sortable_kinds.add("audio")
    return any(record_item_kind(item) in sortable_kinds for item in record.get("files", []))


def match_record(record: dict[str, Any], args: argparse.Namespace) -> MatchDecision:
    labels = normalize_labels(record["torrent"].get("labels"))
    label = parse_label(labels)
    decision = MatchDecision(label, "matched", "matched via label", {"provider": "label"}) if label else None

    if decision is None:
        decision = book_match(record, args)

    if decision is None and args.enable_music_sorting:
        decision = music_match(record, args)

    if decision is None:
        decision = tmdb_match(record, args)

    return decision



def candidate_summary(candidate: dict[str, Any]) -> str:
    media_type = candidate.get("media_type") or "unknown"
    title = candidate.get("title") or candidate.get("name") or "unknown"
    date = candidate.get("release_date") or candidate.get("first_air_date") or ""
    candidate_year = candidate.get("year") or (date[:4] if date else "")
    year = f" ({candidate_year})" if candidate_year else ""
    tmdb_id = candidate.get("provider_id") or candidate.get("id")
    confidence = candidate.get("confidence")

    if candidate.get("provider") in {"audiodb", "acoustid"} and candidate.get("artist"):
        parts = [f"{media_type}:{candidate['artist']} - {title}{year}"]
    else:
        parts = [f"{media_type}:{title}{year}"]
    if tmdb_id is not None:
        parts.append(f"id={tmdb_id}")
    if confidence is not None:
        parts.append(f"confidence={float(confidence):.3f}")
    return " ".join(parts)


def print_queue_record(path: Path, *, include_other: bool = False, max_files: int = 20) -> None:
    record = json.loads(path.read_text(encoding="utf-8"))
    torrent = record.get("torrent", {})
    match = record.get("match") or {}
    files = record.get("files", [])
    printable_files = [
        item
        for item in files
        if include_other or record_item_kind(item) in {"video", "audio", "book", "sidecar"}
    ]
    sortable_count = sum(1 for item in files if record_item_kind(item) in {"video", "audio", "book"})

    print(f"- record: {path}")
    print(f"  key: {record.get('download_key', '')}")
    print(f"  torrent: {torrent.get('name', '')}")
    print(f"  download_dir: {torrent.get('download_dir', '')}")
    print(f"  reason: {record.get('reason') or 'needs review'}")
    if match.get("query"):
        print(f"  query: {match['query']}")
    if torrent.get("labels"):
        print(f"  labels: {', '.join(normalize_labels(torrent.get('labels')))}")

    candidates = match.get("candidates") or []
    if candidates:
        print("  candidates:")
        for candidate in candidates:
            print(f"    - {candidate_summary(candidate)}")

    shown_files = printable_files[:max_files]
    suffix = f", showing {len(shown_files)}" if len(printable_files) > len(shown_files) else ""
    print(f"  files ({sortable_count} sortable / {len(files)} total{suffix}):")
    for item in shown_files:
        print(f"    - [{record_item_kind(item)}] {item.get('path', '')}")



def print_review_queue(args: argparse.Namespace) -> int:
    queue_root = Path(args.queue_root)
    review_dir = queue_dirs(queue_root)["needs_review"]
    ignored_dir = queue_dirs(queue_root)["ignored"]
    review_paths = sorted(review_dir.glob("*.json")) if review_dir.exists() else []
    ignored_paths = sorted(ignored_dir.glob("*.json")) if ignored_dir.exists() else []

    if not review_paths:
        print("needs-review queue is empty")
    else:
        print(f"needs-review: {len(review_paths)} item(s)")
        for index, path in enumerate(review_paths):
            if index:
                print()
            print_queue_record(path)

    if ignored_paths:
        if review_paths:
            print()
        print(f"ignored: {len(ignored_paths)} item(s)")
        for index, path in enumerate(ignored_paths):
            if index:
                print()
            print_queue_record(path, include_other=True)
    return 0


def ignore_record(args: argparse.Namespace) -> int:
    if not args.ignore:
        raise RuntimeError("--ignore requires a record path or queue key")

    queue_root = Path(args.queue_root)
    ensure_queue_dirs(queue_root)
    path = record_path(queue_root, args.ignore)
    record = load_record(path)
    reason = args.ignore_reason or "manually ignored"
    record["reason"] = reason
    record["match"] = record.get("match") or {"provider": "manual", "ignored": True}
    move_record(path, queue_root, "ignored", record)
    log("INFO", f"ignored key={record.get('download_key', '')} reason={reason}")
    return 0



def print_preflight(args: argparse.Namespace) -> int:
    if not args.preflight:
        raise RuntimeError("--preflight requires a record path or queue key")

    path = record_path(Path(args.queue_root), args.preflight)
    record = load_record(path)
    entries = entries_from_record(record)
    decision = match_record(record, args)
    record["reason"] = decision.reason
    record["match"] = decision.match

    if decision.status != "matched" or decision.label is None:
        record["preflight"] = {"ok": False, "reasons": [decision.reason], "warnings": [], "skipped_optional": []}
        print(json.dumps(record, indent=2, sort_keys=True))
        return 0

    plan = plan_entries(decision.label, record["torrent"]["name"], entries, args)
    preflight = preflight_plan(plan, library_roots(args))
    record["plan"] = plan_to_record(plan, preflight)
    record["preflight"] = preflight_to_record(preflight)
    print(json.dumps(record, indent=2, sort_keys=True))
    return 0



def process_queue(args: argparse.Namespace) -> int:
    queue_root = Path(args.queue_root)
    ensure_queue_dirs(queue_root)
    ok = True
    queue_paths = sorted(queue_dirs(queue_root)["queue"].glob("*.json"))
    if not queue_paths:
        log("INFO", "queue is empty")
        return 0

    for path in queue_paths:
        record = load_record(path)
        entries = entries_from_record(record)
        if not has_sortable_media(record, args):
            record["reason"] = "no sortable video or book files; music is handled by Lidarr"
            record["match"] = {"provider": "none", "ignored": True}
            log("INFO", f"ignored key={record['download_key']} reason={record['reason']}")
            if not args.dry_run:
                move_record(path, queue_root, "ignored", record)
            continue

        try:
            decision = match_record(record, args)
        except Exception as exc:
            record["reason"] = str(exc)
            log("ERROR", f"failed key={record['download_key']}: {exc}")
            if not args.dry_run:
                move_record(path, queue_root, "failed", record)
            ok = False
            continue

        record["reason"] = decision.reason
        record["match"] = decision.match
        if decision.status != "matched" or decision.label is None:
            log("WARNING", f"needs review key={record['download_key']} reason={decision.reason}")
            if not args.dry_run:
                move_record(path, queue_root, "needs_review", record)
            continue

        log("INFO", f"planning key={record['download_key']} as {decision.label.kind}:{decision.label.title}")
        plan = plan_entries(decision.label, record["torrent"]["name"], entries, args)
        preflight = preflight_plan(plan, library_roots(args))
        record["preflight"] = preflight_to_record(preflight)
        record["plan"] = plan_to_record(plan, preflight)

        for warning in preflight.warnings:
            log("WARNING", f"preflight warning key={record['download_key']}: {warning}")
        if not preflight.ok:
            record["reason"] = "preflight failed: " + "; ".join(preflight.reasons)
            log("WARNING", f"needs review key={record['download_key']} reason={record['reason']}")
            if not args.dry_run:
                move_record(path, queue_root, "needs_review", record)
            continue

        if args.grok_review:
            try:
                review = review_plan_with_grok(record, args)
            except Exception as exc:
                record["reason"] = f"Grok review failed: {exc}"
                record["grok_review"] = {"approved": False, "decision": "error", "reason": str(exc)}
                if record.get("plan"):
                    record["plan"]["grok_review_reason"] = record["reason"]
                log("WARNING", f"needs review key={record['download_key']} reason={record['reason']}")
                if not args.dry_run:
                    move_record(path, queue_root, "needs_review", record)
                continue

            record["grok_review"] = review
            if record.get("plan"):
                record["plan"]["grok_review_reason"] = review["reason"]
            if not review["approved"]:
                record["reason"] = f"Grok rejected plan: {review['reason']}"
                log("WARNING", f"needs review key={record['download_key']} reason={record['reason']}")
                if not args.dry_run:
                    move_record(path, queue_root, "needs_review", record)
                continue

        log("INFO", f"processing key={record['download_key']} as {decision.label.kind}:{decision.label.title}")
        sorted_ok, owned_links = apply_plan(plan, preflight, args.dry_run)
        record["owned_links"] = owned_links
        if sorted_ok:
            raw_ignore = write_raw_ignore(entries, Path(args.source_root), args.dry_run)
            if raw_ignore is not None:
                record["raw_ignore"] = raw_ignore
            record["reason"] = decision.reason
            if not args.dry_run:
                move_record(path, queue_root, "done", record)
        else:
            ok = False
            record["reason"] = "hardlink sorting failed"
            if not args.dry_run:
                move_record(path, queue_root, "failed", record)
    return 0 if ok else 1
