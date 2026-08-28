#!/usr/bin/env python3
"""Report new current-user systemd-coredump events through Berg notifications."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
from dataclasses import asdict, dataclass
from pathlib import Path
import subprocess
import sys
import time
import unicodedata
from collections.abc import Callable, Mapping, Sequence
from typing import Any


COREDUMP_MESSAGE_ID = "fc2e22bc6ee647b6b90729ab34a250b1"
DEFAULT_DEDUPE_SECONDS = 60.0
DEFAULT_MUTE_FILE = Path(__file__).resolve().parent.parent / "crash-watch-muted.txt"


@dataclass(frozen=True)
class CrashEvent:
    uid: int
    pid: int
    program: str
    executable: str
    signal: int | None
    signal_name: str

    @property
    def dedupe_key(self) -> str:
        return self.executable or self.program

    @property
    def is_berg(self) -> bool:
        candidates = {self.program.casefold()}
        if self.executable:
            candidates.add(Path(self.executable).name.casefold())
        return bool(candidates & {"qs", "quickshell"})


def sanitize_text(value: Any, *, fallback: str = "", limit: int = 240) -> str:
    """Normalize journal text without accepting binary-array JSON values."""
    if not isinstance(value, str):
        return fallback

    normalized: list[str] = []
    for character in value:
        if character.isspace():
            normalized.append(" ")
        elif not unicodedata.category(character).startswith("C"):
            normalized.append(character)

    return " ".join("".join(normalized).split())[:limit] or fallback


def parse_unsigned(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value if value >= 0 else None
    if not isinstance(value, str):
        return None
    value = value.strip()
    return int(value) if value.isascii() and value.isdigit() else None


def parse_event(record: Mapping[str, Any], expected_uid: int) -> CrashEvent | None:
    message_id = sanitize_text(record.get("MESSAGE_ID"), limit=64)
    uid = parse_unsigned(record.get("COREDUMP_UID"))
    pid = parse_unsigned(record.get("COREDUMP_PID"))
    if message_id != COREDUMP_MESSAGE_ID or uid != expected_uid or pid is None:
        return None

    executable = sanitize_text(record.get("COREDUMP_EXE"), limit=512)
    program = sanitize_text(record.get("COREDUMP_COMM"), limit=96)
    if not program and executable:
        program = Path(executable).name
    if not program:
        program = "Unknown process"

    signal_number = parse_unsigned(record.get("COREDUMP_SIGNAL"))
    signal_name = sanitize_text(record.get("COREDUMP_SIGNAL_NAME"), limit=32)
    if not signal_name:
        signal_name = f"signal {signal_number}" if signal_number is not None else "unknown signal"

    return CrashEvent(
        uid=uid,
        pid=pid,
        program=program,
        executable=executable,
        signal=signal_number,
        signal_name=signal_name,
    )


def load_mute_list(path: Path) -> set[str]:
    try:
        contents = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return set()
    except OSError as error:
        print(f"berg-crash-watch: unable to read mute list: {error}", file=sys.stderr, flush=True)
        return set()

    muted: set[str] = set()
    for raw_line in contents.splitlines():
        line = sanitize_text(raw_line, limit=512)
        if line and not line.startswith("#"):
            muted.add(line)
    return muted


def is_muted(event: CrashEvent, muted: set[str]) -> bool:
    return event.program in muted or bool(event.executable and event.executable in muted)


class DedupeCache:
    def __init__(self, window_seconds: float = DEFAULT_DEDUPE_SECONDS) -> None:
        self.window_seconds = window_seconds
        self._last_emitted: dict[str, float] = {}

    def should_emit(self, event: CrashEvent, now: float | None = None) -> bool:
        timestamp = time.monotonic() if now is None else now
        stale_before = timestamp - self.window_seconds
        self._last_emitted = {
            key: seen for key, seen in self._last_emitted.items() if seen > stale_before
        }
        if event.dedupe_key in self._last_emitted:
            return False

        self._last_emitted[event.dedupe_key] = timestamp
        return True


def notification_argv(event: CrashEvent) -> list[str]:
    safe_program = html.escape(event.program, quote=True)
    safe_signal = html.escape(event.signal_name, quote=True)
    signal_suffix = f" ({event.signal})" if event.signal is not None else ""
    summary = f"{safe_program} crashed"
    body = (
        f"Signal: <b>{safe_signal}{signal_suffix}</b>\n"
        f"PID: <b>{event.pid}</b>\n"
        f"Inspect: <tt>coredumpctl info {event.pid}</tt>"
    )
    stack_digest = hashlib.sha256(event.dedupe_key.encode("utf-8")).hexdigest()[:16]

    return [
        "/usr/bin/notify-send",
        "--urgency=critical",
        "--expire-time=0",
        "--app-name=Berg",
        "--icon=dialog-error-symbolic",
        f"--hint=string:x-dunst-stack-tag:berg-crash-{stack_digest}",
        summary,
        body,
    ]


def send_notification(
    event: CrashEvent,
    *,
    runner: Callable[..., Any] = subprocess.run,
    sleeper: Callable[[float], None] = time.sleep,
) -> bool:
    attempts = 12 if event.is_berg else 1
    argv = notification_argv(event)

    for attempt in range(attempts):
        try:
            result = runner(
                argv,
                check=False,
                capture_output=True,
                text=True,
                timeout=2,
            )
            if result.returncode == 0:
                return True
        except (OSError, subprocess.SubprocessError) as error:
            if attempt == attempts - 1:
                print(f"berg-crash-watch: notification failed: {error}", file=sys.stderr, flush=True)

        if attempt < attempts - 1:
            sleeper(0.5)

    return False


def journal_command(uid: int) -> list[str]:
    return [
        "/usr/bin/journalctl",
        "--follow",
        "--lines=0",
        "--output=json",
        "--no-pager",
        "--quiet",
        f"MESSAGE_ID={COREDUMP_MESSAGE_ID}",
        f"COREDUMP_UID={uid}",
    ]


def watch(uid: int, mute_file: Path, dedupe_seconds: float) -> None:
    cache = DedupeCache(dedupe_seconds)
    command = journal_command(uid)
    print(f"berg-crash-watch: following new coredumps for UID {uid}", flush=True)

    with subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    ) as journal:
        if journal.stdout is None:
            raise RuntimeError("journalctl stdout pipe was not created")

        for line in journal.stdout:
            try:
                record = json.loads(line)
            except json.JSONDecodeError as error:
                print(f"berg-crash-watch: ignored malformed journal JSON: {error}", file=sys.stderr, flush=True)
                continue
            if not isinstance(record, dict):
                continue

            event = parse_event(record, uid)
            if event is None or is_muted(event, load_mute_list(mute_file)):
                continue
            if cache.should_emit(event) and not send_notification(event):
                print(
                    f"berg-crash-watch: could not notify for PID {event.pid}",
                    file=sys.stderr,
                    flush=True,
                )

        return_code = journal.wait()

    raise RuntimeError(f"journalctl exited unexpectedly with status {return_code}")


def read_fixture(path: Path, uid: int) -> CrashEvent:
    try:
        record = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"unable to read fixture: {error}") from error
    if not isinstance(record, dict):
        raise ValueError("fixture must contain one JSON object")
    event = parse_event(record, uid)
    if event is None:
        raise ValueError("fixture is malformed or belongs to a different UID")
    return event


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--format-event", type=Path, metavar="JSON")
    mode.add_argument("--notify-event", type=Path, metavar="JSON")
    parser.add_argument("--uid", type=int, default=os.getuid())
    parser.add_argument("--mute-file", type=Path, default=DEFAULT_MUTE_FILE)
    parser.add_argument("--dedupe-seconds", type=float, default=DEFAULT_DEDUPE_SECONDS)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = build_parser().parse_args(argv)
    if arguments.uid < 0:
        raise ValueError("UID must be non-negative")
    if arguments.dedupe_seconds < 0:
        raise ValueError("dedupe interval must be non-negative")

    fixture_path = arguments.format_event or arguments.notify_event
    if fixture_path is not None:
        event = read_fixture(fixture_path, arguments.uid)
        formatted = {"event": asdict(event), "notification_argv": notification_argv(event)}
        print(json.dumps(formatted, indent=2, sort_keys=True))
        if arguments.notify_event and not send_notification(event):
            return 1
        return 0

    watch(arguments.uid, arguments.mute_file, arguments.dedupe_seconds)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, ValueError) as error:
        print(f"berg-crash-watch: {error}", file=sys.stderr)
        raise SystemExit(1) from error
