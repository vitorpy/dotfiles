"""Exercise the real updater with deterministic provider responses, no network."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "update-clock-weather.sh"


class ClockWeatherTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.cache = self.root / "cache"
        self.cache.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.calls = self.root / "calls"
        self.scenario = self.root / "scenario.json"
        curl = self.bin / "curl"
        curl.write_text('''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
kind = next(arg for arg in sys.argv[1:] if arg.startswith("fixture:"))[8:]
with open(os.environ["FAKE_CALLS"], "a") as stream:
    stream.write(kind + "\\n")
value = json.loads(Path(os.environ["FAKE_SCENARIO"]).read_text())[kind]
if value is None:
    print("curl: (6) Could not resolve fixture provider", file=sys.stderr)
    sys.exit(6)
print(json.dumps(value))
''')
        curl.chmod(0o755)
        self.env = {**os.environ, "PATH": f"{self.bin}:/usr/bin", "CLOCK_CACHE_DIR": str(self.cache),
                    "CLOCK_LOCATION_CACHE": str(self.cache / "location.json"),
                    "CLOCK_WEATHER_CACHE": str(self.cache / "weather.json"),
                    "CLOCK_IPAPI_URL": "fixture:ipapi", "CLOCK_IP_API_URL": "fixture:ip-api",
                    "CLOCK_WEATHER_URL": "fixture:weather", "FAKE_SCENARIO": str(self.scenario),
                    "FAKE_CALLS": str(self.calls), "LC_ALL": "C", "CLOCK_LOCATION_MAX_AGE": "3600"}
        self.location = {"city": "New York", "country_code": "US", "latitude": 40.7, "longitude": -74,
                         "timezone": "America/New_York", "updated_at": int(time.time()), "source": "ipapi.co"}
        current = {"time": "2026-09-26T20:00", "temperature_2m": 20, "apparent_temperature": 20,
                   "precipitation_probability": 0, "weather_code": 0, "wind_speed_10m": 5}
        hourly = {key: [value, value] for key, value in current.items()}
        hourly["time"] = ["2026-09-26T20:00", "2026-09-26T21:00"]
        self.weather = {"current": current, "hourly": hourly}

    def run_updater(self, ipapi=None, fallback=None, weather=True):
        self.scenario.write_text(json.dumps({"ipapi": ipapi, "ip-api": fallback,
                                            "weather": self.weather if weather else None}))
        return subprocess.run(["bash", str(SCRIPT)], env=self.env, capture_output=True, text=True, timeout=10)

    def read_location(self):
        return json.loads((self.cache / "location.json").read_text())

    def write_location(self, value):
        (self.cache / "location.json").write_text(json.dumps(value))

    def test_new_location_published_before_weather_failure(self):
        result = self.run_updater(ipapi=self.location, weather=False)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(self.read_location()["timezone"], "America/New_York")
        self.assertFalse((self.cache / "weather.json").exists())
        self.assertIn("Could not resolve", result.stderr)
        self.assertEqual((self.cache / "location.json").stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.cache.stat().st_mode & 0o777, 0o700)

    def test_offline_startup_then_wifi_recovery_ignores_default_ttl(self):
        failed = self.run_updater(weather=False)
        self.assertEqual(failed.returncode, 1, failed.stderr)
        self.assertEqual(self.read_location()["source"], "default")
        recovered = self.run_updater(ipapi=self.location)
        self.assertEqual(recovered.returncode, 0, recovered.stderr)
        self.assertEqual(self.read_location()["timezone"], "America/New_York")
        self.assertEqual(self.calls.read_text().splitlines().count("ipapi"), 2)

    def test_stale_location_survives_and_weather_success_still_retries(self):
        old = {**self.location, "updated_at": int(time.time()) - 7200}
        self.write_location(old)
        result = self.run_updater()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(self.read_location(), old)
        self.assertTrue((self.cache / "weather.json").is_file())
        self.assertIn("Unable to refresh location", result.stderr)

    def test_fresh_detection_avoids_duplicate_geolocation(self):
        self.write_location(self.location)
        result = self.run_updater()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text().splitlines(), ["weather"])

    def test_invalid_provider_zone_uses_valid_fallback(self):
        fallback = {"status": "success", "city": "New York", "countryCode": "US", "lat": 40.7,
                    "lon": -74, "timezone": "America/New_York"}
        result = self.run_updater(ipapi={**self.location, "timezone": "Invalid/Zone"}, fallback=fallback)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read_location()["source"], "ip-api.com")

    def test_malformed_and_invalid_cache_does_not_block_recovery(self):
        for raw in ("{", json.dumps({**self.location, "timezone": "Invalid/Zone"})):
            with self.subTest(raw=raw):
                (self.cache / "location.json").write_text(raw)
                result = self.run_updater(ipapi=self.location)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.read_location()["timezone"], "America/New_York")


if __name__ == "__main__":
    unittest.main()
