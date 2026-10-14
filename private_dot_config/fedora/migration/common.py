"""Shared, non-destructive validation for Rivest's migration tooling."""
import configparser
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

USER = "vitorpy"
HOME = "/home/vitorpy"
LABEL = "RIVEST_RECOVERY"
REPO = "sftp:mediaserver:/mnt/media/backups/rivest-restic"
TARGET = {"model": "WD PC SN5000S SDEPTSJ-512G", "serial": "25343C801463", "size": 512110190592}
USB = {"serial": "03021830022221114151", "size": 15376000000}
FIXTURE = HOME + "/.local/state/fedora-migration/restore-fixture/record.txt"
FIXTURE_SHA = "e7eb1d6fb7fae35e74c9867bfbee0b9de221242b3484af40edebf06f89f4a775"


def run(args, **kwargs):
    # Do not include command arguments in exceptions: some tools handle secrets.
    result = subprocess.run([str(a) for a in args], check=False, **kwargs)
    if result.returncode:
        raise RuntimeError(f"{Path(args[0]).name} failed (exit {result.returncode})")
    return result


def output(args, **kwargs):
    return run(args, stdout=subprocess.PIPE, **kwargs).stdout.decode().strip()


def sha(path):
    with open(path, "rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_private(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.is_symlink():
        raise OSError("Refusing a symlink for private state")
    fd, temporary = tempfile.mkstemp(prefix="." + path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(value)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        Path(temporary).unlink(missing_ok=True)


def disk_inventory():
    return json.loads(output(["lsblk", "--json", "--bytes", "--paths", "--output",
                              "NAME,TYPE,MODEL,SERIAL,SIZE,TRAN,RM,MOUNTPOINTS,UUID,PARTUUID,PARTTYPE,FSTYPE"]))["blockdevices"]


def match_disk(disks, identity, usb=False):
    matches = [d for d in disks if d["type"] == "disk" and
               (d.get("serial") or "").strip() == identity["serial"] and
               int(d["size"]) == identity["size"] and
               ("model" not in identity or (d.get("model") or "").strip() == identity["model"])]
    if len(matches) != 1:
        raise RuntimeError("Expected exactly one disk matching the recorded serial, model and capacity")
    disk = matches[0]
    if usb and (disk.get("tran") != "usb" or not disk.get("rm")):
        raise RuntimeError("Recovery target is not a removable USB disk")
    if not usb and disk.get("tran") != "nvme":
        raise RuntimeError("Installation target is not the recorded internal NVMe")
    return disk


def partition_fingerprint(disk):
    # Mount points and dynamically discovered device names are deliberately absent.
    partitions = [{key: child.get(key) for key in
                   ("size", "uuid", "partuuid", "parttype", "fstype")}
                  for child in disk.get("children", [])]
    return hashlib.sha256(json.dumps(partitions, sort_keys=True).encode()).hexdigest()


def validate_manifest(manifest):
    if manifest.get("schema") != 1 or manifest.get("user") != USER or manifest.get("uid") != 1000:
        raise RuntimeError("Unsupported recovery manifest or user identity")
    for key in ("source_snapshot", "usb_snapshot", "payload_sha256", "partition_fingerprint"):
        if not re.fullmatch(r"[0-9a-f]{64}", manifest.get(key, "")):
            raise RuntimeError("Missing full snapshot or artifact identity")
    if manifest.get("target") != TARGET or manifest.get("usb") != USB:
        raise RuntimeError("Recovery manifest belongs to a different machine or USB")
    if not manifest.get("independent_recovery_confirmed"):
        raise RuntimeError("Independent recovery confirmation is missing")


def prepare_wifi(keyfile):
    profile = configparser.ConfigParser(interpolation=None, strict=True)
    profile.read_string(keyfile)
    if profile.get("connection", "type") not in ("wifi", "802-11-wireless"):
        raise RuntimeError("The selected profile is not wireless")
    security = next((s for s in ("wifi-security", "802-11-wireless-security") if profile.has_section(s)), None)
    if not security or profile.get(security, "key-mgmt") not in ("wpa-psk", "sae"):
        raise RuntimeError("Only the captured WPA personal profile is supported")
    if not profile.get(security, "psk", fallback=""):
        raise RuntimeError("The wireless password was not captured")
    profile.remove_option("connection", "interface-name")
    profile.remove_option("connection", "permissions")
    profile.set("connection", "autoconnect", "true")
    profile.set(security, "psk-flags", "0")
    for section in ("wifi", "802-11-wireless"):
        if profile.has_section(section):
            profile.remove_option(section, "mac-address")
    import io
    stream = io.StringIO()
    profile.write(stream, space_around_delimiters=False)
    return stream.getvalue(), profile.get("connection", "uuid")


def check_files(root):
    root = Path(root)
    hashes = json.loads((root / "files.json").read_text())
    for name, expected in hashes.items():
        path = root / name
        if Path(name).is_absolute() or ".." in Path(name).parts or path.is_symlink() or sha(path) != expected:
            raise RuntimeError("Public payload integrity check failed")
    return sha(root / "files.json")


def restic_env(password_file):
    env = {k: v for k, v in os.environ.items() if not k.startswith("RESTIC_")}
    env.update(RESTIC_PASSWORD_FILE=str(password_file), RESTIC_CACHE_DIR="/run/rivest-migration/restic-cache")
    return env
