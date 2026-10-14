#!/usr/bin/env python3
"""Local-only recovery preparation; public build payloads may go to Scherbius.

Never invokes sudo. Run prepare interactively after refreshing root-reference.tar.
Private material is decrypted only in XDG_RUNTIME_DIR (tmpfs), then removed.
"""
import argparse
import configparser
import contextlib
import getpass
import io
import json
import os
from pathlib import Path
import pty
import secrets
import select
import shutil
import socket
import subprocess
import tarfile
import tempfile
import time

from common import (FIXTURE, FIXTURE_SHA, HOME, LABEL, REPO, TARGET, USB, USER,
                    check_files, disk_inventory, match_disk, output,
                    partition_fingerprint, prepare_wifi, run, sha,
                    validate_manifest, write_private)

HERE = Path(__file__).resolve().parent
CACHE = Path(HOME) / ".cache/fedora-migration/guided"
STATE = Path(HOME) / ".local/state/fedora-migration"
ITEM = "251e6f68-a928-45f0-8670-b4e300b301fe"


def age_crypt(binary, source, destination, password, decrypt=False):
    """Give age its passphrase through a private controlling PTY, not argv/env.

    Never return terminal output: even unexpected echo must not reach logs.
    """
    pid, master = pty.fork()
    if pid == 0:
        os.execl(str(binary), str(binary), "-d" if decrypt else "-p", "-o", str(destination), str(source))
    pending = b""
    sent = 0
    deadline = time.monotonic() + 120
    try:
        while time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], 0.2)
            if ready:
                try:
                    data = os.read(master, 4096)
                except OSError:
                    break
                if not data:
                    break
                pending += data
                # age 1.3 uses these exact prompts. A changed tool fails closed.
                if b":" in pending and (b"Enter passphrase" in pending or b"Confirm passphrase" in pending):
                    if sent >= (1 if decrypt else 2):
                        raise RuntimeError("Unexpected encryption prompt")
                    os.write(master, password.encode() + b"\n")
                    sent += 1
                    pending = b""
            done, status = os.waitpid(pid, os.WNOHANG)
            if done:
                if os.waitstatus_to_exitcode(status) != 0:
                    raise RuntimeError("Bundle encryption or unlock failed")
                return
        done, status = os.waitpid(pid, os.WNOHANG)
        if not done:
            os.kill(pid, 15)
            os.waitpid(pid, 0)
            raise RuntimeError("Encryption prompt timed out")
        if os.waitstatus_to_exitcode(status) != 0:
            raise RuntimeError("Bundle encryption or unlock failed")
    finally:
        os.close(master)


def public_payload(destination):
    """Explicit allowlist: no vault templates, application data or private keys."""
    destination = Path(destination)
    if destination.exists():
        raise RuntimeError("Public payload destination already exists; use a new build directory")
    destination.mkdir(parents=True, mode=0o700)
    for name in ("common.py", "installer.py", "console.py", "firstboot.service", "resume"):
        shutil.copyfile(HERE / name, destination / name)
    shutil.copytree(HERE.parent / "ansible", destination / "ansible", ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    source = Path(output(["chezmoi", "source-path"]))
    commit = output(["git", "-C", source, "rev-parse", "HEAD"])
    # Files are drawn from the tracked public config set; read the current live
    # versions so unrelated newer Arch source-only profiles are not applied.
    tracked = output(["git", "-C", source, "ls-files", "private_dot_config/quickshell/berg",
                      "private_dot_config/hypr", "private_dot_config/uwsm", "private_dot_config/xdg-desktop-portal",
                      "private_dot_config/systemd/user"]).splitlines()
    entries = {}
    for name in tracked:
        parts = name.split("/")
        rel = Path(".config")
        for part in parts[1:]:
            for prefix in ("private_", "executable_"):
                part = part.removeprefix(prefix)
            rel /= part
        if rel.suffix == ".tmpl" or any(p.endswith(".wants") for p in rel.parts) or "rclone" in str(rel):
            continue
        live = Path(HOME) / rel
        if live.is_file() and not live.is_symlink() and "__pycache__" not in live.parts:
            entries[str(rel)] = live
    for name in ("codex", "arts-wallpaper"):
        entries[f".local/bin/{name}"] = Path(HOME) / f".local/bin/{name}"
    with tarfile.open(destination / "home-public.tar", "w") as archive:
        for name, path in sorted(entries.items()):
            archive.add(path, arcname=name, recursive=False)
    (destination / "code-commit").write_text(commit + "\n")
    print(f"Public payload prepared: {destination}. Add verified bin/ tools before hashing/building.")


def hashes(destination):
    root = Path(destination)
    values = {str(path.relative_to(root)): sha(path) for path in sorted(root.rglob("*"))
              if path.is_file() and path.name != "files.json"}
    (root / "files.json").write_text(json.dumps(values, indent=2, sort_keys=True) + "\n")
    print(check_files(root))


def root_inputs(archive, uuid):
    if archive.stat().st_mode & 0o077 or archive.stat().st_uid != os.getuid():
        raise RuntimeError("Root capture must be owned by you and mode 0600")
    if time.time() - archive.stat().st_mtime > 14400:
        raise RuntimeError("Refresh the protected root capture within the last four hours")
    with tarfile.open(archive) as stream:
        shadow = stream.extractfile("etc/shadow").read().decode()
        password = next(line.split(":")[1] for line in shadow.splitlines() if line.startswith(USER + ":"))
        selected = []
        for member in stream.getmembers():
            if member.isfile() and member.name.startswith("etc/NetworkManager/system-connections/"):
                try:
                    profile, candidate = prepare_wifi(stream.extractfile(member).read().decode())
                    if candidate == uuid:
                        selected.append(profile)
                except (configparser.Error, RuntimeError, UnicodeError):
                    continue
        if len(selected) != 1 or not password.startswith("$"):
            raise RuntimeError("Active Wi-Fi credentials or login password hash were not captured")
    return selected[0], password


def vault_item(env):
    return json.loads(output(["bw", "get", "item", ITEM], env=env))


def prepare(args):
    if socket.gethostname().split(".", 1)[0] != "rivest" or os.geteuid() == 0:
        raise RuntimeError("Prepare runs only as the existing Rivest user")
    payload = Path(args.payload).resolve()
    payload_sha = check_files(payload)
    if (payload / "lab_pre.py").exists():
        raise RuntimeError("Dummy rehearsal payloads cannot prepare a physical migration")
    runtime = Path(os.environ["XDG_RUNTIME_DIR"])
    if output(["findmnt", "-n", "-o", "FSTYPE", "-T", runtime]) != "tmpfs":
        raise RuntimeError("Private preparation requires a tmpfs runtime directory")
    os.umask(0o077)
    cache = Path(args.cache).resolve()
    # Keep every possible repository/image staging location under the excluded
    # cache tree, preventing a recovery repository from backing up itself.
    if not cache.is_relative_to(Path(HOME) / ".cache/fedora-migration"):
        raise RuntimeError("Preparation cache must remain inside the excluded migration cache")
    cache.mkdir(parents=True, exist_ok=True, mode=0o700)
    recovery = cache / "recovery"
    if (recovery / "manifest.json").exists():
        manifest = json.loads((recovery / "manifest.json").read_text())
        validate_manifest(manifest)
        if manifest["payload_sha256"] != payload_sha:
            raise RuntimeError("Verified preparation uses another payload; preserve it and use --cache with a new subdirectory")
        print("Recovery preparation already verified; pinned snapshot retained. Compose/write can continue.")
        return
    resuming = (recovery / "preparation.age").exists()
    if recovery.exists() and any(recovery.iterdir()) and not resuming:
        raise RuntimeError("Unrecognized incomplete preparation; preserve it and use --cache with a new subdirectory")
    if not resuming:
        uuid = output(["nmcli", "-t", "--escape", "no", "-f", "UUID,TYPE", "connection", "show", "--active"])
        candidates = [line.rsplit(":", 1)[0] for line in uuid.splitlines() if line.endswith(":802-11-wireless") or line.endswith(":wifi")]
        if len(candidates) != 1:
            raise RuntimeError("Exactly one active Wi-Fi profile must be selected")
        wifi, login_hash = root_inputs(STATE / "root-reference.tar", candidates[0])
    target = match_disk(disk_inventory(), TARGET)
    match_disk(disk_inventory(), USB, usb=True)
    session_file = runtime / "fedora-migration-bw-session"
    if not session_file.exists():
        raise RuntimeError("Unlock Bitwarden into the documented private runtime session file first")
    recovery.mkdir(mode=0o700, exist_ok=True)
    env = dict(os.environ, BW_SESSION=session_file.read_text().strip())
    try:
        with tempfile.TemporaryDirectory(prefix="rivest-private-", dir=runtime) as private_dir, contextlib.ExitStack() as cleanup:
            private = Path(private_dir)
            item = vault_item(env)
            original_password = item["login"]["password"]
            write_private(private / "nas-password", original_password)
            if resuming:
                fields = [f for f in (item.get("fields") or []) if f["name"] == "USB bootstrap passphrase"]
                if len(fields) != 1:
                    raise RuntimeError("Missing Bitwarden field for this incomplete preparation")
                passphrase = fields[0]["value"]
            else:
                passphrase = secrets.token_urlsafe(32)
                fields = item.get("fields") or []
                for field in fields:
                    if field["name"] == "USB bootstrap passphrase":
                        field["name"] += " (previous " + time.strftime("%Y%m%dT%H%M%S") + ")"
                fields.append({"name": "USB bootstrap passphrase", "value": passphrase, "type": 1})
                item["fields"] = fields
                encoded = output(["bw", "encode"], input=json.dumps(item).encode(), env=env)
                run(["bw", "edit", "item", ITEM], input=encoded.encode(), env=env, stdout=subprocess.DEVNULL)
            if not any(f.get("name") == "USB bootstrap passphrase" and f.get("value") == passphrase
                       for f in (vault_item(env).get("fields") or [])):
                raise RuntimeError("Bitwarden passphrase read-back failed")
            print('On your phone/personal laptop, open Bitwarden → Rivest migration backup → USB bootstrap passphrase.')
            if getpass.getpass("Enter that independently retrieved passphrase: ") != passphrase:
                raise RuntimeError("Independent recovery check did not match")
            # Authenticate before asking the user to close password managers.
            # The private master supports the whole backup/copy with no remote
            # agent forwarding and is closed before its runtime directory exits.
            ssh_control = private / "nas-ssh"
            run(["ssh", "-M", "-S", ssh_control, "-oControlPersist=3600", "-oForwardAgent=no",
                 "-oBatchMode=yes", "-oConnectTimeout=15", "-fN", "mediaserver"], stdin=subprocess.DEVNULL)
            cleanup.callback(subprocess.run, ["ssh", "-S", str(ssh_control), "-O", "exit", "mediaserver"],
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            sftp_args = f"-oControlPath={ssh_control} -oForwardAgent=no -oBatchMode=yes"
            backup_env = {k: v for k, v in os.environ.items() if not k.startswith("RESTIC_")}
            backup_env.update(RESTIC_PASSWORD_FILE=str(private / "nas-password"), RESTIC_SFTP_ARGS=sftp_args)
            if resuming:
                age_crypt(payload / "bin/age", recovery / "preparation.age", private / "pending.json", passphrase, decrypt=True)
                pending = json.loads((private / "pending.json").read_text())
                if pending["target"] != TARGET or pending["usb"] != USB or pending["payload_sha256"] != payload_sha or pending["partition_fingerprint"] != partition_fingerprint(target):
                    raise RuntimeError("Incomplete preparation belongs to another machine, payload or disk layout")
                snapshot, destination_password = pending["source_snapshot"], pending["restic_password"]
                wifi, login_hash = pending["wifi_keyfile"], pending["login_hash"]
                print("Resuming the existing pinned backup copy; no new source snapshot is taken.")
            else:
                if input("Close stateful apps now. Type BACKUP to take the final snapshot: ") != "BACKUP":
                    raise RuntimeError("Final backup not started")
                run([HERE / "restic.sh", "backup"], env=backup_env)
                logs = sorted(STATE.glob("backup-*.jsonl"), key=lambda p: p.stat().st_mtime)
                summaries = [json.loads(line) for line in logs[-1].read_text().splitlines() if json.loads(line).get("message_type") == "summary"]
                if len(summaries) != 1:
                    raise RuntimeError("No unique final backup summary")
                snapshot = summaries[0]["snapshot_id"]
                destination_password = secrets.token_hex(32)
                # Save encrypted credentials before the resumable copy starts.
                pending = dict(source_snapshot=snapshot, restic_password=destination_password,
                               wifi_keyfile=wifi, login_hash=login_hash,
                               payload_sha256=payload_sha, target=TARGET, usb=USB,
                               partition_fingerprint=partition_fingerprint(target))
                write_private(private / "pending.json", json.dumps(pending))
                age_crypt(payload / "bin/age", private / "pending.json", recovery / "preparation.age", passphrase)
            write_private(private / "usb-password", destination_password)
            restic = payload / "bin/restic"
            dest_env = dict(backup_env, RESTIC_PASSWORD_FILE=str(private / "usb-password"))
            repository = recovery / "repository"
            if not (repository / "config").exists():
                run([restic, "-o", f"sftp.args={sftp_args}", "-r", repository, "init", "--from-repo", REPO, "--from-password-file", private / "nas-password", "--copy-chunker-params"], env=dest_env)
            run([restic, "-o", f"sftp.args={sftp_args}", "-r", repository, "copy", "--from-repo", REPO, "--from-password-file", private / "nas-password", snapshot], env=dest_env)
            copied = json.loads(output([restic, "-r", repository, "snapshots", "--json"], env=dest_env))
            if len(copied) != 1 or copied[0].get("original") != snapshot:
                raise RuntimeError("Copied snapshot does not identify the pinned source snapshot")
            run([restic, "-r", repository, "check", "--read-data"], env=dest_env)
            fixture = private / "fixture"
            run([restic, "-r", repository, "restore", copied[0]["id"], "--include", FIXTURE, "--target", fixture, "--verify"], env=dest_env)
            if sha(fixture / FIXTURE.lstrip("/")) != FIXTURE_SHA:
                raise RuntimeError("USB repository fixture differs")
            manifest = dict(schema=1, user=USER, uid=1000, target=TARGET, usb=USB,
                            partition_fingerprint=partition_fingerprint(target), source_snapshot=snapshot,
                            usb_snapshot=copied[0]["id"], payload_sha256=payload_sha,
                            code_commit=(payload / "code-commit").read_text().strip(), independent_recovery_confirmed=True)
            validate_manifest(manifest)
            bundle = dict(manifest=manifest, wifi_keyfile=wifi, login_hash=login_hash, restic_password=destination_password)
            write_private(private / "bundle.json", json.dumps(bundle))
            age_crypt(payload / "bin/age", private / "bundle.json", recovery / "bootstrap.age", passphrase)
            age_crypt(payload / "bin/age", recovery / "bootstrap.age", private / "readback.json", passphrase, decrypt=True)
            if (private / "readback.json").read_bytes() != (private / "bundle.json").read_bytes():
                raise RuntimeError("Encrypted bundle read-back differs")
            write_private(recovery / "manifest.json", json.dumps(manifest, indent=2) + "\n")
            write_private(STATE / "guided-preparation.json", json.dumps(manifest, indent=2) + "\n")
            print("Final backup, independent unlock and encrypted USB recovery data verified.")
    finally:
        session_file.unlink(missing_ok=True)
        env.pop("BW_SESSION", None)


def compose(args):
    iso = Path(args.iso).resolve()
    root = Path(args.recovery).resolve()
    image = Path(args.output).resolve()
    payload = Path(args.payload).resolve()
    payload_sha = check_files(payload)
    if not iso.is_file() or not root.is_dir() or image.exists():
        raise RuntimeError("Need an existing custom ISO/recovery directory and a new output path")
    manifest = json.loads((root / "manifest.json").read_text())
    validate_manifest(manifest)
    if manifest["payload_sha256"] != payload_sha:
        raise RuntimeError("Recovery bundle belongs to another public payload")
    with tempfile.TemporaryDirectory(prefix="iso-payload-", dir=image.parent) as scratch:
        embedded = Path(scratch) / "files.json"
        run(["xorriso", "-osirrox", "on", "-indev", iso, "-extract", "/migration-payload/files.json", embedded],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if sha(embedded) != payload_sha:
            raise RuntimeError("ISO and recovery payload do not match")
    size = USB["size"]
    start = ((iso.stat().st_size + 1048575) // 1048576) * 2048
    end = (size // 512 - 2048) // 2048 * 2048 - 1
    fs_size = (end - start + 1) * 512
    data_size = sum(p.stat().st_size for p in root.rglob("*") if p.is_file())
    if data_size * 1.1 + 268435456 > fs_size:
        raise RuntimeError("Encrypted recovery copy does not fit this USB")
    shutil.copyfile(iso, image)
    image.chmod(0o600)
    with image.open("r+b") as stream:
        stream.truncate(size)
    table = json.loads(output(["sfdisk", "--json", image]))["partitiontable"]
    # Lorax 44 replays ISO9660 + EFI as two partitions; the original Fedora ISO
    # has a third small boot partition. Reserve partition 4 in either layout.
    if len(table["partitions"]) not in (2, 3) or table["label"] != "gpt":
        raise RuntimeError("Unexpected netinstaller GPT boot layout")
    if table["partitions"][1]["type"].upper() != "C12A7328-F81F-11D2-BA4B-00A0C93EC93B":
        raise RuntimeError("Expected the preserved EFI system partition")
    if max(p["start"] + p["size"] for p in table["partitions"]) > start:
        raise RuntimeError("Recovery partition would overlap installer content")
    run(["sgdisk", "-e", image])
    run(["sgdisk", f"-n4:{start}:{end}", "-t4:8300", "-c4:Rivest encrypted recovery", image])
    filesystem = image.with_suffix(".recovery.ext4")
    if filesystem.exists():
        raise RuntimeError("Recovery filesystem staging file already exists")
    try:
        with filesystem.open("xb") as stream:
            stream.truncate(fs_size)
        run(["mke2fs", "-q", "-t", "ext4", "-m", "0", "-L", LABEL, "-d", root, filesystem])
        with image.open("r+b") as dest, filesystem.open("rb") as source:
            dest.seek(start * 512)
            shutil.copyfileobj(source, dest, 8 * 1024 * 1024)
            dest.flush()
            os.fsync(dest.fileno())
    finally:
        filesystem.unlink(missing_ok=True)
    run(["sgdisk", "-v", image])
    # GPT relocation changes bytes covered by Fedora's ISO media checksum.
    # Refresh only after all partition writes, then require the real checker.
    run([payload / "bin/implantisomd5", "--force", image], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
    run([payload / "bin/checkisomd5", image], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    write_private(str(image) + ".json", json.dumps(dict(image_bytes=size, sha256=sha(image), iso_sha256=sha(iso),
                  usb=USB, payload_sha256=payload_sha, rehearsal=(payload / "lab_pre.py").exists(),
                  source_snapshot=manifest["source_snapshot"], usb_snapshot=manifest["usb_snapshot"],
                  recovery_start_sector=start, recovery_end_sector=end), indent=2) + "\n")
    print(f"Composed {image}; complete checksum saved beside it. No physical device was written.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("public"); p.add_argument("destination")
    p = sub.add_parser("hashes"); p.add_argument("destination")
    p = sub.add_parser("prepare"); p.add_argument("--payload", required=True); p.add_argument("--cache", default=str(CACHE))
    p = sub.add_parser("compose")
    p.add_argument("--iso", required=True); p.add_argument("--recovery", required=True); p.add_argument("--output", required=True); p.add_argument("--payload", required=True)
    sub.add_parser("status")
    args = parser.parse_args()
    if args.command == "public": public_payload(args.destination)
    elif args.command == "hashes": hashes(args.destination)
    elif args.command == "prepare": prepare(args)
    elif args.command == "compose": compose(args)
    else:
        print((STATE / "guided-preparation.json").read_text() if (STATE / "guided-preparation.json").exists() else "Guided USB recovery preparation is pending.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Preparation stopped: {type(error).__name__}.")
        if isinstance(error, RuntimeError):
            print(str(error))
        raise SystemExit(1)
