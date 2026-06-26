from __future__ import annotations

import re

from .constants import MUSIC_RELEASE_MARKERS
from .models import FileEntry, MediaLabel, MusicCandidate
from .utils import normalize_title, safe_component, strip_bracketed


def clean_music_component(value: str) -> str:
    value = re.sub(r"[\._]+", " ", value)
    value = re.sub(r"\s+", " ", value).strip(" -_.")
    return safe_component(value)



def is_music_release_marker(value: str) -> bool:
    marker = re.sub(r"[\[\](){}._-]+", " ", value)
    marker = re.sub(r"\s+", " ", marker).strip().lower()
    if not marker:
        return True
    if marker in MUSIC_RELEASE_MARKERS:
        return True
    if re.fullmatch(r"\d{1,2}\s*(?:cd|cds|disc|discs)", marker):
        return True
    if re.fullmatch(r"(?:cd|disc)\s*\d{1,2}", marker):
        return True
    if re.fullmatch(r"(?:mp3|aac|flac|ogg|opus)\s*\d{2,4}", marker):
        return True
    if re.fullmatch(r"\d{2,4}\s*(?:kbps|k|vbr)", marker):
        return True
    return False



def looks_obfuscated_music_text(value: str) -> bool:
    alnum = re.findall(r"[a-zA-Z0-9]", value)
    if len(alnum) < 8:
        return False
    digit_ratio = sum(1 for char in alnum if char.isdigit()) / len(alnum)
    mixed_tokens = [
        token
        for token in re.findall(r"[a-zA-Z0-9]+", value)
        if any(char.isalpha() for char in token) and any(char.isdigit() for char in token)
    ]
    return digit_ratio >= 0.22 and len(mixed_tokens) >= 3



def deobfuscate_music_text(value: str) -> str:
    return value.translate(str.maketrans({"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t"}))



def music_label_from_text(value: str, reject_obfuscated: bool = True) -> MediaLabel | None:
    cleaned = strip_bracketed(value)
    cleaned = re.sub(r"\s*[\[(].*$", " ", cleaned)
    cleaned = re.sub(r"[\._]+", " ", cleaned)
    cleaned = re.sub(r"\s+-\s*", " - ", cleaned)
    cleaned = re.sub(r"\s*-\s+", " - ", cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned).strip(" -_.")
    parts = [part.strip(" -_.") for part in re.split(r"\s+-\s+", cleaned) if part.strip(" -_.")]
    while parts and is_music_release_marker(parts[-1]):
        parts.pop()
    if len(parts) < 2:
        return None

    artist = clean_music_component(parts[0])
    album = clean_music_component(" - ".join(parts[1:]))
    if reject_obfuscated and looks_obfuscated_music_text(f"{artist} {album}"):
        return None
    return MediaLabel(kind="music", title=artist, album=album)



def music_candidates_from_text(value: str) -> list[MusicCandidate]:
    candidates = []
    seen = set()
    for source, candidate_text in (("filename", value), ("deobfuscated-filename", deobfuscate_music_text(value))):
        label = music_label_from_text(candidate_text, reject_obfuscated=(source == "filename"))
        if not label or not label.album:
            continue
        key = (normalize_title(label.title), normalize_title(label.album))
        if key in seen:
            continue
        seen.add(key)
        candidates.append(MusicCandidate(artist=label.title, album=label.album, query=value, source=source))
    return candidates



def is_disc_folder(value: str) -> bool:
    return re.fullmatch(r"(?i)(?:cd|disc|disk)[ ._-]*\d{1,2}", value.strip()) is not None



def stripped_music_parent(entry: FileEntry, entries: list[FileEntry]) -> tuple[str, ...]:
    selected_parts = [item.relpath.parts for item in entries if item.relpath.parts]
    parts = entry.relpath.parts
    if selected_parts and parts and all(len(item_parts) > 1 and item_parts[0] == parts[0] for item_parts in selected_parts):
        parts = parts[1:]
    parent = parts[:-1]
    if parent and is_disc_folder(parent[-1]):
        parent = parent[:-1]
    return tuple(parent)



def looks_like_single_album(audio: list[FileEntry]) -> bool:
    if not audio:
        return False
    album_parents = {stripped_music_parent(entry, audio) for entry in audio}
    return len(album_parents) <= 1
