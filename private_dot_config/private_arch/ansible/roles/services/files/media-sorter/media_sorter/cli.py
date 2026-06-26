from __future__ import annotations

import argparse
from pathlib import Path

from .backfill import run_backfill
from .labels import normalize_labels, parse_label
from .queue import enqueue_torrent, print_review_queue, process_queue
from .sorters import sort_entries
from .transmission import files_from_torrent, load_transmission_metadata, transmission_torrent
from .utils import log


DESCRIPTION = "Transmission media sorter hook and queue processor."


def run_direct_sort(args: argparse.Namespace) -> int:
    metadata = load_transmission_metadata(args)
    torrent = transmission_torrent(metadata)
    labels = normalize_labels(torrent.get("labels"))
    if args.label:
        labels.extend(args.label)

    torrent_name, _download_dir, entries = files_from_torrent(torrent, Path(args.source_root) if args.source_root else None)
    label = parse_label(labels)
    if not label:
        log("WARNING", f"needs label, leaving in downloads torrent={torrent_name!r} labels={labels!r}")
        return 0
    if not entries:
        log("WARNING", f"no torrent files found, leaving in downloads torrent={torrent_name!r}")
        return 0
    return 0 if sort_entries(label, torrent_name, entries, args) else 1



def parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=DESCRIPTION)
    parser.add_argument("torrent", nargs="?", help="Transmission torrent id or hash; defaults to TR_TORRENT_HASH")
    parser.add_argument("--rpc-url", default="127.0.0.1:9091")
    parser.add_argument("--series-root", default="/mnt/media/series")
    parser.add_argument("--films-root", default="/mnt/media/films")
    parser.add_argument("--music-root", default="/mnt/media/music")
    parser.add_argument("--source-root", default="/mnt/media/downloads")
    parser.add_argument("--queue-root", default="/var/lib/transmission/media-sorter")
    parser.add_argument("--metadata-json", help="test helper: read Transmission JSON from this file")
    parser.add_argument("--tmdb-fixture-json", help="test helper: read TMDB search responses from this file")
    parser.add_argument("--tmdb-api-token", help="TMDB v4 API read token; defaults to TMDB_API_TOKEN")
    parser.add_argument("--tmdb-timeout", type=float, default=10.0)
    parser.add_argument("--tmdb-min-confidence", type=float, default=0.86)
    parser.add_argument("--tmdb-min-gap", type=float, default=0.07)
    parser.add_argument("--tmdb-vote-tiebreak-min-votes", type=int, default=25)
    parser.add_argument("--tmdb-vote-tiebreak-min-gap", type=int, default=25)
    parser.add_argument("--audiodb-fixture-json", help="test helper: read TheAudioDB search responses from this file")
    parser.add_argument("--audiodb-api-key", help="TheAudioDB v1 API key; defaults to AUDIODB_API_KEY")
    parser.add_argument("--audiodb-timeout", type=float, default=10.0)
    parser.add_argument("--audiodb-min-confidence", type=float, default=0.78)
    parser.add_argument("--acoustid-fixture-json", help="test helper: read AcoustID lookup responses from this file")
    parser.add_argument("--acoustid-api-key", help="AcoustID application API key; defaults to ACOUSTID_API_KEY")
    parser.add_argument("--acoustid-timeout", type=float, default=10.0)
    parser.add_argument("--acoustid-fpcalc-timeout", type=float, default=20.0)
    parser.add_argument("--acoustid-request-delay", type=float, default=0.35)
    parser.add_argument("--acoustid-min-score", type=float, default=0.85)
    parser.add_argument("--acoustid-min-tracks", type=int, default=1)
    parser.add_argument("--acoustid-max-tracks", type=int, default=5)
    parser.add_argument("--fpcalc-path", default="fpcalc")
    parser.add_argument("--label", action="append", default=[], help="manual override label, e.g. series:South Park")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--queue", action="store_true", help="print downloads waiting for human review")
    parser.add_argument("--process-queue", action="store_true")
    parser.add_argument("--backfill-current-downloads", action="store_true")
    parser.add_argument("--apply", action="store_true", help="accepted for explicit backfill apply mode")
    return parser



def main() -> int:
    args = parser().parse_args()
    try:
        if args.queue:
            return print_review_queue(args)
        if args.backfill_current_downloads:
            if not args.apply:
                args.dry_run = True
            return run_backfill(args)
        if args.process_queue:
            return process_queue(args)
        if args.label:
            return run_direct_sort(args)
        return enqueue_torrent(args)
    except Exception as exc:
        log("ERROR", str(exc))
        return 1
