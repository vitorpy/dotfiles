from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any

from .queue import queue_dirs


def same_stat(left: dict[str, Any] | None, right: os.stat_result) -> bool:
    if not left:
        return False
    return left.get("device") == right.st_dev and left.get("inode") == right.st_ino


def load_json_records(directory: Path) -> list[dict[str, Any]]:
    if not directory.exists():
        return []
    records = []
    for path in sorted(directory.glob("*.json")):
        try:
            record = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        record["_record_path"] = str(path)
        records.append(record)
    return records


def owned_link_findings(record: dict[str, Any]) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    for link in record.get("owned_links") or []:
        source = Path(str(link.get("source") or ""))
        dest = Path(str(link.get("dest") or ""))
        source_exists = source.exists()
        dest_exists = dest.exists()
        if not dest_exists:
            findings.append({"type": "missing-dest", "record": record.get("_record_path"), "source": str(source), "dest": str(dest)})
            continue
        if not source_exists:
            findings.append({"type": "missing-source", "record": record.get("_record_path"), "source": str(source), "dest": str(dest)})
            continue
        try:
            if os.path.samefile(source, dest):
                continue
        except OSError:
            pass

        dest_stat = dest.stat()
        if same_stat(link.get("dest_stat"), dest_stat):
            findings.append({"type": "stale-owned-link", "record": record.get("_record_path"), "source": str(source), "dest": str(dest)})
        else:
            findings.append({"type": "wrong-dest-inode", "record": record.get("_record_path"), "source": str(source), "dest": str(dest)})
    return findings


def collect_audit(args: argparse.Namespace) -> tuple[dict[str, int], list[dict[str, Any]]]:
    dirs = queue_dirs(Path(args.queue_root))
    counts = {name: len(list(path.glob("*.json"))) if path.exists() else 0 for name, path in dirs.items()}
    findings: list[dict[str, Any]] = []
    for record in load_json_records(dirs["done"]):
        findings.extend(owned_link_findings(record))
    return counts, findings


def print_audit(args: argparse.Namespace) -> int:
    counts, findings = collect_audit(args)
    print("queue counts:")
    for name in ("queue", "done", "needs_review", "ignored", "failed"):
        print(f"  {name}: {counts.get(name, 0)}")
    print(f"owned-link findings: {len(findings)}")
    for finding in findings:
        print(f"- {finding['type']}: {finding['dest']}")
        print(f"  source: {finding['source']}")
        print(f"  record: {finding['record']}")
    return 0 if not findings else 1


def reconcile(args: argparse.Namespace) -> int:
    _counts, findings = collect_audit(args)
    stale = [finding for finding in findings if finding["type"] == "stale-owned-link"]
    print(f"mode={'apply' if args.apply else 'dry-run'}")
    print(f"stale-owned-links={len(stale)}")
    for finding in stale:
        print(f"- {finding['dest']}")
        if args.apply:
            Path(finding["dest"]).unlink()
    return 0
