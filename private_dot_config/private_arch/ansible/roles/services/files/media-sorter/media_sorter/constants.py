from __future__ import annotations

import re


VIDEO_EXTENSIONS = {
    ".avi",
    ".m4v",
    ".mkv",
    ".mov",
    ".mp4",
    ".mpeg",
    ".mpg",
    ".ts",
    ".webm",
    ".wmv",
}

SUBTITLE_EXTENSIONS = {
    ".ass",
    ".idx",
    ".srt",
    ".ssa",
    ".sub",
    ".vtt",
}

USEFUL_SIDECAR_EXTENSIONS = SUBTITLE_EXTENSIONS | {
    ".jpg",
    ".jpeg",
    ".nfo",
    ".png",
}

AUDIO_EXTENSIONS = {
    ".aac",
    ".aif",
    ".aiff",
    ".alac",
    ".ape",
    ".flac",
    ".m4a",
    ".mp3",
    ".oga",
    ".ogg",
    ".opus",
    ".wav",
    ".wma",
}

MUSIC_SIDECAR_EXTENSIONS = {
    ".cue",
    ".elrc",
    ".jpg",
    ".jpeg",
    ".lrc",
    ".log",
    ".m3u",
    ".m3u8",
    ".nfo",
    ".png",
}

BOOK_EXTENSIONS = {
    ".azw",
    ".azw3",
    ".cb7",
    ".cbr",
    ".cbt",
    ".cbz",
    ".epub",
    ".mobi",
}

BOOK_SIDECAR_EXTENSIONS = {
    ".jpg",
    ".jpeg",
    ".nfo",
    ".opf",
    ".png",
}

MUSIC_RELEASE_MARKERS = {
    "aac",
    "cd",
    "cds",
    "cue",
    "eac",
    "flac",
    "lossless",
    "m4a",
    "mp3",
    "ogg",
    "opus",
    "proper",
    "retail",
    "v0",
    "v2",
    "vinyl",
    "web",
}

BACKFILL_SERIES_MAP = (
    (re.compile(r"^South[ ._-]*Park[ ._-]*Season", re.I), "South Park"),
    (re.compile(r"^Corporate", re.I), "Corporate"),
    (re.compile(r"^A[ ._-]*P[ ._-]*Bio", re.I), "A.P. Bio"),
    (re.compile(r"^Rick[ ._-]*and[ ._-]*Morty", re.I), "Rick and Morty"),
    (re.compile(r"^Parks[ ._-]*and[ ._-]*Recreation", re.I), "Parks and Recreation"),
    (re.compile(r"^Star[ ._-]*Trek[ ._-]*Deep[ ._-]*Space[ ._-]*Nine", re.I), "Star Trek Deep Space Nine"),
    (re.compile(r"^Star[ ._-]*Trek[ ._-]*Enterprise", re.I), "Star Trek Enterprise"),
    (re.compile(r"^Stargate[ ._-]*SG-?1", re.I), "Stargate SG-1"),
    (re.compile(r"^Stargate[ ._-]*Atlantis", re.I), "Stargate Atlantis"),
    (re.compile(r"^SGU[ ._-]*Stargate[ ._-]*Universe", re.I), "Stargate Universe"),
    (re.compile(r"^Os[ ._-]*normais", re.I), "Os Normais"),
    (re.compile(r"^Cowboy[ ._-]*Bebop", re.I), "Cowboy Bebop"),
    (re.compile(r"^The[ ._-]*Chemistry[ ._-]*Of[ ._-]*Death", re.I), "The Chemistry of Death"),
    (re.compile(r"^Top[ ._-]*Gear[ ._-]*UK[ ._-]*1-17", re.I), "Top Gear"),
)

RELEASE_TOKENS = {
    "aac",
    "amzn",
    "bd",
    "bdrip",
    "bluray",
    "brrip",
    "complete",
    "ddp",
    "dual",
    "dvdrip",
    "galaxyrg",
    "galaxyrg265",
    "galaxytv",
    "hdtv",
    "hevc",
    "japanese",
    "proper",
    "rarbg",
    "remastered",
    "repack",
    "rerip",
    "tgx",
    "web",
    "web-dl",
    "webdl",
    "webrip",
    "x264",
    "x265",
}

SPECIAL_VIDEO_PATTERNS = (
    re.compile(r"(?i)(?:^|[^a-z0-9])NCOP(?:[^a-z0-9]|$)"),
    re.compile(r"(?i)(?:^|[^a-z0-9])NCED(?:[^a-z0-9]|$)"),
    re.compile(r"(?i)clean[ ._-]*(?:op|opening)"),
    re.compile(r"(?i)non[ ._-]*credit"),
    re.compile(r"(?i)creditless"),
)

EXTRA_VIDEO_PATTERNS = (
    (re.compile(r"(?i)^kino[ ._-]*\d{1,3}(?:\b|[ ._-])"), "shorts"),
    (re.compile(r"(?i)(?:^|[ ._-])interviews?[ ._-]*\d{1,3}(?:\b|[ ._-])"), "interviews"),
    (re.compile(r"(?i)(?:^|[ ._-])interviews?(?:\b|[ ._-])"), "interviews"),
    (re.compile(r"(?i)(?:^|[ ._-])featurettes?(?:\b|[ ._-])"), "featurettes"),
    (re.compile(r"(?i)(?:^|[ ._-])trailers?(?:\b|[ ._-])"), "trailers"),
    (re.compile(r"(?i)(?:^|[ ._-])teasers?(?:\b|[ ._-])"), "trailers"),
    (re.compile(r"(?i)(?:^|[ ._-])promos?(?:\b|[ ._-])"), "clips"),
    (re.compile(r"(?i)(?:^|[ ._-])slogans?(?:\b|[ ._-])"), "clips"),
    (re.compile(r"(?i)(?:^|[ ._-])clips?(?:\b|[ ._-])"), "clips"),
    (re.compile(r"(?i)(?:^|[ ._-])samples?(?:\b|[ ._-])"), "samples"),
    (re.compile(r"(?i)(?:^|[ ._-])shorts?(?:\b|[ ._-])"), "shorts"),
    (re.compile(r"(?i)(?:^|[ ._-])extras?(?:\b|[ ._-])"), "extras"),
)

MOVIE_EXTRA_VIDEO_PATTERNS = (
    (re.compile(r"(?i)(?:^|[ ._-])trailers?(?:\b|[ ._-])"), "trailers"),
    (re.compile(r"(?i)(?:^|[ ._-])teasers?(?:\b|[ ._-])"), "trailers"),
    (re.compile(r"(?i)(?:^|[ ._-])music[ ._-]*videos?(?:\b|[ ._-])"), "extras"),
    (re.compile(r"(?i)(?:^|[ ._-])deleted[ ._-]*scenes?(?:\b|[ ._-])"), "deleted scenes"),
    (re.compile(r"(?i)(?:^|[ ._-])behind[ ._-]*the[ ._-]*scenes?(?:\b|[ ._-])"), "behind the scenes"),
)

GENERIC_METADATA_FOLDER_TITLES = {
    "behind the scenes",
    "backdrops",
    "clips",
    "deleted scenes",
    "extras",
    "featurettes",
    "interviews",
    "other",
    "samples",
    "scenes",
    "shorts",
    "specials",
    "theme-music",
    "trailers",
}
