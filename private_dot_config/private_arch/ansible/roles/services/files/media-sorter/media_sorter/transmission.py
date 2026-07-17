from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
from pathlib import Path
from typing import Any

from .media_files import collect_files
from .models import FileEntry


def load_transmission_metadata(args: argparse.Namespace) -> dict[str, Any]:
    if args.metadata_json:
        with Path(args.metadata_json).open("r", encoding="utf-8") as handle:
            return json.load(handle)

    torrent_ref = args.torrent or os.environ.get("TR_TORRENT_HASH") or os.environ.get("TR_TORRENT_ID")
    if not torrent_ref:
        raise RuntimeError("missing torrent reference; TR_TORRENT_HASH was not set")

    command = [
        "transmission-remote",
        args.rpc_url,
        "-t",
        str(torrent_ref),
        "-j",
        "-i",
    ]
    result = subprocess.run(command, check=False, text=True, capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(f"transmission-remote failed: {result.stderr.strip() or result.stdout.strip()}")
    return json.loads(result.stdout)



def transmission_torrent(metadata: dict[str, Any]) -> dict[str, Any]:
    if "result" in metadata:
        torrents = metadata.get("result", {}).get("torrents", [])
        if not torrents:
            raise RuntimeError("transmission-remote returned no torrent records")
        return torrents[0]
    if "arguments" in metadata:
        torrents = metadata.get("arguments", {}).get("torrents", [])
        if not torrents:
            raise RuntimeError("transmission-remote returned no torrent records")
        return torrents[0]
    return metadata



def torrent_hash(torrent: dict[str, Any]) -> str:
    return str(torrent.get("hash_string") or torrent.get("hashString") or "").strip().lower()



def files_from_torrent(torrent: dict[str, Any], source_root: Path | None) -> tuple[str, Path, list[FileEntry]]:
    name = str(torrent.get("name") or os.environ.get("TR_TORRENT_NAME") or "torrent")
    download_dir = Path(
        torrent.get("downloadDir")
        or torrent.get("download_dir")
        or os.environ.get("TR_TORRENT_DIR")
        or source_root
        or "."
    )

    entries = []
    for item in torrent.get("files", []):
        if isinstance(item, str):
            relpath = Path(item)
        else:
            relpath = Path(str(item.get("name", "")))
        if not relpath.name:
            continue
        entries.append(FileEntry(relpath=relpath, source=download_dir / relpath))

    if not entries and source_root:
        fallback_root = source_root.resolve(strict=False)
        download_root = download_dir.resolve(strict=False)
        fallback_path = (download_dir / name).resolve(strict=False)
        try:
            fallback_path.relative_to(fallback_root)
        except ValueError as exc:
            raise RuntimeError(
                f"download path {fallback_path} is outside source root {fallback_root}; refusing fallback scan"
            ) from exc
        entries = collect_files(fallback_path, download_root)

    return name, download_dir, entries



def download_key(torrent: dict[str, Any], download_dir: Path, name: str, entries: list[FileEntry]) -> str:
    hash_string = torrent_hash(torrent)
    if hash_string:
        return f"btih:{hash_string}"

    manifest = {
        "download_dir": str(download_dir),
        "name": name,
        "files": sorted((str(entry.relpath), entry.source.stat().st_size if entry.source.exists() else None) for entry in entries),
    }
    digest = hashlib.sha256(json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
    return f"pathsha256:{digest}"
