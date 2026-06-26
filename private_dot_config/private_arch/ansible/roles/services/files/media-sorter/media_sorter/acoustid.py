from __future__ import annotations

import argparse
import json
import os
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from .models import AcoustIDFingerprint, FileEntry, MatchDecision, MediaLabel
from .music_names import looks_like_single_album
from .utils import log, normalize_title, safe_component


def fpcalc_fingerprint(entry: FileEntry, args: argparse.Namespace) -> AcoustIDFingerprint | None:
    command = [args.fpcalc_path, "-json", str(entry.source)]
    result = subprocess.run(command, check=False, text=True, capture_output=True, timeout=args.acoustid_fpcalc_timeout)
    if result.returncode != 0:
        log("WARNING", f"fpcalc failed source={entry.source}: {result.stderr.strip() or result.stdout.strip()}")
        return None
    data = json.loads(result.stdout)
    fingerprint = str(data.get("fingerprint") or "").strip()
    duration_raw = data.get("duration")
    if not fingerprint or duration_raw is None:
        return None
    return AcoustIDFingerprint(entry=entry, duration=int(float(duration_raw)), fingerprint=fingerprint)



def acoustid_fixture_lookup(fixture_path: str, fingerprint: str) -> dict[str, Any]:
    fixture = json.loads(Path(fixture_path).read_text(encoding="utf-8"))
    return fixture.get("fingerprints", {}).get(fingerprint, {"status": "ok", "results": []})



def acoustid_lookup(args: argparse.Namespace, fingerprint: AcoustIDFingerprint) -> dict[str, Any]:
    if args.acoustid_fixture_json:
        return acoustid_fixture_lookup(args.acoustid_fixture_json, fingerprint.fingerprint)

    token = args.acoustid_api_key or os.environ.get("ACOUSTID_API_KEY")
    if not token:
        return {"status": "ok", "results": []}

    params = {
        "client": token,
        "duration": str(fingerprint.duration),
        "fingerprint": fingerprint.fingerprint,
        "meta": "recordings releases releasegroups compress",
    }
    request = urllib.request.Request(
        "https://api.acoustid.org/v2/lookup",
        data=urllib.parse.urlencode(params).encode("utf-8"),
        headers={"Accept": "application/json", "Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(request, timeout=args.acoustid_timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise RuntimeError(f"AcoustID lookup failed source={fingerprint.entry.source}: {exc}") from exc



def acoustid_recording_artist(recording: dict[str, Any]) -> str:
    artists = recording.get("artists") or []
    if artists:
        return str(artists[0].get("name") or "")
    return ""



def acoustid_album_candidates(response: dict[str, Any], min_score: float) -> list[dict[str, Any]]:
    candidates = []
    if response.get("status") not in {None, "ok"}:
        return candidates
    for result in response.get("results", []):
        result_score = float(result.get("score") or 0)
        if result_score < min_score:
            continue
        for recording in result.get("recordings", []):
            artist = acoustid_recording_artist(recording)
            for release_group in recording.get("releasegroups", []) or []:
                title = str(release_group.get("title") or "")
                if not artist or not title:
                    continue
                candidates.append(
                    {
                        "provider": "acoustid",
                        "media_type": "album",
                        "provider_id": release_group.get("id"),
                        "title": title,
                        "artist": artist,
                        "confidence": result_score,
                        "recording": recording.get("title"),
                        "raw": release_group,
                    }
                )
            for release in recording.get("releases", []) or []:
                title = str(release.get("title") or "")
                if not artist or not title:
                    continue
                candidates.append(
                    {
                        "provider": "acoustid",
                        "media_type": "album",
                        "provider_id": release.get("id"),
                        "title": title,
                        "artist": artist,
                        "confidence": result_score,
                        "recording": recording.get("title"),
                        "raw": release,
                    }
                )
    return candidates



def acoustid_match(audio: list[FileEntry], args: argparse.Namespace) -> MatchDecision:
    if not looks_like_single_album(audio):
        return MatchDecision(
            None,
            "needs_review",
            "multi-album music pack needs explicit review",
            {"provider": "acoustid", "audio_count": len(audio)},
        )

    if not args.acoustid_api_key and not os.environ.get("ACOUSTID_API_KEY") and not args.acoustid_fixture_json:
        return MatchDecision(None, "needs_review", "ACOUSTID_API_KEY is not set", {"provider": "acoustid"})

    votes: dict[tuple[str, str], dict[str, Any]] = {}
    sampled = 0
    for entry in audio[: args.acoustid_max_tracks]:
        fingerprint = fpcalc_fingerprint(entry, args)
        if not fingerprint:
            continue
        sampled += 1
        if sampled > 1 and not args.acoustid_fixture_json and args.acoustid_request_delay > 0:
            time.sleep(args.acoustid_request_delay)
        response = acoustid_lookup(args, fingerprint)
        for candidate in acoustid_album_candidates(response, args.acoustid_min_score):
            key = (normalize_title(candidate["artist"]), normalize_title(candidate["title"]))
            vote = votes.setdefault(
                key,
                {
                    **candidate,
                    "score_total": 0.0,
                    "track_count": 0,
                    "sources": [],
                },
            )
            vote["score_total"] += float(candidate["confidence"])
            vote["track_count"] += 1
            vote["sources"].append(str(entry.relpath))

    if not votes:
        return MatchDecision(
            None,
            "needs_review",
            "no AcoustID album candidates",
            {"provider": "acoustid", "sampled_tracks": sampled},
        )

    ranked = sorted(
        votes.values(),
        key=lambda item: (item["track_count"], item["score_total"]),
        reverse=True,
    )
    top = ranked[0]
    runner_up_tracks = ranked[1]["track_count"] if len(ranked) > 1 else 0
    if top["track_count"] < args.acoustid_min_tracks or top["track_count"] == runner_up_tracks:
        return MatchDecision(
            None,
            "needs_review",
            "ambiguous AcoustID album match",
            {"provider": "acoustid", "candidates": ranked[:5], "sampled_tracks": sampled},
        )

    label = MediaLabel(kind="music", title=safe_component(top["artist"]), album=safe_component(top["title"]))
    return MatchDecision(
        label,
        "matched",
        "matched via AcoustID fingerprint",
        {"provider": "acoustid", "selected": top, "candidates": ranked[:5], "sampled_tracks": sampled},
    )
