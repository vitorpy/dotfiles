# Fedora migration lab on Scherbius

Created 2026-10-14 to test the Framework Laptop 12 migration from Arch to Fedora,
especially the existing Hyprland 0.56.2 Lua configuration and Berg on Quickshell
0.3.2. The laptop stays on Arch while the server runs the test guest.

Preparation status on 2026-10-14: the 558 MiB base image is downloaded on
Scherbius, its Fedora 44 signature and SHA256 are verified, and the CIDATA seed
is built. ShellCheck, Bash syntax, Python syntax, ISO label, and file permissions
passed inspection. The launch preflight reports the expected missing QEMU tools
and unavailable `/dev/kvm`; the VM has not booted and the desktop is untested.

The guest starts from Fedora Cloud Base 44 and updates on first boot. This is a
package/configuration test platform, not a rehearsal of Workstation's installer
or its complete default package selection. GNOME and Hyprland can be added in
the guest once package availability has been checked. Use the laptop's live USB
for hardware, touchscreen, suspend, and graphics checks. The server VM uses a
virtual GPU with software rendering.

## Layout and access

- Host: `vitorpy@scherbius.vitorpy.com`, Arch Linux.
- State: `~/.local/share/fedora-migration-lab/` on the server, mode 0700.
- Resources: 8 vCPUs, 16 GiB RAM, 80 GiB thin-provisioned qcow2 overlay.
- Immutable base image: Fedora Cloud 44-1.7, verified using its signed checksum,
  the published Fedora 44 OpenPGP fingerprint, and a pinned SHA256.
- Networking: QEMU user networking, SSH on host `127.0.0.1:22244`, VNC on
  host `127.0.0.1:5904`; no bridge, firewall edits, or public listeners.
- Credentials: a dedicated VM-only SSH key generated on the server; guest
  passwords are locked. Root key access is for provisioning this disposable
  guest. No personal private keys, password stores, or browser data are copied.
- QEMU runs as the existing user. There is no host libvirt service or autostart.

## One-time host prerequisites — user must run

The workstation's AGENTS.md forbids the assistant from executing `sudo`. These
commands install the minimal distro packages, load the existing KVM module, and
grant the existing account access through Arch's KVM group:

```sh
ssh -t vitorpy@scherbius.vitorpy.com
sudo pacman -S --needed qemu-system-x86 qemu-img qemu-hw-display-virtio-gpu qemu-hw-display-virtio-vga
sudo modprobe kvm_intel
sudo usermod -aG kvm vitorpy
exit
```

Open a fresh SSH connection afterward so the new group membership takes effect.
No reboot or server-wide package upgrade is part of this procedure. If pacman
reports missing package files or dependency conflicts, stop and review the host's
update needs; do not refresh its package database without a matching upgrade.

## Deploy and prepare from the laptop

```sh
ssh vitorpy@scherbius.vitorpy.com 'install -d -m 700 ~/.local/share/fedora-migration-lab'
scp ~/.config/fedora/migration-lab/{prepare.sh,start.sh,guest.sh,vmctl.py,README.md} \
  vitorpy@scherbius.vitorpy.com:.local/share/fedora-migration-lab/
ssh vitorpy@scherbius.vitorpy.com \
  'chmod 700 ~/.local/share/fedora-migration-lab/*.sh ~/.local/share/fedora-migration-lab/vmctl.py; ~/.local/share/fedora-migration-lab/prepare.sh'
```

The image, cloud-init files, logs, guest disk, and private key remain outside the
dotfiles repository. Preparation does not require QEMU or KVM and can run before
the host prerequisites are installed. It preserves an existing image and seed.

## Start and inspect

Run on Scherbius after the host prerequisites are available:

```sh
~/.local/share/fedora-migration-lab/start.sh --check
~/.local/share/fedora-migration-lab/start.sh
~/.local/share/fedora-migration-lab/vmctl.py status
tail -n 50 ~/.local/share/fedora-migration-lab/run/serial.log
~/.local/share/fedora-migration-lab/guest.sh root cloud-init status --long
~/.local/share/fedora-migration-lab/guest.sh vitorpy cat /etc/os-release
```

The first boot updates Fedora and installs basic inspection tools; wait for
cloud-init to finish before modifying guest packages. The prepared guest has
SSH access but no desktop yet. Root guest commands can be run through
`guest.sh root`; the assistant still does not execute `sudo`.

For the eventual graphical session, start this tunnel on the laptop:

```sh
ssh -N -L 5904:127.0.0.1:5904 vitorpy@scherbius.vitorpy.com
```

Connect a VNC viewer to `127.0.0.1:5904`. The server's existing SSH policy must
allow local TCP forwarding; do not change SSH policy automatically if it rejects
the tunnel. QMP screenshots remain available through `vmctl.py screenshot`.

## Rollback and cleanup

Request a graceful shutdown on Scherbius:

```sh
~/.local/share/fedora-migration-lab/vmctl.py shutdown
```

Confirm the QEMU process has exited before removing or replacing any image. To
reset only the guest, remove `fedora44-lab.qcow2` after shutdown; the next start
creates a new overlay and cloud-init runs again. The verified base stays intact.
To remove the whole lab after shutdown, remove its dedicated server directory.
Removing the overlay or directory permanently discards the lab's guest data.
No laptop data or host system configuration is part of the lab directory.

If the KVM group membership was added solely for this lab, the user can remove it
with `sudo gpasswd -d vitorpy kvm` and reconnect. Review other consumers before
uninstalling QEMU; there is no reason to unload KVM for cleanup.

Revert the dotfiles commit and apply the corresponding chezmoi paths to remove
these tracked helper files. Never place the generated VM private key or image in
chezmoi.

## References

- [Fedora Cloud downloads](https://fedoraproject.org/cloud/download/)
- [Fedora signing keys](https://fedoraproject.org/security/)
- [cloud-init NoCloud](https://docs.cloud-init.io/en/latest/reference/datasources/nocloud.html)
- [QEMU invocation](https://www.qemu.org/docs/master/system/invocation.html)
