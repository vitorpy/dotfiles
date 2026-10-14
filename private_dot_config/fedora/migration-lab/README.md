# Fedora migration lab on Scherbius

Created 2026-10-14 to test the Framework Laptop 12 migration from Arch to Fedora,
especially the existing Hyprland 0.56.2 Lua configuration and Berg on Quickshell
0.3.2. The laptop stays on Arch while the server runs the test guest.

Status on 2026-10-14: the 558 MiB base image is downloaded on Scherbius, its
Fedora 44 signature and SHA256 are verified, and the CIDATA seed is built.
ShellCheck, Bash syntax, Python syntax, ISO label, file permissions, QEMU launch
preflight, and guest disk checks passed. Fedora has booted with KVM acceleration,
cloud-init finished without errors, guest SSH works, and the guest has no failed
system units. Both forwarded ports listen only on `127.0.0.1`. Hyprland 0.56.2
and Quickshell 0.3.2 are installed and running under UWSM on kernel
`7.2.10-200.fc44.x86_64`. Berg's bar and clock/calendar panel were visually
checked; the panel was closed afterward. The full Fedora port is not complete:
the package updater still invokes Arch tools, and machine-local state is absent.

The guest starts from Fedora Cloud Base 44 and updates on first boot. This is a
package/configuration test platform, not a rehearsal of Workstation's installer
or its complete default package selection. Hyprland has been added; GNOME has
not been installed. Use the laptop's live USB
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

## One-time host prerequisites

The user explicitly authorized the assistant to use `sudo` on Scherbius on
2026-10-14; the prohibition still applies to the local workstation. These
commands were run on Scherbius to install the minimal distro packages, load the
existing KVM module, and grant the existing account access through Arch's KVM
group:

```sh
ssh -t vitorpy@scherbius.vitorpy.com
sudo pacman -S --needed qemu-system-x86 qemu-img qemu-hw-display-virtio-gpu qemu-hw-display-virtio-vga
sudo modprobe kvm_intel
sudo usermod -aG kvm vitorpy
exit
```

Open a fresh SSH connection afterward so the new group membership takes effect.
The installed QEMU packages are version `11.0.2-4`. No reboot or server-wide
package upgrade was needed. The guest was restarted to load its updated Fedora
kernel. After a future server reboot, reload `kvm_intel` if `/dev/kvm` is absent.
If pacman reports missing package files or dependency conflicts, review the host's
update needs; do not refresh its package database without a matching upgrade.

## Deploy and prepare from the laptop

```sh
ssh vitorpy@scherbius.vitorpy.com 'install -d -m 700 ~/.local/share/fedora-migration-lab'
scp ~/.config/fedora/migration-lab/{prepare.sh,start.sh,guest.sh,provision-desktop.sh,configure-session.sh,vmctl.py,README.md} \
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
cloud-init to finish before modifying guest packages. `prepare.sh` supplies SSH
access; the later provisioning steps add the desktop. Root guest commands use
`guest.sh root`. Host `sudo` authorization is limited to Scherbius.

To view the running graphical session, a VNC viewer can use this laptop tunnel
if Scherbius's SSH forwarding policy allows it:

```sh
ssh -N -L 5904:127.0.0.1:5904 vitorpy@scherbius.vitorpy.com
```

Connect a VNC viewer to `127.0.0.1:5904`. The server's existing SSH policy must
allow local TCP forwarding; do not change SSH policy automatically if it rejects
the tunnel. QMP screenshots remain available through `vmctl.py screenshot`.

## Desktop package investigation

Public Fedora 44 COPR metadata checked on 2026-10-14 lists Hyprland 0.56.2 in
both `sdegler/hyprland` and `lionheartp/Hyprland`. The latter also lists
Quickshell 0.3.2 and UWSM 0.27.0, so it can supply the workstation's current
compositor and shell versions. Fedora's own repositories list the older
Quickshell 0.2.1 Git snapshot and no Hyprland. The following versions were
successfully installed from the scoped `lionheartp/Hyprland` repository:

| Component | Installed RPM version |
| --- | --- |
| Hyprland | `0.56.2-3.fc44` |
| Quickshell | `0.3.2-1.git.20261008.4f508be.fc44` |
| UWSM | `0.27.0-1.fc44` |

`provision-desktop.sh` is guarded to run only as root inside Fedora 44 with
hostname `fedora44-lab`, after cloud-init has finished. It limits COPR packages
to the Hyprland family, Quickshell, UWSM, and the matching desktop portal, with
RPM signature verification enabled. Run from the laptop:

```sh
ssh vitorpy@scherbius.vitorpy.com \
  '~/.local/share/fedora-migration-lab/guest.sh root bash -s -- --preview' \
  < ~/.config/fedora/migration-lab/provision-desktop.sh
```

Review the preview, then repeat with `--install` to install only in the guest.
DNF returns a nonzero exit status when an `--assumeno` preview is declined.
The script installs the compositor, shell, supporting services, software graphics,
fonts, and Qt/Python test tools. It does not configure a graphical login.

## Configure the test session

Copy the selected desktop files and the two existing fonts from the laptop.
This copies no application credentials, private SSH keys, browser profiles, or
personal documents:

```sh
tar -C /home/vitorpy --exclude='__pycache__' --exclude='*.pyc' -cf - \
  .config/quickshell/berg .config/hypr/hyprland.lua \
  .config/systemd/user/quickshell-berg.service \
  .local/share/fonts/AvenirNextMForBBG/AvenirNextMForBBG-Regular.ttf \
  .local/share/fonts/SF/SFSymbolsFallback.otf \
  | ssh vitorpy@scherbius.vitorpy.com \
      '~/.local/share/fedora-migration-lab/guest.sh root tar -xf - -C /home/vitorpy'

ssh vitorpy@scherbius.vitorpy.com \
  '~/.local/share/fedora-migration-lab/guest.sh root bash -s' \
  < ~/.config/fedora/migration-lab/configure-session.sh
```

The guarded session script preserves `hyprland.workstation.lua`, omits personal
application autostarts only in the VM copy, sets a 1280x800 display, disables
blur/animations for software rendering, and finalizes the UWSM session. The
runtime Lua timers remain unchanged. It creates a Berg desktop app entry for
Fedora's portal registration and enables the existing Berg user service.

The guest uses greetd console autologin as `vitorpy`, with a normal PAM/seat
session. This autologin is confined to the disposable VM behind localhost-only
VNC. Fedora's SELinux stays **Enforcing**. The script configures and enables
greetd; run syntax/model checks before starting it:

```sh
# On Scherbius, after the checks described below:
~/.local/share/fedora-migration-lab/guest.sh root systemctl start greetd.service
```

Session launcher output is in the guest at
`~vitorpy/.local/state/fedora-migration-lab/session.log`. If an initial session
exits, greetd shows its normal login prompt and does not automatically repeat
autologin until the next guest boot.

## Verified results and remaining work

- ShellCheck, Bash/Python syntax, base-image signature/SHA256, seed ISO, and
  source/server helper parity passed.
- All Berg QML files passed Fedora's Qt 6 `qmllint` (exit 0; nonfatal lint
  warnings remain). **32 Python model tests passed**, run from `/home/vitorpy`.
- **146 QML model tests passed** both offscreen and on the actual Qt 6 Wayland
  session with the inherited X11/theme overrides removed.
- The original and VM Lua configs passed parsing/API verification after
  isolating the CLI timer-cleanup bug described below. The original also passed
  `luac -p` on the workstation. The real compositor reports no config errors.
- Berg loaded and rendered its bar and clock/calendar panel. Its service is
  `active/running` with `NRestarts=0`. Safe shell/action status IPC calls passed;
  `openClockPanel Virtual-1` and `closeClockPanel` worked with standard
  `qs -c berg ipc call ...` on this COPR Quickshell 0.3.2 build.
- The guest has no failed system units and SELinux is Enforcing. No logout,
  reboot, or poweroff action in Berg was exercised.

The unchanged update widget cannot find `/usr/bin/checkupdates` or `/usr/bin/yay`
and remains in `loading`; its Fedora backend and updater command still need
porting. No fake compatibility commands were installed. Weather is `stale`
because the weather cache/service has not been provisioned, artwork metadata is
absent, and Gmail is correctly `disabled` without copied credentials. These
expected gaps mean the full runtime is **not** warning-free or migration-ready.

The VM exercises a virtual display and dummy audio output. It does not validate
the laptop's battery, backlight, microphones, graphics acceleration, or suspend.

Hyprland's `--verify-config` crashes during timer cleanup even with this minimal
Lua file:

```lua
local timer = hl.timer(function() end, { timeout = 1000, type = "oneshot" })
```

An empty config exits successfully; the timer reproducer exits 139 with a stack
through `CEventLoopManager::removeTimer` and `CConfigManager::cleanTimers`.
For static verification only, temporary copies prefixed the original source with
`hl.timer = function(...) return { set_enabled = function(...) end } end`.
Both then reported `config ok`. This stub is not in the runtime configs.
Guest verification logs are `/var/tmp/fedora-lab-*.log`; the server's desktop
installation log is `~/.local/share/fedora-migration-lab/run/provision-desktop.log`.

Known portability work still includes Berg's pacman/Yay update backend and
Arch updater command, Qt tool paths (`/usr/lib64/qt6/bin` on Fedora), and the
existing Arch Ansible roles. Berg's fonts are user-installed Avenir and SF Symbols
fonts; preserve those in the actual NAS backup. Do not put font binaries or
credentials in this helper directory or the dotfiles repository.

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
- [Selected Hyprland COPR](https://copr.fedorainfracloud.org/coprs/lionheartp/Hyprland/)
