#!/usr/bin/env python3
"""Host/Wayland smoke test of ClockState using isolated location caches."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


def main():
    berg = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="berg-clock-runtime-") as directory:
        root = Path(directory)
        cache = root / "cache" / "quickshell-berg"
        cache.mkdir(parents=True)
        location = cache / "location.json"
        harness = root / "shell.qml"
        harness.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "''' + berg.as_uri() + '''" as Berg
ShellRoot {
    QtObject {
        id: popoutModel
        property string screenName: ""
        function isOpen(kind, screen) { return false; }
    }
    Berg.ClockState { id: clock; popouts: popoutModel }
    IpcHandler {
        target: "probe"
        function status(): string {
            return JSON.stringify({ timezone: clock.currentTimezone,
                locationStatus: clock.locationStatus, locationNote: clock.locationNote,
                local: clock.localDate, barWarsaw: clock.barWarsaw,
                timezoneError: clock.timezoneError });
        }
    }
}
''')
        env = {**os.environ, "XDG_CACHE_HOME": str(root / "cache"), "QT_QPA_PLATFORM": "wayland"}
        for name in ("DISPLAY", "GTK_THEME", "QT_QPA_PLATFORMTHEME", "QT_STYLE_OVERRIDE"):
            env.pop(name, None)
        with (root / "runtime.log").open("w+") as log:
            process = subprocess.Popen(["qs", "-p", str(harness), "--no-color"], env=env, stdout=log, stderr=log)
            try:
                def expect(zone, status):
                    deadline = time.monotonic() + 8
                    result = None
                    while time.monotonic() < deadline:
                        if process.poll() is not None:
                            log.flush()
                            log.seek(0)
                            raise AssertionError(f"Quickshell exited during startup: {log.read()}")
                        response = subprocess.run(["qs", "-p", str(harness), "ipc", "call", "probe", "status"],
                                                  env=env, capture_output=True, text=True, timeout=3)
                        if response.returncode == 0 and response.stdout.lstrip().startswith("{"):
                            result = json.loads(response.stdout)
                            if result["timezone"] == zone and result["locationStatus"] == status and result["local"]:
                                assert result["timezoneError"] == "", result
                                print(f"PASS runtime: {zone} / {status}", flush=True)
                                return result
                        time.sleep(0.1)
                    log.flush()
                    log.seek(0)
                    raise AssertionError(f"expected {zone}/{status}, got {result}\n{log.read()}")

                def write(zone, age=0):
                    temporary = location.with_suffix(".tmp")
                    temporary.write_text(json.dumps({"timezone": zone, "source": "ip-api.com",
                                                      "updated_at": int(time.time()) - age}))
                    temporary.replace(location)

                first = expect("Europe/Warsaw", "unavailable")
                assert first["barWarsaw"] == "", first
                write("America/New_York")
                detected = expect("America/New_York", "fresh")
                assert detected["barWarsaw"].startswith("Warsaw "), detected
                write("America/New_York", age=7200)
                stale = expect("America/New_York", "stale")
                assert stale["locationNote"] == "last known location", stale
                location.write_text("{")
                expect("America/New_York", "stale")
                location.unlink()
                expect("America/New_York", "stale")
                write("Asia/Kathmandu")
                expect("Asia/Kathmandu", "fresh")
                write("Europe/Warsaw")
                last = expect("Europe/Warsaw", "fresh")
                assert last["barWarsaw"] == "", last
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)


if __name__ == "__main__":
    main()
