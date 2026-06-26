from __future__ import annotations

import re
import sys
import time
import unicodedata


def log(level: str, message: str) -> None:
    stream = sys.stderr if level in {"ERROR", "WARNING"} else sys.stdout
    print(f"{level}: media-sort-transmission: {message}", file=stream, flush=True)



def now_ts() -> int:
    return int(time.time())



def safe_component(value: str) -> str:
    cleaned = value.replace("/", " ").replace("\0", "").strip()
    cleaned = re.sub(r"\s+", " ", cleaned)
    cleaned = cleaned.strip(".")
    if not cleaned or cleaned == "..":
        raise ValueError(f"unsafe path component: {value!r}")
    return cleaned



def parse_season(value: str) -> int | None:
    value = value.replace("_", " ")
    patterns = (
        r"(?i)(?:^|[ .\-\[(])s(\d{1,2})(?:e\d{1,3})+(?:\b|[ .\-\])])",
        r"(?i)(?:^|[ .\-\[(])s(\d{1,2})(?:e\d{1,3})?(?:\b|[ .\-\])])",
        r"(?i)(?:^|[ .\-\[(])season[ .\-]*(\d{1,2})(?:\b|[ .\-\])])",
        r"(?i)(?:^|[ .\-\[(])(\d{1,2})x\d{1,3}(?:\b|[ .\-\])])",
    )
    for pattern in patterns:
        match = re.search(pattern, value)
        if match:
            season = int(match.group(1))
            if 0 <= season <= 99:
                return season
    return None



def first_not_none(*values: int | None) -> int | None:
    for value in values:
        if value is not None:
            return value
    return None



def normalize_title(value: str) -> str:
    value = unicodedata.normalize("NFKD", value)
    value = "".join(char for char in value if not unicodedata.combining(char))
    value = re.sub(r"[\._]+", " ", value)
    value = "".join(char.lower() if char.isalnum() else " " for char in value)
    return re.sub(r"\s+", " ", value).strip()



def display_title(value: str) -> str:
    value = re.sub(r"[\._]+", " ", value)
    value = re.sub(r"\s+", " ", value).strip(" -_.")
    return safe_component(" ".join(word[:1].upper() + word[1:].lower() for word in value.split()))



def strip_bracketed(value: str) -> str:
    return re.sub(r"[\[(].*?[\])]", " ", value)
