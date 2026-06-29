from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

from media_sorter.labels import parse_label
from media_sorter.media_files import is_special_video, season_from_entry
from media_sorter.models import FileEntry
from media_sorter.music_names import music_candidates_from_text, music_label_from_text
from media_sorter.series import jellyfin_series_name
from media_sorter.tmdb import (
    candidates_matching_preference,
    media_hints,
    metadata_query_variants,
    record_has_series_season_hint,
    tmdb_vote_count_tiebreak,
)
from media_sorter.utils import parse_season


def video_record(path: str) -> dict[str, str]:
    return {"kind": "video", "path": path}


def queue_record(name: str, *files: dict[str, str]) -> dict[str, object]:
    return {
        "torrent": {"name": name, "download_dir": "/tmp/downloads"},
        "files": list(files),
    }


def test_parse_season_variants() -> None:
    assert parse_season("Show.S01E02.1080p.WEBRip") == 1
    assert parse_season("Show Season 12 Episode 03") == 12
    assert parse_season("Show 3x04") == 3
    assert parse_season("Show E04") is None


def test_special_opening_videos_are_detected_without_season() -> None:
    clean_op = FileEntry(
        relpath=Path("Show/Show Clean OP.mkv"),
        source=Path("/tmp/downloads/Show/Show Clean OP.mkv"),
    )
    assert is_special_video(clean_op)
    assert season_from_entry(clean_op) is None


def test_jellyfin_series_name_adds_known_season_to_e_only_names() -> None:
    assert jellyfin_series_name("Show E01 Title.mkv", 1) == "Show S01E01 Title.mkv"
    assert jellyfin_series_name("Show E26 Finale.mkv", 12) == "Show S12E26 Finale.mkv"
    assert jellyfin_series_name("Show S01E01E02 Pilot.mkv", 1) == "Show S01E01-E02 Pilot.mkv"
    assert jellyfin_series_name("Show 5x01 Title.mkv") == "Show S05E01 Title.mkv"
    assert jellyfin_series_name("Show - 01 Title.mkv", 1) == "Show - S01E01 Title.mkv"


def test_episode_range_pack_can_infer_season_one() -> None:
    record = queue_record(
        "[Kanavid] Serial Experiments Lain 1-13(END) [BD][1080p][AAC][MP4]",
        video_record("[Kanavid] Serial Experiments Lain - 01 [BD][1080p][AAC].mp4"),
        video_record("[Kanavid] Serial Experiments Lain - 02 [BD][1080p][AAC].mp4"),
    )
    hints = media_hints(record)
    assert hints["season"] == 1
    assert hints["preferred"] == "series"
    assert record_has_series_season_hint(record, hints)


def test_bare_numbered_pack_can_infer_season_one_without_extras_query() -> None:
    record = queue_record(
        "[SNSbu] Long Riders! (BD 1920x1080 HEVC FLAC)",
        video_record("[SNSbu] Long Riders! (BD 1920x1080 HEVC FLAC)/Extras/[SNSbu] Long Riders! - NCOP 01 (BD 1920x1080 HEVC FLAC).mkv"),
        video_record("[SNSbu] Long Riders! (BD 1920x1080 HEVC FLAC)/[SNSbu] Long Riders! - 01 (BD 1920x1080 HEVC FLAC).mkv"),
        video_record("[SNSbu] Long Riders! (BD 1920x1080 HEVC FLAC)/[SNSbu] Long Riders! - 02 (BD 1920x1080 HEVC FLAC).mkv"),
        video_record("[SNSbu] Long Riders! (BD 1920x1080 HEVC FLAC)/[SNSbu] Long Riders! - 03 (BD 1920x1080 HEVC FLAC).mkv"),
    )
    hints = media_hints(record)
    queries = metadata_query_variants(record, hints)

    assert hints["season"] == 1
    assert hints["preferred"] == "series"
    assert record_has_series_season_hint(record, hints)
    assert "Extras" not in [query.query for query in queries]


def test_seasonless_series_needs_review_even_with_episode_numbers() -> None:
    record = queue_record(
        "Seasonless Anime",
        video_record("Seasonless Anime/Seasonless Anime E01.mkv"),
        video_record("Seasonless Anime/Seasonless Anime E02.mkv"),
    )
    hints = media_hints(record)
    assert hints["season"] is None
    assert not record_has_series_season_hint(record, hints)


def test_special_videos_are_not_series_season_hints() -> None:
    record = queue_record(
        "Ghost in the Shell Stand Alone Complex Complete Series Batch",
        video_record("Ghost in the Shell Stand Alone Complex Clean OP.mp4"),
    )
    hints = media_hints(record)
    assert hints["season"] is None
    assert not record_has_series_season_hint(record, hints)


def test_tmdb_vote_count_tiebreak_requires_vote_floor_and_gap() -> None:
    args = SimpleNamespace(tmdb_vote_tiebreak_min_votes=25, tmdb_vote_tiebreak_min_gap=25)
    assert tmdb_vote_count_tiebreak({"vote_count": 300}, {"vote_count": 35}, args) == {
        "type": "vote_count",
        "top_vote_count": 300,
        "runner_up_vote_count": 35,
        "vote_gap": 265,
    }
    assert tmdb_vote_count_tiebreak({"vote_count": 30}, {"vote_count": 20}, args) is None
    assert tmdb_vote_count_tiebreak({"vote_count": 10}, {"vote_count": 0}, args) is None


def test_tmdb_candidates_honor_strong_media_preference() -> None:
    candidates = [
        {"media_type": "movie", "title": "Fury", "confidence": 1.0, "vote_count": 12961},
        {"media_type": "tv", "title": "Initial D", "confidence": 1.0, "vote_count": 132},
    ]
    assert candidates_matching_preference(candidates, {"preferred": "series"}) == [candidates[1]]
    assert candidates_matching_preference(candidates, {"preferred": "film"}) == [candidates[0]]
    assert candidates_matching_preference(candidates, {"preferred": "unknown"}) == candidates


def test_music_label_and_obfuscated_candidates() -> None:
    label = music_label_from_text("Aphex Twin - Selected Ambient Works 85-92 [FLAC]")
    assert label is not None
    assert label.title == "Aphex Twin"
    assert label.album == "Selected Ambient Works 85-92"

    assert music_label_from_text("3l1s R3g1n4 3 T0m J0b1m- 3l1s 3 T0m") is None
    candidates = music_candidates_from_text("3l1s R3g1n4 3 T0m J0b1m- 3l1s 3 T0m")
    assert [candidate.source for candidate in candidates] == ["deobfuscated-filename"]
    assert candidates[0].artist == "elis Regina e Tom Jobim"
    assert candidates[0].album == "elis e Tom"


def test_parse_labels_preserves_existing_cli_contract() -> None:
    assert parse_label(["series:South Park", "season:4"]).season == 4
    music = parse_label(["music:Aphex Twin - Selected Ambient Works 85-92"])
    assert music is not None
    assert music.kind == "music"
    assert music.title == "Aphex Twin"
    assert music.album == "Selected Ambient Works 85-92"
