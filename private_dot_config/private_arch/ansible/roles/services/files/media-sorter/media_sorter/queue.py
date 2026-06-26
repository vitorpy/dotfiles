from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path
from typing import Any

from .labels import normalize_labels, parse_label
from .media_files import entries_from_record, file_records, record_item_kind
from .models import FileEntry, MatchDecision
from .music import music_match
from .sorters import sort_entries
from .tmdb import tmdb_match
from .transmission import download_key, files_from_torrent, load_transmission_metadata, torrent_hash, transmission_torrent
from .utils import log, now_ts


def key_filename(key: str) -> str:
    return key.replace(":", "_")



def queue_dirs(queue_root: Path) -> dict[str, Path]:
    return {
        "queue": queue_root / "queue",
        "done": queue_root / "done",
        "needs_review": queue_root / "needs-review",
        "failed": queue_root / "failed",
    }



def ensure_queue_dirs(queue_root: Path) -> None:
    for directory in queue_dirs(queue_root).values():
        directory.mkdir(parents=True, exist_ok=True)



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
        "schema_version": 1,
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
    return 0



def move_record(path: Path, queue_root: Path, status: str, record: dict[str, Any]) -> None:
    record["status"] = status
    record["updated_at"] = now_ts()
    target_dir = queue_dirs(queue_root)[status]
    target = target_dir / path.name
    atomic_write_json(target, record)
    if path.exists():
        path.unlink()



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



def print_review_queue(args: argparse.Namespace) -> int:
    queue_root = Path(args.queue_root)
    review_dir = queue_dirs(queue_root)["needs_review"]
    review_paths = sorted(review_dir.glob("*.json")) if review_dir.exists() else []

    if not review_paths:
        print("needs-review queue is empty")
        return 0

    print(f"needs-review: {len(review_paths)} item(s)")
    for index, path in enumerate(review_paths):
        if index:
            print()

        record = json.loads(path.read_text(encoding="utf-8"))
        torrent = record.get("torrent", {})
        match = record.get("match") or {}
        files = record.get("files", [])
        media_files = [item for item in files if record_item_kind(item) in {"video", "audio", "sidecar"}]

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

        print(f"  files ({len(media_files)} media / {len(files)} total):")
        for item in media_files:
            print(f"    - [{record_item_kind(item)}] {item.get('path', '')}")
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
        record = json.loads(path.read_text(encoding="utf-8"))
        entries = entries_from_record(record)
        labels = normalize_labels(record["torrent"].get("labels"))
        label = parse_label(labels)
        decision = MatchDecision(label, "matched", "matched via label", {"provider": "label"}) if label else None

        if decision is None:
            decision = music_match(record, args)

        if decision is None:
            try:
                decision = tmdb_match(record, args)
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

        log("INFO", f"processing key={record['download_key']} as {decision.label.kind}:{decision.label.title}")
        sorted_ok = sort_entries(decision.label, record["torrent"]["name"], entries, args)
        if sorted_ok:
            if not args.dry_run:
                move_record(path, queue_root, "done", record)
        else:
            ok = False
            record["reason"] = "hardlink sorting failed"
            if not args.dry_run:
                move_record(path, queue_root, "failed", record)
    return 0 if ok else 1
