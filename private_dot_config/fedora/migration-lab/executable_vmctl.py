#!/usr/bin/env python3
"""Inspect, gracefully stop, or capture the migration lab via its private QMP socket."""
import argparse
import json
import os
from pathlib import Path
import socket

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("action", choices=["status", "shutdown", "screenshot"])
args = parser.parse_args()
lab = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "fedora-migration-lab"

def read_response(stream):
    while True:
        line = stream.readline()
        if not line:
            raise RuntimeError("QEMU closed the control connection")
        reply = json.loads(line)
        if "error" in reply:
            raise RuntimeError(reply["error"])
        if "return" in reply:
            return reply["return"]

try:
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(10)
        connection.connect(str(lab / "run/qmp.sock"))
        with connection.makefile("rwb", buffering=0) as stream:
            greeting = json.loads(stream.readline())
            if "QMP" not in greeting:
                raise RuntimeError("Unexpected QEMU greeting")
            def execute(command, arguments=None):
                request = {"execute": command}
                if arguments is not None:
                    request["arguments"] = arguments
                stream.write(json.dumps(request).encode() + b"\n")
                return read_response(stream)
            execute("qmp_capabilities")
            if args.action == "status":
                print(json.dumps(execute("query-status"), indent=2))
            elif args.action == "shutdown":
                execute("system_powerdown")
                print("Requested graceful guest shutdown; check status until it stops.")
            else:
                destination = lab / "run/screenshot.ppm"
                execute("screendump", {"filename": str(destination)})
                print(destination)
except (OSError, ValueError, RuntimeError) as error:
    parser.exit(1, f"VM control failed: {error}\n")
