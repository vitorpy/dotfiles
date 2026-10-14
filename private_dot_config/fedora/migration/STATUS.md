# Migration rehearsal status — 2026-10-14

This is a rehearsal. Laptop partitions and boot configuration are unchanged.
USB creation is deferred at the user's request.

## Verified

- NAS `mediaserver` (192.168.1.94) SSH and SFTP access; approximately 360 GiB free.
  Private backup directory `/mnt/media/backups/rivest-restic` created.
- Restic 0.19.1 installed in the laptop's user bin; upstream OpenPGP signature
  and SHA256 verified. No local sudo was run by the assistant.
- User captured protected files into a private 150,138,880-byte archive. Archive
  readable, 1,877 entries. Recovery inventory and archive remain outside Git.
- Shared Berg backend selects Arch or Fedora using `/etc/os-release` and exposes
  its backend through update IPC. Arch and Fedora update status both ready.
- Missing executable, stale result preservation, timeout and accepted nonzero
  status passed real Quickshell runtime tests on Arch and Fedora.
- 148 QML tests passed on Arch and Fedora Wayland; Python suite passed 32 tests
  and 21 subtests. Four isolated Fedora updater integration tests passed.
- Arch personal/corporate workstation profile checks passed. Arch provisioning
  and the original updater are unchanged. Personal laptop was not accessed.
- Fedora provisioning completed with signed, scoped repositories. Its final
  repeated Cloud-VM run reported `changed=0`, `failed=0` (13 tasks).
- Cloud VM has Hyprland/Berg active with no service restart. Weather is ready.
  Ghostty, 1Password/CLI, Roam, Chrome, VSCodium, AWS CLI, Terraform and Tailscale
  installed; application launch and authenticated workflows are separate checks.
- KDE live and Everything netinstaller ISO signatures/SHA256 verified. Separate
  UEFI/KDE installation completed using LUKS Btrfs. LUKS unlock and SSH fingerprint verified; SELinux Enforcing on installed boot.

## Remaining acceptance gates

- Password stored and read-back verified in Bitwarden item "Rivest migration backup";
  the temporary vault session file was deleted.
- Initial encrypted snapshot `d8929379d21133b73c8ae676615d0a868365ee32cfe025e7194a157bde1746b3`
  completed successfully: 328,714 files, 12,450,641,124 bytes; no diagnostics.
  Full read-data check is running; representative local restore remains to verify.
  Independent-device recovery access must be confirmed by the user.
- Installed KDE login, Plasma/Hyprland session isolation, portals, screen sharing,
  secret service, lock/inhibitors and sanitized restore with SELinux relabeling.
- Application matrix `packages.tsv` has all 243 explicit Arch packages; unresolved
  or untested required workflows block physical migration.
- USB and physical Framework hardware checks are deferred, not passed.
- Final quiesced backup and installation are outside this rehearsal's cutover.
