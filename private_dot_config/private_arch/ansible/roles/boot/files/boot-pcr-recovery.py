#!/usr/bin/env python3
"""Preserve the signed pre-PCR boot state once, or explicitly restore it."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify_signed(path):
    report = json.loads(subprocess.check_output(
        ["sbctl", "verify", "--json", str(path)], text=True
    ))
    if not any(row.get("file_name") == str(path) and row.get("is_signed") == 1
               for row in report):
        raise ValueError(f"Secure Boot signature verification failed: {path}")


def snapshot(paths, optional, destination):
    """Publish a complete snapshot atomically; never replace an existing one."""
    manifest_path = destination / "manifest.json"
    if destination.exists():
        manifest = json.loads(manifest_path.read_text())
        if set(manifest) != {str(path) for path in paths}:
            raise ValueError("Backup paths differ from the requested boot configuration")
        for name, record in manifest.items():
            if record is not None and digest(destination / "files" / name.lstrip("/")) != record["sha256"]:
                raise ValueError(f"Backup checksum mismatch: {name}")
        return manifest, False

    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    staging = Path(tempfile.mkdtemp(prefix=".pre-pcr-", dir=destination.parent))
    try:
        manifest = {}
        for source in paths:
            if source.is_symlink():
                raise ValueError(f"Refusing a symlink in the boot snapshot: {source}")
            if source == optional and not source.exists():
                manifest[str(source)] = None
                continue
            target = staging / "files" / str(source).lstrip("/")
            target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            shutil.copyfile(source, target)
            target.chmod(0o600)
            source_hash = digest(source)
            if digest(target) != source_hash:
                raise ValueError(f"Backup checksum mismatch: {source}")
            manifest[str(source)] = {"sha256": source_hash, "mode": source.stat().st_mode & 0o777}
        (staging / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        (staging / "manifest.json").chmod(0o600)
        os.rename(staging, destination)
        return manifest, True
    finally:
        if staging.exists():
            shutil.rmtree(staging)


def copy_once(source, destination, expected_hash):
    if destination.exists():
        if destination.is_symlink() or digest(destination) != expected_hash:
            raise ValueError(f"Existing rescue image differs from preserved boot image: {destination}")
        return False
    # Exclusive creation avoids ever replacing a separately created rescue image.
    with destination.open("xb") as target, source.open("rb") as original:
        shutil.copyfileobj(original, target)
    if digest(destination) != expected_hash:
        raise ValueError("Rescue image checksum mismatch; refusing to continue")
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--default", required=True)
    parser.add_argument("--fallback", required=True)
    parser.add_argument("--kernel", required=True)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--restore", action="store_true")
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error("Run as root to inspect or preserve the root-only ESP")
    if args.check and args.restore:
        parser.error("--check and --restore are mutually exclusive")
    if not args.kernel.replace("-", "").isalnum():
        parser.error("Invalid kernel package name")

    default, fallback = Path(args.default), Path(args.fallback)
    rescue = Path("/boot/EFI/Linux/arch-linux-pre-pcr.efi")
    entry = Path("/boot/loader/entries/arch-pre-pcr.conf")
    backup = Path("/var/lib/arch-boot/pre-pcr")
    uki_config = Path("/etc/kernel/uki.conf")
    paths = [default, fallback, Path("/etc/mkinitcpio.conf"),
             Path(f"/etc/mkinitcpio.d/{args.kernel}.preset"), Path("/etc/kernel/cmdline"),
             uki_config, Path("/etc/fstab"), Path("/boot/loader/loader.conf"),
             Path("/boot/loader/entries/arch.conf"), Path("/boot/loader/entries/arch-fallback.conf"),
             Path("/boot/EFI/systemd/systemd-bootx64.efi"), Path("/boot/EFI/BOOT/BOOTX64.EFI")]
    if default == rescue or fallback == rescue or len(set(paths)) != len(paths):
        raise ValueError("Managed UKI and recovery paths must be distinct")

    if not backup.exists():
        if args.restore:
            raise ValueError("No pre-PCR snapshot to restore")
        if rescue.exists() or entry.exists():
            raise ValueError("Rescue files already exist without a matching snapshot")
        verify_signed(default)
        verify_signed(fallback)
        for path in paths:
            if path != uki_config and not path.is_file():
                raise ValueError(f"Required boot file is missing: {path}")
        required = sum(path.stat().st_size for path in (default, fallback))
        if shutil.disk_usage(rescue.parent).free < required:
            raise ValueError("Insufficient ESP space for the rescue UKI and rebuild headroom")
        if args.check:
            print(json.dumps({"changed": True, "backup": str(backup)}))
            return

    manifest, changed = snapshot(paths, uki_config, backup)
    if args.restore:
        # snapshot() verifies every backup hash before restoring any file.
        for name, record in manifest.items():
            target = Path(name)
            if target.is_symlink():
                raise ValueError(f"Refusing to restore over a symlink: {target}")
            if record is None:
                target.unlink(missing_ok=True)
            else:
                shutil.copyfile(backup / "files" / name.lstrip("/"), target)
                target.chmod(record["mode"])
        verify_signed(default)
        verify_signed(fallback)
        print(json.dumps({"changed": True, "restored": str(backup)}))
        return

    expected_hash = manifest[str(default)]["sha256"]
    entry_content = "title   Arch Linux — before PCR signing\nefi     /EFI/Linux/arch-linux-pre-pcr.efi\n"
    if entry.exists() and (entry.is_symlink() or entry.read_text() != entry_content):
        raise ValueError("Existing rescue loader entry differs; refusing to overwrite it")
    if args.check:
        if rescue.exists():
            if digest(rescue) != expected_hash:
                raise ValueError("Rescue checksum differs from backup")
            verify_signed(rescue)
        print(json.dumps({"changed": not rescue.exists() or not entry.exists(), "backup": str(backup)}))
        return
    changed |= copy_once(backup / "files" / str(default).lstrip("/"), rescue, expected_hash)
    verify_signed(rescue)
    if not entry.exists():
        with entry.open("x") as stream:
            stream.write(entry_content)
        changed = True
    print(json.dumps({"changed": changed, "backup": str(backup), "rescue": str(rescue)}))


if __name__ == "__main__":
    main()
