#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
updater="${repo_root}/roles/services/files/transmission-update-trackers"

python3 - "${updater}" <<'PY'
import importlib.machinery
import importlib.util
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("transmission_update_trackers", str(path))
spec = importlib.util.spec_from_loader("transmission_update_trackers", loader)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

trackers = module.parse_tracker_text(
    """
    # comment
    udp://tracker.example:1337/announce

    https://tracker.example/announce
    ftp://ignored.example/announce
    UDP://TRACKER.EXAMPLE:1337/announce
    """
)
assert trackers == [
    "udp://tracker.example:1337/announce",
    "https://tracker.example/announce",
]

merged = module.merge_trackers(
    current_trackers=[
        "udp://private.example:80/announce",
        "udp://old-managed.example:80/announce",
        "udp://tracker.example:1337/announce",
    ],
    desired_trackers=[
        "udp://tracker.example:1337/announce",
        "https://new.example/announce",
    ],
    previous_managed_trackers=[
        "udp://old-managed.example:80/announce",
        "udp://tracker.example:1337/announce",
    ],
)
assert merged == [
    "udp://private.example:80/announce",
    "udp://tracker.example:1337/announce",
    "https://new.example/announce",
]

assert module.tracker_list_changed(["UDP://TRACKER.EXAMPLE:1337/announce"], ["udp://tracker.example:1337/announce"]) is False
assert module.tracker_list_changed(["udp://old.example/announce"], ["udp://new.example/announce"]) is True

calls = []


class FakeTransmissionRpc(module.TransmissionRpc):
    def __init__(self):
        pass

    def call(self, method, arguments=None):
        calls.append((method, arguments or {}))
        return {"result": "success"}


client = FakeTransmissionRpc()
client.reannounce_torrents([])
assert calls == []
client.reannounce_torrents([1, 2])
assert calls == [("torrent-reannounce", {"ids": [1, 2]})]
PY
