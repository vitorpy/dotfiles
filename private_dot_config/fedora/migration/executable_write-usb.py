#!/usr/bin/env python3
"""Write only the authorized SanDisk using UDisks native desktop authentication."""
import argparse
import fcntl
import hashlib
import json
import mmap
import os
from pathlib import Path
import stat
import struct
import time

from common import USB, disk_inventory, match_disk, sha, write_private


def check_target():
    disk = match_disk(disk_inventory(), USB, usb=True)
    nodes = [disk]
    while nodes:
        node = nodes.pop()
        if any(node.get("mountpoints") or []):
            raise RuntimeError("USB or one of its partitions is mounted; unmount it first")
        sys = Path("/sys/class/block") / Path(node["name"]).name
        if any((sys / "holders").iterdir()):
            raise RuntimeError("USB has an active holder")
        nodes.extend(node.get("children", []))
    return disk


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    args = parser.parse_args()
    image = args.image.resolve()
    receipt = json.loads(Path(str(image) + ".json").read_text())
    if receipt.get("rehearsal") is not False:
        raise RuntimeError("Only a composed production image may be written to the physical USB")
    if not image.is_file() or image.stat().st_size != USB["size"] or receipt["usb"] != USB or receipt["image_bytes"] != USB["size"]:
        raise RuntimeError("Image and device identity receipt do not match")
    expected = sha(image)
    if expected != receipt["sha256"]:
        raise RuntimeError("Composed image checksum differs")
    disk = check_target()
    print(f"Authorized USB: {disk['name']}, serial {USB['serial']}, {USB['size']} bytes", flush=True)
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib
    connection = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    path = "/org/freedesktop/UDisks2/block_devices/" + Path(disk["name"]).name
    flags = os.O_EXCL | os.O_SYNC | os.O_DIRECT | os.O_CLOEXEC
    result, fdlist = connection.call_with_unix_fd_list_sync(
        "org.freedesktop.UDisks2", path, "org.freedesktop.UDisks2.Block", "OpenDevice",
        GLib.Variant("(sa{sv})", ("rw", {"flags": GLib.Variant("i", flags)})),
        GLib.VariantType.new("(h)"), Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION,
        120000, None, None)
    descriptor = fdlist.get(result.unpack()[0])
    # get() duplicates the descriptor. Drop the originals too, otherwise the
    # UnixFDList keeps an exclusive device handle alive across the later rescan.
    for original in fdlist.steal_fds():
        os.close(original)
    try:
        opened = os.fstat(descriptor)
        if not stat.S_ISBLK(opened.st_mode) or opened.st_rdev != os.stat(disk["name"]).st_rdev:
            raise RuntimeError("Opened device identity changed")
        capacity = struct.unpack("Q", fcntl.ioctl(descriptor, 0x80081272, bytes(8)))[0]
        if capacity != USB["size"] or check_target()["name"] != disk["name"]:
            raise RuntimeError("USB changed before imaging")
        block = 8 * 1024 * 1024
        with mmap.mmap(-1, block) as buffer, image.open("rb", buffering=0) as source:
            view = memoryview(buffer)
            try:
                position = 0
                last = 0
                while position < capacity:
                    amount = source.readinto(view[:min(block, capacity-position)])
                    if not amount or amount % 512:
                        raise RuntimeError("Short or unaligned image read")
                    written = os.write(descriptor, view[:amount])
                    if written != amount:
                        raise RuntimeError("Short direct write")
                    position += written
                    if position-last >= 1024**3:
                        print(f"Written {position / 1024**3:.1f} GiB", flush=True)
                        last = position
                os.fsync(descriptor)
                os.lseek(descriptor, 0, os.SEEK_SET)
                digest = hashlib.sha256()
                position = 0
                while position < capacity:
                    amount = os.readv(descriptor, [view[:min(block, capacity-position)]])
                    if not amount:
                        raise RuntimeError("Short direct verification read")
                    digest.update(view[:amount])
                    position += amount
                if digest.hexdigest() != expected:
                    raise RuntimeError("USB read-back checksum differs")
            finally:
                view.release()
    finally:
        os.close(descriptor)
    connection.call_sync("org.freedesktop.UDisks2", path, "org.freedesktop.UDisks2.Block", "Rescan",
                         GLib.Variant("(a{sv})", ({},)), None, Gio.DBusCallFlags.NONE, 30000, None)
    write_private(Path.home() / ".local/state/fedora-migration/guided-usb-verification.json",
                  json.dumps(dict(result="passed", sha256=expected, bytes=USB["size"], usb=USB, verified_at=time.time()), indent=2) + "\n")
    print("Complete USB write and direct-read verification passed. Internal disk untouched.")


if __name__ == "__main__":
    main()
