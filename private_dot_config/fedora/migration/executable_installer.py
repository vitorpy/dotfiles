#!/usr/bin/env python3
"""Installer guard, verified home restore, and resumable Fedora provisioning.

Only pre() can generate partitioning instructions. Installed status/provision
commands have no formatting path. Private inputs live in /run, never the journal.
"""
import configparser
import fcntl
import getpass
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile

from common import (FIXTURE, FIXTURE_SHA, HOME, LABEL, TARGET, USB, USER,
                    check_files, disk_inventory, match_disk, output,
                    partition_fingerprint, prepare_wifi, restic_env, run, sha,
                    validate_manifest, write_private)

RAM = Path("/run/rivest-migration")
STATE = Path("/var/lib/rivest-migration")
DEST = Path("/opt/rivest-migration")
REACH = "https://dl.fedoraproject.org/pub/fedora/linux/releases/44/Everything/x86_64/os/repodata/repomd.xml"


def require_fedora():
    text = Path("/etc/os-release").read_text()
    if os.geteuid() != 0 or not re.search(r'^ID=["\']?fedora["\']?$', text, re.M) or not re.search(r'^VERSION_ID=["\']?44["\']?$', text, re.M):
        raise RuntimeError("Requires root inside Fedora 44")


def mark(state, name):
    write_private(state / name, "verified\n")


def media_mount():
    partitions = json.loads(output(["lsblk", "-J", "-p", "-o", "NAME,LABEL"]))["blockdevices"]
    found = []
    def visit(nodes):
        for node in nodes:
            if node.get("label") == LABEL:
                found.append(node["name"])
            visit(node.get("children", []))
    visit(partitions)
    if len(found) != 1:
        raise RuntimeError("Exactly one recovery partition is required")
    base = RAM / "media"
    base.mkdir(parents=True, exist_ok=True)
    run(["mount", "-o", "ro,nosuid,nodev,noexec", found[0], base])
    # The recovery partition must belong to the same authorized physical USB.
    usb = match_disk(disk_inventory(), USB, usb=True)
    if found[0] not in [c["name"] for c in usb.get("children", [])]:
        raise RuntimeError("Recovery partition is not on the recorded USB")
    return base


def unlock(base, payload):
    bundle_path = RAM / "bundle.json"
    while True:
        print("Unlock the encrypted recovery bundle (passphrase from Bitwarden).", flush=True)
        result = subprocess.run([str(payload / "bin/age"), "-d", "-o", str(bundle_path), str(base / "bootstrap.age")])
        if result.returncode == 0:
            break
        bundle_path.unlink(missing_ok=True)
        if input("Unlock failed. Type RETRY to try again: ") != "RETRY":
            raise RuntimeError("Recovery bundle remains locked")
    bundle_path.chmod(0o600)
    bundle = json.loads(bundle_path.read_text())
    manifest = json.loads((base / "manifest.json").read_text())
    validate_manifest(manifest)
    if bundle["manifest"] != manifest or check_files(payload) != manifest["payload_sha256"]:
        raise RuntimeError("Bundle, manifest and public installer do not agree")
    write_private(RAM / "password", bundle["restic_password"])
    return manifest, bundle


def wifi_connect(bundle):
    profile, uuid = prepare_wifi(bundle["wifi_keyfile"])
    path = Path("/run/NetworkManager/system-connections/rivest-migration.nmconnection")
    write_private(path, profile)
    # Keep a private normalized copy for the installed system.
    write_private(RAM / "wifi.nmconnection", profile)
    run(["nmcli", "connection", "load", path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    run(["nmcli", "radio", "wifi", "on"])
    while True:
        devices = output(["nmcli", "-t", "--escape", "no", "-f", "DEVICE,TYPE", "device"]).splitlines()
        wireless = [line.rsplit(":", 1)[0] for line in devices if line.endswith(":wifi")]
        ok = False
        for device in wireless:
            result = subprocess.run(["nmcli", "--wait", "45", "connection", "up", "uuid", uuid, "ifname", device],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if result.returncode == 0:
                ok = True
                break
        if ok and subprocess.run(["curl", "-fLsS", "--connect-timeout", "15", "--max-time", "45", "-o", "/dev/null", REACH],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
            return
        print("Wi-Fi or Fedora repository access failed. Correct the connection, then retry.")
        choice = input("Type EDIT to edit Wi-Fi, RETRY to reconnect, or anything else to stop: ")
        if choice == "EDIT" and shutil.which("nmtui"):
            run(["nmtui"])
            # Export the successfully selected keyfile below; don't persist an old password.
            active = output(["nmcli", "-g", "GENERAL.CON-UUID", "device", "show", wireless[0]]) if wireless else ""
            if active:
                uuid = active
                for directory in (Path("/run/NetworkManager/system-connections"), Path("/etc/NetworkManager/system-connections")):
                    for candidate in directory.glob("*"):
                        try:
                            text, candidate_uuid = prepare_wifi(candidate.read_text())
                            if candidate_uuid == uuid:
                                write_private(RAM / "wifi.nmconnection", text)
                        except (ValueError, configparser.Error, RuntimeError):
                            continue
        elif choice == "EDIT":
            # The minimal installer may lack nmtui. Capture PSK with hidden input,
            # never nmcli argv or an echoing connection editor.
            edited = configparser.ConfigParser(interpolation=None)
            edited.read_string((RAM / "wifi.nmconnection").read_text())
            section = next(s for s in ("wifi", "802-11-wireless") if edited.has_section(s))
            security = next(s for s in ("wifi-security", "802-11-wireless-security") if edited.has_section(s))
            ssid = input("Wi-Fi name (empty retains the captured network): ")
            if ssid:
                edited.set(section, "ssid", ssid)
            edited.set(security, "psk", getpass.getpass("Wi-Fi password: "))
            import io
            buffer = io.StringIO()
            edited.write(buffer, space_around_delimiters=False)
            profile, uuid = prepare_wifi(buffer.getvalue())
            write_private(path, profile)
            write_private(RAM / "wifi.nmconnection", profile)
            run(["nmcli", "connection", "load", path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        elif choice != "RETRY":
            raise RuntimeError("Network readiness not confirmed")


def verify_repository(base, payload, manifest):
    restic = payload / "bin/restic"
    env = restic_env(RAM / "password")
    args = [restic, "-r", base / "repository"]
    run(args + ["check"], env=env)
    snapshots = json.loads(output(args + ["snapshots", "--json", manifest["usb_snapshot"]], env=env))
    if len(snapshots) != 1 or snapshots[0]["id"] != manifest["usb_snapshot"] or HOME not in snapshots[0]["paths"]:
        raise RuntimeError("Pinned recovery snapshot or home path is missing")
    fixture = RAM / "fixture"
    run(args + ["restore", manifest["usb_snapshot"], "--include", FIXTURE, "--target", fixture, "--verify"], env=env)
    if sha(fixture / FIXTURE.lstrip("/")) != FIXTURE_SHA:
        raise RuntimeError("Recovery fixture verification failed")


def pre(payload):
    require_fedora()
    if "inst.ks=" not in Path("/proc/cmdline").read_text() or not Path("/run/install").is_dir():
        raise RuntimeError("Destructive preparation is confined to the Fedora installer")
    os.umask(0o077)
    RAM.mkdir(mode=0o700, exist_ok=True)
    run(["findmnt", "-n", "-t", "tmpfs", "/run"], stdout=subprocess.DEVNULL)
    base = media_mount()
    manifest, bundle = unlock(base, payload)
    wifi_connect(bundle)
    verify_repository(base, payload, manifest)
    disk = match_disk(disk_inventory(), TARGET)
    if partition_fingerprint(disk) != manifest["partition_fingerprint"]:
        raise RuntimeError("Internal partitions changed; refusing a fresh install or accidental reinstallation")
    if Path(disk["name"]).name not in ("nvme0n1", "nvme1n1"):
        raise RuntimeError("Unexpected NVMe device name")
    print(f"\nERASE {disk['name']}: {TARGET['model']}, serial {TARGET['serial']}, {TARGET['size']} bytes")
    print(f"Verified USB snapshot {manifest['usb_snapshot']}; NAS snapshot retained: {manifest['source_snapshot']}")
    if input("Type the entire internal disk serial to authorize erasure: ").strip() != TARGET["serial"]:
        raise RuntimeError("Disk erase confirmation did not match")
    while True:
        password = getpass.getpass("New LUKS disk-encryption passphrase: ")
        confirmation = getpass.getpass("Repeat LUKS passphrase: ")
        if password == confirmation and len(password) >= 12 and not any(c in password for c in "\r\n\x00"):
            break
        print("Use matching passphrases of at least 12 characters, without line breaks.")
    login_hash = bundle["login_hash"]
    if not re.fullmatch(r"\$[A-Za-z0-9./$=,+_-]+", login_hash):
        raise RuntimeError("Captured password hash is malformed")
    name = Path(disk["name"]).name
    write_private(RAM / "confirmed.ks", "\n".join([
        f"ignoredisk --only-use={name}", "zerombr", f"clearpart --all --initlabel --drives={name}",
        f"autopart --type=btrfs --encrypted --passphrase={shlex.quote(password)}",
        f"user --name={USER} --uid=1000 --gid=1000 --groups=wheel --password={shlex.quote(login_hash)} --iscrypted",
        "network --hostname=rivest", ""]))
    write_private(RAM / "payload-path", str(payload))
    print("Prerequisites passed. Starting Fedora installation.", flush=True)


def merge_home(staging, target, payload):
    home = target / HOME.lstrip("/")
    source = staging / HOME.lstrip("/")
    if not source.is_dir():
        raise RuntimeError("Restored home is missing")
    run(["rsync", "-aHAX", "--numeric-ids", str(source) + "/", str(home) + "/"])
    reference = home / ".local/state/fedora-migration/arch-session-reference"
    reference.mkdir(parents=True, exist_ok=True, mode=0o700)
    for relative in (".config/systemd/user", ".local/share/dbus-1/services", ".config/environment.d", ".config/uwsm", ".dmrc"):
        old = home / relative
        saved = reference / relative
        if old.exists() or old.is_symlink():
            saved.parent.mkdir(parents=True, exist_ok=True)
            if saved.exists() or saved.is_symlink():
                # A retry first restores the original home again. Keep the first
                # reference, but never leave restored Arch activation in place.
                if old.is_dir() and not old.is_symlink():
                    shutil.rmtree(old)
                else:
                    old.unlink()
            else:
                old.rename(saved)
    # Overlay only the explicitly reviewed public dotfiles; never template secrets.
    with tarfile.open(payload / "home-public.tar") as archive:
        archive.extractall(home, filter="data")
    # Default first login to Plasma, retaining any former choice in the reference.
    write_private(home / ".dmrc", "[Desktop]\nSession=plasma\n")
    run(["chown", "-R", "1000:1000", reference])
    with tarfile.open(payload / "home-public.tar") as archive:
        for member in archive.getmembers():
            destination = home / member.name
            if not destination.is_symlink():
                os.chown(destination, 1000, 1000)
    os.chown(home / ".dmrc", 1000, 1000)


def post(payload):
    require_fedora()
    target = Path("/mnt/sysroot")
    if not (target / "etc/fedora-release").is_file():
        raise RuntimeError("Installed Fedora root was not mounted")
    state = target / STATE.relative_to("/")
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    base = RAM / "media"
    manifest = json.loads((base / "manifest.json").read_text())
    validate_manifest(manifest)
    destination = target / DEST.relative_to("/")
    shutil.copytree(payload, destination, dirs_exist_ok=True)
    run(["chown", "-R", "0:0", destination])
    write_private(state / "manifest.json", json.dumps(manifest))
    shutil.copyfile(RAM / "wifi.nmconnection", target / "etc/NetworkManager/system-connections/rivest-migration.nmconnection")
    (target / "etc/NetworkManager/system-connections/rivest-migration.nmconnection").chmod(0o600)
    # Install resume machinery before restoring, so an interrupted restore has a
    # recovery path and the desktop cannot race a partial home merge.
    shutil.copyfile(payload / "firstboot.service", target / "etc/systemd/system/rivest-migration.service")
    run(["systemctl", "--root", target, "enable", "rivest-migration.service"])
    launcher = target / "usr/local/bin/rivest-migration"
    shutil.copyfile(payload / "resume", launcher)
    launcher.chmod(0o755)
    dropin = target / "etc/systemd/system/display-manager.service.d/migration.conf"
    dropin.parent.mkdir(parents=True, exist_ok=True)
    dropin.write_text("[Unit]\nRequires=rivest-migration.service\nAfter=rivest-migration.service\n")
    restore_home(target, payload, base, manifest)
    # Upgrade KDE before the current COPR stack is added, avoiding the release /
    # updates KMime file conflict seen in the earlier rehearsal.
    run(["chroot", target, "dnf", "-y", "upgrade", "--refresh"])
    mark(state, "updated")
    (target / "etc/plasma-setup-done").touch()
    run(["chroot", target, "restorecon", "-RF", HOME, "/etc/NetworkManager/system-connections", str(DEST), str(STATE)])
    # Anaconda is booted with inst.nosave=all. Remove temporary KS and secrets as
    # soon as restore and installation have succeeded.
    for name in ("bundle.json", "password", "confirmed.ks"):
        (RAM / name).unlink(missing_ok=True)


def restore_home(target, payload, base, manifest):
    state = target / STATE.relative_to("/")
    if (state / "home-restored").exists():
        return
    staging = state / "restore"
    run([payload / "bin/restic", "-r", base / "repository", "restore", manifest["usb_snapshot"],
         "--target", staging, "--verify"], env=restic_env(RAM / "password"))
    if sha(staging / FIXTURE.lstrip("/")) != FIXTURE_SHA:
        raise RuntimeError("Restored home fixture differs")
    merge_home(staging, target, payload)
    mark(state, "home-restored")


def provision():
    require_fedora()
    if not STATE.is_dir():
        raise RuntimeError("This is not an installed Rivest migration")
    # Keep this descriptor until process exit: service and manual retries must
    # never race DNF, Flatpak or a partially merged home.
    global _provision_lock
    _provision_lock = (STATE / "provision.lock").open("a")
    try:
        fcntl.flock(_provision_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise RuntimeError("Provisioning is already running; inspect its journal first") from None
    if (STATE / "complete").exists():
        print("Migration already complete; no changes made.")
        return
    if not (STATE / "home-restored").exists():
        RAM.mkdir(mode=0o700, exist_ok=True)
        base = media_mount()
        manifest, _ = unlock(base, DEST)
        if json.loads((STATE / "manifest.json").read_text()) != manifest:
            raise RuntimeError("Recovery USB does not match the interrupted installation")
        verify_repository(base, DEST, manifest)
        restore_home(Path("/"), DEST, base, manifest)
        for name in ("bundle.json", "password"):
            (RAM / name).unlink(missing_ok=True)
    if not (STATE / "updated").exists():
        run(["dnf", "-y", "upgrade", "--refresh"])
        mark(STATE, "updated")
    ansible = DEST / "ansible"
    env = dict(os.environ, ANSIBLE_CONFIG=str(ansible / "ansible.cfg"), ANSIBLE_NOCOLOR="1")
    # A separate user bus supports Flatpak before a graphical login. Nothing from
    # the restored user's shell startup is sourced by this root controller.
    run(["systemctl", "start", "user@1000.service"])
    env.update(XDG_RUNTIME_DIR="/run/user/1000", DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus")
    run(["ansible-playbook", "-i", ansible / "inventory.ini", ansible / "site.yml", "--limit", "rivest",
         "-e", "fedora_corporate=true", "-e", "fedora_full_parity=true"], env=env, cwd=ansible)
    mark(STATE, "provisioned")
    # Enable reviewed session-scoped units only. Arch wants/ directories were
    # quarantined before this public unit set was installed.
    user_env = ["runuser", "-u", USER, "--", "env", "XDG_RUNTIME_DIR=/run/user/1000",
                "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus", "systemctl", "--user"]
    run(user_env + ["daemon-reload"])
    run(user_env + ["enable", "berg-crash-watch.service", "hypridle.service", "hyprpaper.service",
                    "hyprpolkitagent.service", "hyprsunset.service", "quickshell-berg.service",
                    "arts-wallpaper.timer", "quickshell-berg-weather.timer"])
    # Recover only artwork data from the old root reference, never its services.
    archive = Path(HOME) / ".local/state/fedora-migration/root-reference.tar"
    if archive.exists() and not (STATE / "artwork-restored").exists():
        scratch = STATE / "artwork"
        scratch.mkdir(exist_ok=True)
        with tarfile.open(archive) as stream:
            members = [m for m in stream.getmembers() if m.name.startswith("var/lib/arts-wallpaper/")]
            stream.extractall(scratch, members=members, filter="data")
        old = scratch / "var/lib/arts-wallpaper"
        if old.is_dir():
            run(["rsync", "-aH", str(old) + "/", "/var/lib/arts-wallpaper/"])
            run(["chown", "-R", "vitorpy:arts-wallpaper", "/var/lib/arts-wallpaper"])
        mark(STATE, "artwork-restored")
    run(["restorecon", "-RF", HOME, "/var/lib/arts-wallpaper"])
    for executable in ("/usr/local/bin/codex", "/usr/local/bin/bitwarden-desktop", "/usr/bin/qs",
                       "/usr/bin/Hyprland", "/usr/libexec/xdg-desktop-portal-hyprland"):
        if not os.access(executable, os.X_OK):
            raise RuntimeError("A required desktop executable is missing")
    if output(["getenforce"]) != "Enforcing":
        raise RuntimeError("SELinux must remain enforcing")
    mark(STATE, "complete")
    print("Migration complete. Sign into Plasma first; select Hyprland after logging out.")


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "status"
    if command == "status":
        if os.geteuid() != 0:
            raise RuntimeError("Installed phase status requires root: sudo rivest-migration status")
        for phase in ("home-restored", "updated", "provisioned", "artwork-restored", "complete"):
            print(f"{phase}: {'verified' if (STATE / phase).exists() else 'pending'}")
    elif command in ("provision", "resume"):
        provision()
        if command == "resume":
            run(["systemctl", "reset-failed", "rivest-migration.service", "display-manager.service"])
            run(["systemctl", "start", "display-manager.service"])
    elif command in ("pre", "post") and len(sys.argv) == 3:
        globals()[command](Path(sys.argv[2]).resolve())
    else:
        raise RuntimeError("Usage: rivest-migration {status|resume}")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Avoid dumping tracebacks, bundle contents, or secret-bearing argv.
        print(f"Migration stopped: {type(error).__name__}. No later phase was authorized.", file=sys.stderr)
        if isinstance(error, RuntimeError):
            print(str(error), file=sys.stderr)
        sys.exit(1)
