# Fedora post-install status — 2026-10-16

The corporate Framework is now **vpbworkstation**. Fedora 44 KDE/Wayland runs on
LUKS Btrfs with UID/GID 1000 and enforcing SELinux. Home has been restored.
The `rivest` Ansible inventory entry is a local provisioning alias. Personal
`zygalski` remains Arch, and its dotfile selection is unchanged.

## Completed

- Replaced the restored Arch-linked Codex daemon package: it required
  `libbz2.so.1.0`, while Fedora provides `libbz2.so.1`. The pinned native musl CLI
  package 0.162.1 works without a compatibility symlink or library change.
- Ran `codex app-server daemon update --from-cli --yes`, then started through
  the corporate wrapper. CLI and daemon both report 0.162.1. A fresh TUI opened
  without `--no-daemon`; disconnecting it left the daemon running. Remote control
  remains disabled. Authentication, history and the existing session are retained.
- Restored corporate Codex PATH priority and app-codex.slice. The daemon's cgroup
  is inside the slice: 3 GiB MemoryHigh, 4 GiB MemoryMax, 1 GiB MemorySwapMax.
  Both `rivest` and `vpbworkstation` select this configuration; Arch uses its
  native CLI path and personal `zygalski` remains excluded as before.
- Applied only reviewed UWSM files, Berg/weather/artwork units and Hyprland
  session guards. Enabled the session units and both timers. Weather and artwork
  jobs completed successfully in KDE; Plasma retains the notification bus.
- Recovered 81 artwork archive entries into the existing user-owned Fedora
  artwork directory. Imported no Arch system configuration.
- Copied Discord and Telegram native profiles into their Flatpak locations,
  verified rsync checksum parity, omitted stale Electron singleton locks and
  retained the original profiles. Existing Bitwarden data was preserved.
- All previously requested native package profiles and the three Flatpaks are
  installed. No full provisioning or OS upgrade was repeated.

## Validation and remaining acceptance

Eight wrapper tests, 13 clock tests, nine crash-watcher tests, ten Gmail tests,
53 artwork tests and fourteen migration tests pass (107 total). Four hostname/OS
selection cases and package-update polling invariants pass. User-unit verification
passes. The existing package-test lint output includes pre-existing QML warnings;
no Berg QML was changed in this phase.

KDE is still the active session. Manually log out when convenient and choose
**Hyprland (UWSM)**. No automatic logout or reboot is scheduled. In that session,
require a bounded `hyprctl -j monitors` probe, then run the Qt 6 Wayland QML suite
with `/usr/lib64/qt6/bin/qmltestrunner`. Check Berg IPC/UI, weather, wallpaper,
notification ownership, idle services, restart counts and `hyprctl configerrors`.
Physical Hyprland runtime success is not yet claimed. Authenticated application,
Bluetooth, dock and suspend workflows still need user acceptance.

The host retains a Bluetooth-wizard exit and DrKonqi pickup timeout from
2026-10-15, before this work; these are not hidden by resetting failed-unit state. They are separate
from the newly enabled desktop units and need their journal reviewed if ongoing.

## Operation and rollback

New desktop shells resolve `~/.local/bin/codex`; existing terminals may retain
an old PATH until a new login. The wrapper selects `/usr/local/bin/codex` on
Fedora and `/usr/bin/codex` on Arch. The managed daemon is pinned to the same
verified package as the Fedora playbook; changing this pin is a deliberate update.

If daemon repair regresses, `/usr/local/bin/codex --no-daemon` remains the direct
fallback. Do not delete `.codex`, account state or history. Revert only the focused
configuration commit when needed. KDE remains selectable at the login screen.
Disable the enabled Berg/Hyprland units and timers to undo session activation;
restore their prior user configuration before reloading the user manager.
Original application profiles and protected recovery capture remain in home.
Retain the USB backup until recovery is accepted; no backup was erased.
