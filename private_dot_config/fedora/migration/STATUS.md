# Migration rehearsal status — 2026-10-14

Laptop partitions and boot configuration are unchanged. USB creation is deferred
at the user's request. Personal `zygalski` stays Arch.

## Backup and recovery — passed

- Restic 0.19.1 installed in the laptop's user bin after upstream OpenPGP and
  SHA256 verification. No local sudo was run by the assistant.
- NAS repository: `sftp:mediaserver:/mnt/media/backups/rivest-restic`, private
  directories owned by vitorpy. Approximately 360 GiB free before backup.
- Password created and read-back verified in Bitwarden item **Rivest migration
  backup**. Temporary vault session deleted. No password is stored in Git.
- Initial snapshot `d8929379d21133b73c8ae676615d0a868365ee32cfe025e7194a157bde1746b3`:
  328,714 files, 12,450,641,124 bytes, no diagnostics. Full read-data check passed
  all 314 packs with no errors.
- Nine representative real paths restored locally and matched content, UID/GID,
  modes, symlink and user xattr, including SSH, keyring, GnuPG, font and protected
  recovery files. Restore staging is private and excluded from future backups.
- User captured protected files into a private 150,138,880-byte archive with
  1,877 entries. Inventory and archive remain outside Git.
- A separate public fixture restored inside Fedora with UID/GID/mode/symlink/xattr
  verification, then `restorecon` and SELinux context verification. No personal
  data or NAS password was copied to Scherbius.

## Shared configuration — passed

- Berg selects Arch or Fedora using `/etc/os-release`; update IPC preserves its
  existing fields and adds `backend`. Both report ready. Fedora counts unique
  RPM name/architecture pairs, skips AUR and invokes its own RPM-only updater.
- DNF's unprivileged first-use metadata key confirmation is handled with
  `--assumeyes`; package installation still has interactive confirmation.
- Missing executable, stale results, timeout and accepted nonzero status passed
  real Quickshell tests. 148 QML tests passed on real Arch and Fedora Wayland;
  Python suite passed 32 tests plus 21 subtests. Four isolated updater tests pass.
- Arch personal/corporate profile checks pass. Original Arch updater unchanged.
- Themes, portals and compositor services are scoped to Hyprland. In Plasma,
  Berg's ExecCondition skips it and plasmashell owns Notifications.

## Scherbius VMs — installation and desktop checks

- Original Cloud baseline preserved separately. Signed image verified; Hyprland
  and Berg previously rendered correctly with updates and weather ready.
- Separate clean KDE VM: verified Fedora 44 KDE live and Everything netinstaller
  signatures/SHA256, UEFI, LUKS Btrfs, UID 1000, SELinux Enforcing. Installed from
  the supported netinstaller; KDE live installer rejects Kickstart.
- LUKS unlock tested twice, normal KDE login and native Plasma Login Manager
  retained. Release packages upgraded normally before adding current components.
- Provisioning preserves KDE's native tuned-ppd. Repeated corporate provision
  reports `ok=37 changed=0 failed=0 skipped=5`.
- Packaged Hyprland (uwsm-managed) session starts through the native greeter.
  Berg active/running, NRestarts=0; no compositor config errors. Clock/weather
  ready, calendar open/close works, wallpaper fetch succeeds.
- KDE portal file dialog and screen sharing passed, including actual PNG frame
  capture through the portal's PipeWire FD. Hyprland file dialog passed on Cloud.
- Native KDE lock/unlock and Hyprlock password authentication passed. A user-owned
  sleep/idle inhibitor appeared in logind and expired after the bounded test.
- Cloud Secret Service store/lookup/clear passed with a disposable fixture.
- Vendor RPMs: 1Password and Roam rendered their welcome/sign-in UI on Hyprland;
  Slack rendered sign-in on KDE. No real account authentication was attempted.
- Pinned Foundry, GAM, Jira, Starship and Noirup install and CLI checks passed.
  These archives need deliberate Ansible version bumps, outside the RPM badge.

## Blockers and acceptance gates

- Hyprland screen sharing crashed the software-rendered Cloud VM compositor
  (Aquamarine DRM output commit / EGL_BAD_PARAMETER). KDE capture passed.
  This does not establish behavior on the Framework GPU; capture must pass there
  before accepting Hyprland for work. Crash report remains in the Cloud guest.
- In the clean VM, hyprpaper segfaulted while loading fetched artwork. Hyprlock
  logged a DRM dumb-buffer permission warning but rendered and unlocked. These
  software-graphics issues remain unresolved; do not call the runtime error-free.
- Slack's default launch crashed in the Cloud Hyprland guest, while KDE launch
  passed. Required Slack/Roam calls, screen sharing, browser sign-in, password
  manager integration and hardware security keys remain untested workflows.
- `packages.tsv` accounts for all 243 explicit Arch packages. Unresolved package
  sources and required workflows marked BLOCKER need resolution or explicit
  omission before physical migration.
- Recovery access to Bitwarden and NAS from another device needs user verification.
- USB creation and Framework hardware checks are deferred, not passed.
- Refresh root capture, close stateful apps, take a final quiesced backup, and
  record its snapshot ID before installation. No physical cutover is authorized
  by this rehearsal's test results.
