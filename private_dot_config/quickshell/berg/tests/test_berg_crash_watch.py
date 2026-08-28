from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import sys
import tempfile
import unittest


SCRIPT_PATH = Path(__file__).resolve().parent.parent / "scripts" / "berg_crash_watch.py"
FIXTURE_PATH = Path(__file__).resolve().parent / "fixtures" / "coredump-event.json"
SPEC = importlib.util.spec_from_file_location("berg_crash_watch", SCRIPT_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("unable to load berg_crash_watch")
crash_watch = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = crash_watch
SPEC.loader.exec_module(crash_watch)


class CrashWatchTests(unittest.TestCase):
    def fixture(self) -> dict[str, object]:
        return json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))

    def event(self, **changes: object):
        record = self.fixture()
        record.update(changes)
        event = crash_watch.parse_event(record, 1000)
        self.assertIsNotNone(event)
        return event

    def test_current_uid_is_accepted_and_foreign_uid_is_rejected(self) -> None:
        self.assertIsNotNone(crash_watch.parse_event(self.fixture(), 1000))
        self.assertIsNone(crash_watch.parse_event(self.fixture(), 1001))

        record = self.fixture()
        record["MESSAGE_ID"] = "not-a-coredump"
        self.assertIsNone(crash_watch.parse_event(record, 1000))

    def test_malformed_pid_and_binary_journal_fields_are_safe(self) -> None:
        record = self.fixture()
        record["COREDUMP_PID"] = "4; touch /tmp/nope"
        self.assertIsNone(crash_watch.parse_event(record, 1000))

        event = self.event(COREDUMP_COMM=[102, 111, 111], COREDUMP_EXE="/usr/bin/fallback")
        self.assertEqual(event.program, "fallback")

    def test_text_is_normalized_and_notification_markup_is_escaped(self) -> None:
        event = self.event(
            COREDUMP_COMM=" <img src=x>\u001b\n player ",
            COREDUMP_SIGNAL_NAME="SIG<SEGV>",
        )
        argv = crash_watch.notification_argv(event)
        self.assertIn("&lt;img src=x&gt; player crashed", argv[-2])
        self.assertNotIn("\u001b", "".join(argv))
        self.assertIn("SIG&lt;SEGV&gt;", argv[-1])

    def test_notification_is_critical_persistent_and_argv_only(self) -> None:
        event = self.event(COREDUMP_PID="4242")
        argv = crash_watch.notification_argv(event)
        self.assertEqual(argv[0], "/usr/bin/notify-send")
        self.assertIn("--urgency=critical", argv)
        self.assertIn("--expire-time=0", argv)
        self.assertIn("coredumpctl info 4242", argv[-1])
        self.assertNotIn("sh", argv[:1])

    def test_mute_list_matches_only_exact_program_or_path(self) -> None:
        event = self.event()
        with tempfile.TemporaryDirectory() as directory:
            mute_file = Path(directory) / "muted.txt"
            mute_file.write_text("# comment\nfixture\n\n/usr/bin/other\n", encoding="utf-8")
            self.assertFalse(crash_watch.is_muted(event, crash_watch.load_mute_list(mute_file)))
            mute_file.write_text("fixture-player\n", encoding="utf-8")
            self.assertTrue(crash_watch.is_muted(event, crash_watch.load_mute_list(mute_file)))
            mute_file.write_text("/usr/bin/fixture-player\n", encoding="utf-8")
            self.assertTrue(crash_watch.is_muted(event, crash_watch.load_mute_list(mute_file)))

    def test_deduplication_window_is_per_executable(self) -> None:
        cache = crash_watch.DedupeCache(60)
        event = self.event()
        other = self.event(COREDUMP_EXE="/usr/bin/other", COREDUMP_COMM="other")
        self.assertTrue(cache.should_emit(event, now=100))
        self.assertFalse(cache.should_emit(event, now=120))
        self.assertTrue(cache.should_emit(other, now=120))
        self.assertTrue(cache.should_emit(event, now=160))

    def test_journal_follow_is_current_uid_and_new_events_only(self) -> None:
        command = crash_watch.journal_command(1000)
        self.assertIn("--follow", command)
        self.assertIn("--lines=0", command)
        self.assertIn("COREDUMP_UID=1000", command)
        self.assertIn(f"MESSAGE_ID={crash_watch.COREDUMP_MESSAGE_ID}", command)

    def test_berg_notification_retries_while_normal_process_does_not(self) -> None:
        calls: list[list[str]] = []
        sleeps: list[float] = []
        statuses = iter([1, 1, 0])

        def runner(argv, **_kwargs):
            calls.append(argv)
            return SimpleNamespace(returncode=next(statuses))

        berg = self.event(COREDUMP_COMM="qs", COREDUMP_EXE="/usr/bin/qs")
        self.assertTrue(crash_watch.send_notification(berg, runner=runner, sleeper=sleeps.append))
        self.assertEqual(len(calls), 3)
        self.assertEqual(sleeps, [0.5, 0.5])

        calls.clear()
        normal = self.event()
        self.assertFalse(
            crash_watch.send_notification(
                normal,
                runner=lambda argv, **_kwargs: calls.append(argv) or SimpleNamespace(returncode=1),
                sleeper=sleeps.append,
            )
        )
        self.assertEqual(len(calls), 1)

    def test_controlled_fixture_formats_deterministically(self) -> None:
        event = crash_watch.read_fixture(FIXTURE_PATH, 1000)
        self.assertEqual(event.program, "fixture-player")
        self.assertEqual(event.pid, 4242)
        self.assertEqual(crash_watch.notification_argv(event)[-2], "fixture-player crashed")


if __name__ == "__main__":
    unittest.main()
