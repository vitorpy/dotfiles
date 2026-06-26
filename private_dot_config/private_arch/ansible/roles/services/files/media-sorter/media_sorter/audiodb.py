from __future__ import annotations

import argparse
import difflib
import json
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from .models import MatchDecision, MediaLabel, MusicCandidate
from .utils import normalize_title, safe_component


def audiodb_fixture_search(fixture_path: str, artist: str, album: str) -> dict[str, Any]:
    fixture = json.loads(Path(fixture_path).read_text(encoding="utf-8"))
    key = f"{normalize_title(artist)}\0{normalize_title(album)}"
    return fixture.get("album", {}).get(key, {"album": []})



def audiodb_search_album(args: argparse.Namespace, artist: str, album: str) -> dict[str, Any]:
    if args.audiodb_fixture_json:
        return audiodb_fixture_search(args.audiodb_fixture_json, artist, album)

    token = args.audiodb_api_key or os.environ.get("AUDIODB_API_KEY")
    if not token:
        return {"album": []}

    params = urllib.parse.urlencode({"s": artist, "a": album})
    token_path = urllib.parse.quote(str(token), safe="")
    url = f"https://www.theaudiodb.com/api/v1/json/{token_path}/searchalbum.php?{params}"
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=args.audiodb_timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise RuntimeError(f"TheAudioDB search failed for artist={artist!r} album={album!r}: {exc}") from exc



def audiodb_album_title(candidate: dict[str, Any]) -> str:
    return str(candidate.get("strAlbum") or "")



def audiodb_artist_title(candidate: dict[str, Any]) -> str:
    return str(candidate.get("strArtist") or "")



def score_audiodb_album(query: MusicCandidate, candidate: dict[str, Any]) -> float:
    artist_score = difflib.SequenceMatcher(None, normalize_title(query.artist), normalize_title(audiodb_artist_title(candidate))).ratio()
    album_score = difflib.SequenceMatcher(None, normalize_title(query.album), normalize_title(audiodb_album_title(candidate))).ratio()
    return min(1.0, (artist_score * 0.4) + (album_score * 0.6))



def ranked_audiodb_candidates(args: argparse.Namespace, query: MusicCandidate) -> list[dict[str, Any]]:
    response = audiodb_search_album(args, query.artist, query.album)
    ranked = []
    for candidate in (response.get("album") or [])[:5]:
        ranked.append(
            {
                "provider": "audiodb",
                "media_type": "album",
                "provider_id": candidate.get("idAlbum"),
                "title": audiodb_album_title(candidate),
                "artist": audiodb_artist_title(candidate),
                "year": candidate.get("intYearReleased"),
                "confidence": round(score_audiodb_album(query, candidate), 3),
                "query_artist": query.artist,
                "query_album": query.album,
                "query_source": query.source,
                "raw": candidate,
            }
        )
    return sorted(ranked, key=lambda item: item["confidence"], reverse=True)



def audiodb_match(candidates: list[MusicCandidate], args: argparse.Namespace) -> MatchDecision:
    ranked: list[dict[str, Any]] = []
    for candidate in candidates:
        ranked.extend(ranked_audiodb_candidates(args, candidate))
    ranked = sorted(ranked, key=lambda item: item["confidence"], reverse=True)
    if not ranked:
        return MatchDecision(None, "needs_review", "no TheAudioDB album candidates", {"provider": "audiodb", "candidates": []})

    top = ranked[0]
    if top["confidence"] < args.audiodb_min_confidence:
        return MatchDecision(
            None,
            "needs_review",
            "low confidence TheAudioDB album match",
            {"provider": "audiodb", "candidates": ranked[:5]},
        )

    artist = audiodb_artist_title(top["raw"]) or str(top["artist"])
    album = audiodb_album_title(top["raw"]) or str(top["title"])
    label = MediaLabel(kind="music", title=safe_component(artist), album=safe_component(album))
    return MatchDecision(
        label,
        "matched",
        "matched via TheAudioDB",
        {"provider": "audiodb", "selected": top, "candidates": ranked[:5]},
    )
