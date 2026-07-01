from __future__ import annotations

import json
import os
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

def log(level: str, message: str) -> None:
    stream = sys.stderr if level in {"ERROR", "WARNING"} else sys.stdout
    print(f"{level}: media-sort-transmission: {message}", file=stream, flush=True)


def read_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return values
    except OSError as exc:
        log("WARNING", f"could not read env file {path}: {exc}")
        return values

    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def telegram_config() -> tuple[str | None, str | None]:
    env_file = Path(os.environ.get("MEDIA_SORTER_TELEGRAM_ENV_FILE", "/etc/media-sorter/telegram.env"))
    env_values = read_env_file(env_file)

    def value(*names: str) -> str | None:
        for name in names:
            candidate = os.environ.get(name)
            if candidate:
                return candidate
        for name in names:
            candidate = env_values.get(name)
            if candidate:
                return candidate
        return None

    token = value("MEDIA_SORTER_TELEGRAM_BOT_TOKEN", "TELEGRAM_BOT_TOKEN")
    chat_id = value("MEDIA_SORTER_TELEGRAM_CHAT_ID", "TELEGRAM_CHAT_ID")
    if not chat_id:
        allowed_users = value("TELEGRAM_ALLOWED_USERS")
        if allowed_users and "," not in allowed_users:
            chat_id = allowed_users
    return token, chat_id


def send_telegram_notification(message: str) -> None:
    token, chat_id = telegram_config()
    if not token or not chat_id:
        return

    data = urllib.parse.urlencode({"chat_id": chat_id, "text": message}).encode("utf-8")
    request = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            if response.status != 200:
                log("WARNING", f"telegram notification returned status={response.status}")
    except urllib.error.HTTPError as exc:
        log("WARNING", f"telegram notification failed status={exc.code}")
    except urllib.error.URLError as exc:
        log("WARNING", f"telegram notification failed reason={exc.reason}")
    except OSError as exc:
        log("WARNING", f"telegram notification failed: {exc}")


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
        r"(?i)(?:^|[ .\-\[(])(\d{1,2})[aªºo]?[ ._-]*temporada(?:\b|[ .\-\])])",
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
