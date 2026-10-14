# Migration rehearsal status — 2026-10-14

Corporate Rivest remains Arch with its partitions and boot configuration intact.
USB preparation is deferred. Personal Zygalski stays Arch.

## Backup and recovery

- Encrypted NAS repository: `sftp:mediaserver:/mnt/media/backups/rivest-restic`.
  Password read-back verified in Bitwarden **Rivest migration backup**. Secrets
  are outside Git and have not been copied to Scherbius.
- Refreshed snapshot `9775cc38ff1ca0f5749dc633c09dacdef3e55729158a142d36c98a789eb16e0b`:
  328,970 files, 12,473,377,872 bytes. Repository metadata check passed and nine
  changed files were restored with content, UID/GID, mode and xattr verification.
  This snapshot includes application-profile commit `895202d`. Its full data read
  was not repeated; the preceding full read result is recorded below. Temporary
  backup password and vault-session files have been removed.
- Latest previously verified snapshot:
  `7828297443a93c8614c7e856cf04c28066e0341bfcd7cdffee9808b13eb5b0a1`:
  328,856 files, 12,491,851,633 bytes. Full read verification passed 320/320 packs
  with no errors. Initial snapshot `d8929379d21133b73c8ae676615d0a868365ee32cfe025e7194a157bde1746b3`
  also passed its full 314-pack read check.
- Representative real-file restores matched content, UID/GID, mode, symlinks and
  user xattrs, including SSH, keyring, GnuPG, fonts and protected recovery files.
  Private restore staging is excluded from future backups. A sanitized fixture
  also passed Fedora restore/restorecon/SELinux checks.
- The user captured a private 150,138,880-byte, 1,877-entry root reference archive.
  It is a reference for recreating settings under Fedora, not an Arch system
  archive to extract over Fedora defaults.
- `recovery-check.sh` is pushed for the personal laptop. It restores and verifies
  only a public fixture using independent Bitwarden/NAS access. User verification
  is still pending; see ACCEPTANCE.md for the exact command.

## Package profiles and parity

- All 243 explicit Arch package rows remain in packages.tsv. Every row has an
  identified route, Fedora native replacement, Arch-only classification or
  user-approved omission. Required account/hardware workflows remain pending.
- Deezer is corporate-omitted and personal-only in Arch. ROCm SDKs are retired
  from both Arch workstation profiles. User-run local removal completed on
  Rivest; a privilege-disabled Ansible check confirms no SDKs remain to remove.
  Actual removal on the personal laptop is not claimed.
- Live and chezmoi-source corporate/personal profile tests pass. Existing newer
  source-only personal/boot changes were preserved; live Rivest has pre-existing
  differences from those files, so a blanket chezmoi re-add is inappropriate.
- The clean KDE guest installed the full native parity set, signed corporate and
  vendor RPMs, publisher-verified Bitwarden/Discord/Telegram Flatpaks, signed
  Signal AppImage, official Zotero archive and pinned development tools.
- Strict verification rejected incorrect GitHub API metadata URLs and Bitwarden's
  unsigned RPM. Correct release asset URLs match pinned hashes; Bitwarden uses
  its supported, publisher-verified Flatpak instead. No global signature bypass.
- The final expanded provision passed, followed by
  `ok=129 changed=0 failed=0 skipped=18`. The optional gesture service is installed
  but disabled. All 196 native package requests resolve to installed RPMs; Fedora
  provides nodejs/npm through nodejs22/nodejs22-npm.
- Codex 0.162.1 full package, Bitwarden CLI 2026.9.1, NVM 0.40.8, zvm 0.9.1,
  cargo-audit 0.22.2, cargo-hack 0.6.45 and Framework tool help passed. The pinned
  cargo-sort v2.1.4 artifact reports 2.1.3 internally; gesture commit 9552f0d
  reports 2.80. VSCE 4.0.0 packaged a disposable extension successfully with
  lifecycle scripts disabled. No personal toolchain credentials were installed.
- LunarG SDK published SHA256 matched; vkprofiles help and extra/profile layer
  files verified. Its environment remains explicit opt-in. Material Symbols font
  passed fc-match. Android USB rules match the current Arch rule's SHA256 and
  passed udevadm verify; no permanent USB/input group access was granted.
- VLC loads native extra plugins plus signed RPM Fusion x264/x265 add-ons and
  the decoder library. The scoped repository permits five reviewed package names.
  The transaction removed no RPMs. Actual media/subtitle workflows remain pending.

## Desktop rehearsal evidence

- Separate clean Fedora 44 KDE install: signed media, UEFI, LUKS Btrfs, UID 1000,
  SELinux Enforcing, native Plasma Login Manager and tuned-ppd retained.
- Accepted `4114933` disk/UEFI checkpoint preserved read-only as a backing file;
  expanded packages run on a new qcow2 overlay. Original Cloud guest is stopped.
- Prior shared Berg port verification remains valid: 148 QML tests passed on
  real Arch and Fedora Wayland; Python suite passed 32 tests plus 21 subtests;
  four isolated updater tests passed. Arch updater unchanged. No Berg code was
  changed by this package-parity phase.
- Normal LUKS unlock, Plasma login and packaged Hyprland UWSM login passed. Berg
  runs in Hyprland and yields Notifications to plasmashell in Plasma. Clock,
  weather, calendar, lock/unlock and a bounded idle inhibitor passed previously.
- KDE portal file chooser and actual one-frame PipeWire screen capture passed.
  The clean guest also passed Hyprland capture with a real PNG through the portal
  PipeWire FD, automatic session closure, unchanged compositor PID and no new core
  dump. The older Cloud capture failure is preserved; its cause is not claimed
  fixed by the clean-guest result.
  Cloud Hyprland file chooser and disposable Secret Service store/lookup/clear
  passed. No real account secrets were used.
- 1Password and Roam rendered welcome/sign-in in Hyprland; Slack rendered sign-in
  in KDE and clean-guest Hyprland after lab keyring setup. Forced systemctl stop
  produced a Slack SIGTRAP; Ctrl+Q quit succeeded. These are startup observations,
  not authenticated calls or screen-sharing acceptance.
- ChatGPT's signed RPM rendered sign-in through its default XWayland path. Signal
  rendered linking UI; Bitwarden's verified Flatpak rendered login UI. Zoom's
  sign-in UI rendered after removing the VM-only QT_QUICK_BACKEND override for
  that launch. A ZoomWebviewHost SIGABRT occurred before quitting the first
  software-Qt launch; no further Zoom core dump was recorded during the normal-Qt
  rerun. Zotero rendered its
  empty library; verified Telegram/Discord rendered welcome/login. No account
  sign-in was attempted.

## Remaining gates

- Hyprpaper reproducibly SIGSEGVs with tiny PNG/JPEG/WebP images in the clean
  software-graphics guest after GBM/dumb-buffer allocation failure. The preserved
  Cloud compositor crashed during portal capture in Aquamarine's DRM path; clean
  guest Hyprland capture subsequently passed.
  GRAPHICS.md contains a minimal reproduction and source-level inference. No
  upstream fix or physical Intel-GPU success is claimed.
- Flatpak launches also activated a failed IBus portal unit; login windows
  rendered, but input-method integration has not been accepted.
- Independent-device recovery confirmation, authenticated corporate workflows,
  security keys and Framework hardware checks remain pending in ACCEPTANCE.md.
- Prepare the USB only when requested and after identifying its model/serial.
  Refresh root capture and inventory, quiesce apps, take and verify the final
  pre-install backup, and record its full snapshot ID before physical cutover.
