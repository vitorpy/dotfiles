from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class FileEntry:
    relpath: Path
    source: Path



@dataclass(frozen=True)
class MediaLabel:
    kind: str
    title: str
    season: int | None = None
    album: str | None = None



@dataclass(frozen=True)
class MatchDecision:
    label: MediaLabel | None
    status: str
    reason: str
    match: dict[str, Any] | None = None



@dataclass(frozen=True)
class MusicCandidate:
    artist: str
    album: str
    query: str
    source: str



@dataclass(frozen=True)
class MetadataQuery:
    query: str
    source: str



@dataclass(frozen=True)
class AcoustIDFingerprint:
    entry: FileEntry
    duration: int
    fingerprint: str
