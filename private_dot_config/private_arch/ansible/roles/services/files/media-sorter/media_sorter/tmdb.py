from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from .constants import GENERIC_METADATA_FOLDER_TITLES, RELEASE_TOKENS, SPECIAL_VIDEO_PATTERNS
from .media_files import entries_from_record, is_special_video, is_video, season_from_entry
from .models import MatchDecision, MediaLabel, MetadataQuery
from .utils import display_title, log, normalize_title, parse_season, safe_component, strip_bracketed


def extract_year(value: str) -> int | None:
    match = re.search(r"(?:^|[ ._\-\[(])((?:19|20)\d{2})(?:\b|[ ._\-\])])", value)
    return int(match.group(1)) if match else None



def extract_episode_range(value: str) -> tuple[int, int] | None:
    value = strip_bracketed(value)
    patterns = (
        r"(?i)(?:^|[ ._-])(?:episodes?|eps?)[ ._-]*(\d{1,3})[ ._-]*-[ ._-]*(\d{1,3})(?:\b|[ ._-])",
        r"(?i)(?:^|[ ._-])(\d{1,3})[ ._-]*-[ ._-]*(\d{1,3})(?:\b|[ ._-])",
    )
    for pattern in patterns:
        match = re.search(pattern, value)
        if not match:
            continue
        start = int(match.group(1))
        end = int(match.group(2))
        if 1 <= start < end <= 200:
            return start, end
    return None



def has_episode_numbered_videos(files: list[str]) -> bool:
    numbered = 0
    for file_name in files:
        stem = Path(file_name).stem
        if re.search(r"(?i)(?:^|[ ._\-\]])(?:e)?\d{1,3}(?:\b|[ ._\-\[])", stem):
            numbered += 1
    return numbered >= 2


def has_bare_episode_numbered_videos(files: list[str]) -> bool:
    numbers: set[int] = set()
    for file_name in files:
        stem = Path(file_name).stem
        if any(pattern.search(stem) for pattern in SPECIAL_VIDEO_PATTERNS):
            continue
        match = re.search(r"(?i)(?:^|[ ._\-\]])(\d{1,3})(?:\b|[ ._\-\[])", stem)
        if not match:
            continue
        episode = int(match.group(1))
        if 1 <= episode <= 200:
            numbers.add(episode)
    return len(numbers) >= 3 and 1 in numbers



def title_before_release_tokens(value: str) -> str:
    cleaned = strip_bracketed(value)
    cleaned = re.sub(r"(?i)\b(?:19|20)\d{2}\b.*$", "", cleaned)
    cleaned = re.sub(r"(?i)\bS\d{1,2}(?:E\d{1,3})?\b.*$", "", cleaned)
    cleaned = re.sub(r"(?i)\bSeason[ ._-]*\d{1,2}\b.*$", "", cleaned)
    cleaned = re.sub(r"(?i)(?:^|[ ._-])(?:episodes?|eps?)[ ._-]*\d{1,3}[ ._-]*-[ ._-]*\d{1,3}\b.*$", " ", cleaned)
    cleaned = re.sub(r"(?i)(?:^|[ ._-])\d{1,3}[ ._-]*-[ ._-]*\d{1,3}\b.*$", " ", cleaned)
    tokens = re.split(r"[ ._-]+", cleaned)
    kept = []
    for token in tokens:
        if not token:
            continue
        lower = token.lower()
        if lower in RELEASE_TOKENS or re.fullmatch(r"\d{3,4}p", lower):
            break
        kept.append(token)
    return display_title(" ".join(kept)) if kept else ""



def possessive_title_variant(query: str) -> str | None:
    match = re.match(r"^(.{2,80})[’']s\s+(.{2,})$", query)
    if not match:
        return None
    owner = match.group(1)
    if len(owner.split()) > 5:
        return None
    try:
        return display_title(match.group(2))
    except ValueError:
        return None



def metadata_query_variants(record: dict[str, Any], hints: dict[str, Any]) -> list[MetadataQuery]:
    files = [item["path"] for item in record.get("files", []) if item.get("kind") == "video" and item.get("path")]
    raw_candidates: list[tuple[str, str]] = [(record["torrent"]["name"], "torrent")]
    if hints.get("query"):
        raw_candidates.append((str(hints["query"]), "torrent-cleaned"))
    for file_name in files:
        file_path = Path(file_name)
        raw_candidates.append((file_path.stem, "file-stem"))
        for parent in reversed(file_path.parts[:-1]):
            raw_candidates.append((parent, "folder"))

    variants: list[MetadataQuery] = []
    seen: set[str] = set()

    def add(value: str, source: str) -> None:
        try:
            query = title_before_release_tokens(value)
        except ValueError:
            return
        key = normalize_title(query)
        if not key or key in seen:
            return
        if source == "folder" and key in GENERIC_METADATA_FOLDER_TITLES:
            return
        seen.add(key)
        variants.append(MetadataQuery(query=query, source=source))

    for value, source in raw_candidates:
        add(value, source)

    for variant in list(variants):
        possessive = possessive_title_variant(variant.query)
        if possessive:
            add(possessive, f"{variant.source}-possessive")

    return variants



def media_hints(record: dict[str, Any]) -> dict[str, Any]:
    torrent_name = record["torrent"]["name"]
    files = [item["path"] for item in record.get("files", []) if item.get("kind") == "video"]
    evidence = " ".join([torrent_name] + files)
    season = parse_season(evidence)
    episode_range = extract_episode_range(torrent_name)
    if season is None and episode_range and episode_range[0] == 1 and has_episode_numbered_videos(files):
        season = 1
    if season is None and has_bare_episode_numbered_videos(files):
        season = 1
    year = extract_year(torrent_name) or extract_year(" ".join(files))
    query = title_before_release_tokens(torrent_name)
    if not query and files:
        query = title_before_release_tokens(Path(files[0]).stem)

    if season is not None:
        preferred = "series"
    elif len(files) == 1 and year is not None:
        preferred = "film"
    else:
        preferred = "unknown"

    return {
        "query": query,
        "year": year,
        "season": season,
        "preferred": preferred,
        "video_count": len(files),
    }



def tmdb_fixture_search(fixture_path: str, media_type: str, query: str) -> dict[str, Any]:
    fixture = json.loads(Path(fixture_path).read_text(encoding="utf-8"))
    return fixture.get(media_type, {}).get(query, {"results": []})



def tmdb_fixture_alternative_titles(fixture_path: str, media_type: str, provider_id: object) -> dict[str, Any]:
    fixture = json.loads(Path(fixture_path).read_text(encoding="utf-8"))
    return fixture.get("alternative_titles", {}).get(media_type, {}).get(str(provider_id), {})



def tmdb_search(args: argparse.Namespace, media_type: str, query: str, year: int | None) -> dict[str, Any]:
    if args.tmdb_fixture_json:
        return tmdb_fixture_search(args.tmdb_fixture_json, media_type, query)

    token = args.tmdb_api_token or os.environ.get("TMDB_API_TOKEN")
    if not token:
        raise RuntimeError("TMDB_API_TOKEN is not set")

    params = {"query": query, "include_adult": "false", "language": "en-US", "page": "1"}
    if year is not None and media_type == "movie":
        params["year"] = str(year)
    if year is not None and media_type == "tv":
        params["first_air_date_year"] = str(year)
    url = f"https://api.themoviedb.org/3/search/{media_type}?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=args.tmdb_timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise RuntimeError(f"TMDB search failed for {media_type}:{query}: {exc}") from exc



def tmdb_alternative_titles(args: argparse.Namespace, media_type: str, provider_id: object) -> dict[str, Any]:
    if not provider_id:
        return {}
    if args.tmdb_fixture_json:
        return tmdb_fixture_alternative_titles(args.tmdb_fixture_json, media_type, provider_id)

    token = args.tmdb_api_token or os.environ.get("TMDB_API_TOKEN")
    if not token:
        raise RuntimeError("TMDB_API_TOKEN is not set")

    tmdb_type = "movie" if media_type == "movie" else "tv"
    url = f"https://api.themoviedb.org/3/{tmdb_type}/{provider_id}/alternative_titles"
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=args.tmdb_timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        log("WARNING", f"TMDB alternative titles failed for {media_type}:{provider_id}: {exc}")
        return {}



def candidate_title(media_type: str, candidate: dict[str, Any]) -> str:
    if media_type == "movie":
        return str(candidate.get("title") or candidate.get("original_title") or "")
    return str(candidate.get("name") or candidate.get("original_name") or "")



def alternative_title_values(response: dict[str, Any]) -> list[str]:
    values = []
    for item in response.get("titles") or response.get("results") or []:
        title = str(item.get("title") or item.get("name") or "").strip()
        if title:
            values.append(title)
    return values



def candidate_title_values(media_type: str, candidate: dict[str, Any], alternative_titles: dict[str, Any]) -> list[tuple[str, str]]:
    fields = ("title", "original_title") if media_type == "movie" else ("name", "original_name")
    values = []
    seen = set()

    def add(value: object, source: str) -> None:
        title = str(value or "").strip()
        key = normalize_title(title)
        if not key or key in seen:
            return
        seen.add(key)
        values.append((title, source))

    for field in fields:
        add(candidate.get(field), field)
    for title in alternative_title_values(alternative_titles):
        add(title, "alternative_title")
    return values



def candidate_year(media_type: str, candidate: dict[str, Any]) -> int | None:
    key = "release_date" if media_type == "movie" else "first_air_date"
    value = str(candidate.get(key) or "")
    match = re.match(r"(\d{4})", value)
    return int(match.group(1)) if match else None



def candidate_vote_count(candidate: dict[str, Any]) -> int:
    try:
        return int(candidate.get("vote_count") or 0)
    except (TypeError, ValueError):
        return 0



def candidate_popularity(candidate: dict[str, Any]) -> float:
    try:
        return float(candidate.get("popularity") or 0)
    except (TypeError, ValueError):
        return 0.0



def tmdb_candidate_sort_key(candidate: dict[str, Any]) -> tuple[float, int, float]:
    return (
        float(candidate.get("confidence") or 0),
        int(candidate.get("vote_count") or 0),
        float(candidate.get("popularity") or 0),
    )


def candidates_matching_preference(candidates: list[dict[str, Any]], hints: dict[str, Any]) -> list[dict[str, Any]]:
    preferred = hints.get("preferred")
    if preferred == "series":
        tv_candidates = [candidate for candidate in candidates if candidate.get("media_type") == "tv"]
        if tv_candidates:
            return tv_candidates
    if preferred == "film":
        movie_candidates = [candidate for candidate in candidates if candidate.get("media_type") == "movie"]
        if movie_candidates:
            return movie_candidates
    return candidates



def score_candidate(
    media_type: str,
    query: MetadataQuery,
    year: int | None,
    candidate: dict[str, Any],
    alternative_titles: dict[str, Any],
    single_result_for_query: bool,
) -> dict[str, Any]:
    query_normalized = normalize_title(query.query)
    best_title = candidate_title(media_type, candidate)
    best_source = "title"
    best_score = 0.0
    for title, source in candidate_title_values(media_type, candidate, alternative_titles):
        score = difflib.SequenceMatcher(None, query_normalized, normalize_title(title)).ratio()
        if score > best_score:
            best_title = title
            best_source = source
            best_score = score

    release_year = candidate_year(media_type, candidate)
    exact_year = year is not None and release_year == year
    year_mismatch = year is not None and release_year is not None and release_year != year
    if exact_year:
        confidence = min(1.0, best_score + 0.08)
    elif year_mismatch:
        confidence = min(best_score, 0.8)
    else:
        confidence = best_score
    if exact_year and single_result_for_query:
        confidence = max(confidence, 0.9)
    return {
        "confidence": round(confidence, 3),
        "matched_title": best_title,
        "matched_title_source": best_source,
        "title_score": round(best_score, 3),
        "year_match": exact_year,
        "year_mismatch": year_mismatch,
    }



def ranked_candidates(args: argparse.Namespace, media_type: str, query: MetadataQuery, year: int | None) -> list[dict[str, Any]]:
    response = tmdb_search(args, media_type, query.query, year)
    results = response.get("results", [])[:5]
    single_result_for_query = len(response.get("results", [])) == 1
    ranked = []
    for candidate in results:
        alternative_titles = tmdb_alternative_titles(args, media_type, candidate.get("id"))
        score = score_candidate(media_type, query, year, candidate, alternative_titles, single_result_for_query)
        ranked.append(
            {
                "provider": "tmdb",
                "media_type": media_type,
                "provider_id": candidate.get("id"),
                "title": candidate_title(media_type, candidate),
                "year": candidate_year(media_type, candidate),
                "vote_count": candidate_vote_count(candidate),
                "popularity": candidate_popularity(candidate),
                "query": query.query,
                "query_source": query.source,
                "alternative_titles": alternative_title_values(alternative_titles)[:10],
                "single_result_for_query": single_result_for_query,
                **score,
                "raw": candidate,
            }
        )
    return sorted(ranked, key=tmdb_candidate_sort_key, reverse=True)



def tmdb_vote_count_tiebreak(top: dict[str, Any], runner_up: dict[str, Any], args: argparse.Namespace) -> dict[str, Any] | None:
    top_votes = int(top.get("vote_count") or 0)
    runner_up_votes = int(runner_up.get("vote_count") or 0)
    vote_gap = top_votes - runner_up_votes
    if top_votes < args.tmdb_vote_tiebreak_min_votes:
        return None
    if vote_gap < args.tmdb_vote_tiebreak_min_gap:
        return None
    return {
        "type": "vote_count",
        "top_vote_count": top_votes,
        "runner_up_vote_count": runner_up_votes,
        "vote_gap": vote_gap,
    }



def record_has_series_season_hint(record: dict[str, Any], hints: dict[str, Any]) -> bool:
    if hints.get("season") is not None:
        return True
    torrent_name = record["torrent"]["name"]
    if parse_season(torrent_name) is not None:
        return True
    videos = [entry for entry in entries_from_record(record) if is_video(entry)]
    return any(season_from_entry(entry) is not None for entry in videos)



def tmdb_match(record: dict[str, Any], args: argparse.Namespace) -> MatchDecision:
    hints = media_hints(record)
    queries = metadata_query_variants(record, hints)
    if not queries:
        return MatchDecision(None, "needs_review", "could not derive metadata search query")

    media_types = ["movie", "tv"]
    if hints["preferred"] == "film":
        media_types = ["movie", "tv"]
    elif hints["preferred"] == "series":
        media_types = ["tv", "movie"]

    candidates: list[dict[str, Any]] = []
    for query in queries:
        for media_type in media_types:
            candidates.extend(ranked_candidates(args, media_type, query, hints["year"]))
    deduped: dict[tuple[str, object], dict[str, Any]] = {}
    for candidate in candidates:
        key = (str(candidate.get("media_type")), candidate.get("provider_id") or f"{candidate.get('title')}:{candidate.get('year')}")
        existing = deduped.get(key)
        if existing is None or tmdb_candidate_sort_key(candidate) > tmdb_candidate_sort_key(existing):
            deduped[key] = candidate
    candidates = sorted(deduped.values(), key=tmdb_candidate_sort_key, reverse=True)
    if not candidates:
        return MatchDecision(
            None,
            "needs_review",
            "no TMDB candidates",
            {"query": queries[0].query, "queries": [query.query for query in queries], "candidates": []},
        )
    candidates = candidates_matching_preference(candidates, hints)

    top = candidates[0]
    runner_up_candidate = candidates[1] if len(candidates) > 1 else None
    runner_up = runner_up_candidate["confidence"] if runner_up_candidate else 0
    tie_breaker = None
    if top["confidence"] < args.tmdb_min_confidence:
        return MatchDecision(
            None,
            "needs_review",
            "ambiguous TMDB match",
            {"query": top["query"], "queries": [query.query for query in queries], "candidates": candidates[:5]},
        )
    if top["confidence"] - runner_up < args.tmdb_min_gap:
        if runner_up_candidate:
            tie_breaker = tmdb_vote_count_tiebreak(top, runner_up_candidate, args)
        if not tie_breaker:
            return MatchDecision(
                None,
                "needs_review",
                "ambiguous TMDB match",
                {"query": top["query"], "queries": [query.query for query in queries], "candidates": candidates[:5]},
            )

    if top["media_type"] == "movie":
        label = MediaLabel(kind="film", title=safe_component(top["title"]))
    else:
        if not record_has_series_season_hint(record, hints):
            return MatchDecision(
                None,
                "needs_review",
                "series season ambiguous",
                {"query": top["query"], "queries": [query.query for query in queries], "candidates": candidates[:5], "hints": hints},
            )
        label = MediaLabel(kind="series", title=safe_component(top["title"]), season=hints["season"])
    match = {"query": top["query"], "queries": [query.query for query in queries], "selected": top, "candidates": candidates[:5], "hints": hints}
    if tie_breaker:
        match["tie_breaker"] = tie_breaker
    return MatchDecision(label, "matched", "matched via TMDB", match)
