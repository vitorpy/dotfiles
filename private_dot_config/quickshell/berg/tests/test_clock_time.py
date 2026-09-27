import importlib.util
import json
import locale
from pathlib import Path
import tempfile
import unittest
from datetime import datetime

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "clock-time.py"
spec = importlib.util.spec_from_file_location("clock_time", SCRIPT)
clock = importlib.util.module_from_spec(spec)
spec.loader.exec_module(clock)


def epoch(value):
    return datetime.fromisoformat(value).timestamp()


class ClockTimeTests(unittest.TestCase):
    def setUp(self):
        locale.setlocale(locale.LC_TIME, "C")
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.cache = Path(self.directory.name) / "location.json"
        self.now = epoch("2026-09-27T00:30:00+00:00")
        self.location = {"timezone": "America/New_York", "updated_at": self.now - 60, "source": "ip-api.com"}

    def write(self, value):
        self.cache.write_text(json.dumps(value))

    def test_midnight_and_year_boundary(self):
        for instant, local_date, warsaw_date in [
            (self.now, "2026-09-26", "2026-09-27"),
            (epoch("2027-01-01T00:30:00+00:00"), "2026-12-31", "2027-01-01"),
        ]:
            with self.subTest(instant=instant):
                result = clock.format_clock(instant, "America/New_York")
                self.assertEqual(result["local"]["isoDate"], local_date)
                self.assertEqual(result["warsaw"]["isoDate"], warsaw_date)

    def test_dst_transitions(self):
        for zone, before, after, expected in [
            ("America/New_York", "2026-03-08T06:59:00+00:00", "2026-03-08T07:00:00+00:00", ("01:59", "03:00")),
            ("America/New_York", "2026-11-01T05:59:00+00:00", "2026-11-01T06:00:00+00:00", ("01:59", "01:00")),
            ("Europe/Warsaw", "2026-03-29T00:59:00+00:00", "2026-03-29T01:00:00+00:00", ("01:59", "03:00")),
            ("Europe/Warsaw", "2026-10-25T00:59:00+00:00", "2026-10-25T01:00:00+00:00", ("02:59", "02:00")),
        ]:
            with self.subTest(zone=zone, before=before):
                actual = tuple(clock.format_clock(epoch(t), zone)["local"]["time"] for t in (before, after))
                self.assertEqual(actual, expected)

    def test_fractional_offset_and_warsaw(self):
        self.assertEqual(clock.format_clock(self.now, "Asia/Kathmandu")["local"]["time"], "06:15")
        frame = clock.format_clock(self.now, "Europe/Warsaw")
        self.assertEqual(frame["local"], frame["warsaw"])

    def test_invalid_zones(self):
        for value in (None, "", "Mars/Olympus", "../etc/localtime", "/etc/localtime", "posix/Europe/Warsaw", "right/UTC"):
            with self.subTest(value=value):
                self.assertFalse(clock.valid_timezone(value))

    def test_fresh_cache_and_expired_cache_keep_real_time(self):
        self.write(self.location)
        self.assertEqual(clock.snapshot(self.now, self.cache)["locationStatus"], "fresh")
        later = clock.snapshot(self.now + 3600, self.cache)
        self.assertEqual(later["locationStatus"], "stale")
        self.assertEqual(later["local"]["time"], "21:30")
        self.assertEqual(later["location"], self.location)

    def test_missing_malformed_invalid_and_default_cache(self):
        for raw in (None, "{", "null", json.dumps({**self.location, "timezone": "Mars/Olympus"}),
                    json.dumps({**self.location, "source": "default"}),
                    json.dumps({**self.location, "updated_at": self.now + 60})):
            with self.subTest(raw=raw):
                if raw is None:
                    self.cache.unlink(missing_ok=True)
                else:
                    self.cache.write_text(raw)
                cold = clock.snapshot(self.now, self.cache)
                self.assertEqual(cold["local"]["timezone"], "Europe/Warsaw")
                self.assertEqual(cold["locationStatus"], "unavailable")
                warm = clock.snapshot(self.now, self.cache, self.location)
                self.assertEqual(warm["local"]["timezone"], "America/New_York")
                self.assertEqual(warm["locationStatus"], "stale")

    def test_new_valid_detection_replaces_stale_fallback(self):
        self.write({**self.location, "timezone": "Asia/Kathmandu", "updated_at": self.now})
        result = clock.snapshot(self.now, self.cache, self.location)
        self.assertEqual(result["local"]["timezone"], "Asia/Kathmandu")
        self.assertEqual(result["locationStatus"], "fresh")


if __name__ == "__main__":
    unittest.main()
