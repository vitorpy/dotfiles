# Migration acceptance checklist

This checklist is for corporate Rivest. Personal Zygalski stays Arch. Rehearsal
results are recorded in STATUS.md; an installed package alone does not establish
an authenticated workflow. USB preparation remains deferred.

## Independent recovery

Run from the personal laptop after updating only the dotfiles Git checkout:

```sh
git -C "$(chezmoi source-path)" pull --ff-only
bash "$(chezmoi source-path)/private_dot_config/fedora/migration/executable_recovery-check.sh"
```

Install restic there using Arch's package manager if the helper requests it.
Open Bitwarden independently and use **Rivest migration backup**. The helper
restores only the known public fixture, verifies its SHA256, and deletes its
private staging directory and password file. It does not apply workstation
configuration. Record its successful snapshot ID before scheduling installation.
Keep NAS SSH access and the repository password usable without Rivest's unlocked
1Password agent. Do not put a real vault or repository password on Scherbius.

## Account workflows — user verification pending

Perform these on the physical Fedora system before accepting it for work. Use
Plasma as a comparison session where a Hyprland workflow fails.

- Unlock 1Password and Bitwarden; verify browser integration, SSH agent signing,
  recovery access and hardware security keys. Keep the old keyring and its login
  password until restored secrets are accessible.
- Sign in to the corporate browser, Slack and Roam. Test a real call with camera,
  microphone, speaker/headset and screen sharing; verify the received picture
  from the other endpoint. Check sharing permissions after stopping the call.
- Open ChatGPT and Codium; check required extensions and authentication. Exercise
  Codex, cloud/Kubernetes, Jira, GAM and development toolchain authentication with
  their usual repositories. Use the backed-up home state only on the workstation.
- Link Signal, Telegram and Discord as required; open Zotero and verify its
  database and attachment paths with the application closed during restoration.
- Mount a disposable VeraCrypt container, copy a test file and unmount it. Check
  NAS/rclone mounts and required corporate VPN/Tailscale connectivity.
- Open representative documents, PDFs, images and media with subtitles; check
  VLC codecs with actual files. Deezer is intentionally omitted on corporate
  Fedora. ROCm development kits are retired on both workstation profiles.

## Physical hardware and desktop — pending

Use the signed KDE live USB first, then repeat relevant checks after installation:
Wi-Fi, Bluetooth, camera, audio/microphone, touch, sensors, brightness, external
monitor/dock, USB devices and Android access. Check suspend/resume on battery and
AC, lid close/open, fingerprint enrollment, Secure Boot/LUKS recovery and storage.
Check the Framework firmware guidance before changing firmware settings.

Hyprland/Berg must pass login, artwork, locking/unlocking, notifications, portals,
screen capture, updates and normal work on the Intel GPU. Record any failure and
the selected desktop. The server's software-graphics VM cannot certify these
hardware workflows; its unresolved graphics reproductions are in GRAPHICS.md.

## Final backup and restoration

Close stateful applications, save work, refresh the private root reference and
inventory, then take and verify a final incremental backup. Record the full
snapshot ID and dotfiles commit outside Rivest. Keep the validated older snapshots.
Restore into private staging with matching UID 1000; provision Fedora and restore
application state with applications closed. Run Fedora restorecon on restored
paths. Use Arch system archives as references when recreating settings.

Rollback remains an Arch reinstall plus the verified file backup. Keep the Arch
installer route, package inventory and NAS/Bitwarden recovery access available.
