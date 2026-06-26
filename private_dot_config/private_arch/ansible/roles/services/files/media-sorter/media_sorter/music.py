from __future__ import annotations

import argparse
import subprocess
from typing import Any

from .acoustid import acoustid_match
from .audiodb import audiodb_match
from .media_files import entries_from_record, is_audio, is_video
from .models import MatchDecision, MusicCandidate
from .music_names import music_candidates_from_text, music_label_from_text
from .utils import normalize_title


def music_match(record: dict[str, Any], args: argparse.Namespace) -> MatchDecision | None:
    entries = entries_from_record(record)
    audio = [entry for entry in entries if is_audio(entry)]
    if not audio or any(is_video(entry) for entry in entries):
        return None

    torrent_name = record["torrent"]["name"]
    candidates = [torrent_name]
    candidates.extend(entry.relpath.parts[0] for entry in audio if len(entry.relpath.parts) > 1)

    seen = set()
    for candidate in candidates:
        if candidate in seen:
            continue
        seen.add(candidate)
        label = music_label_from_text(candidate)
        if label:
            return MatchDecision(
                label,
                "matched",
                "matched via music filename heuristic",
                {
                    "provider": "filename",
                    "query": candidate,
                    "artist": label.title,
                    "album": label.album,
                    "audio_count": len(audio),
                },
            )

    music_candidates: list[MusicCandidate] = []
    seen_music_candidates = set()
    for candidate in candidates:
        for music_candidate in music_candidates_from_text(candidate):
            key = (normalize_title(music_candidate.artist), normalize_title(music_candidate.album))
            if key in seen_music_candidates:
                continue
            seen_music_candidates.add(key)
            music_candidates.append(music_candidate)

    if music_candidates:
        try:
            decision = audiodb_match(music_candidates, args)
        except Exception as exc:
            decision = MatchDecision(None, "needs_review", str(exc), {"provider": "audiodb", "query": torrent_name})
        if decision.status == "matched":
            return decision

    try:
        return acoustid_match(audio, args)
    except subprocess.TimeoutExpired as exc:
        return MatchDecision(None, "needs_review", f"fpcalc timed out: {exc}", {"provider": "acoustid", "query": torrent_name})
    except Exception as exc:
        return MatchDecision(None, "needs_review", str(exc), {"provider": "acoustid", "query": torrent_name})
