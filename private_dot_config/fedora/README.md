# Fedora workstation migration

Corporate Framework Laptop 12 `vpbworkstation` (formerly `rivest`) now runs
Fedora 44 KDE, LUKS Btrfs and restored user `vitorpy` (UID/GID 1000). Hyprland/Berg
is configured alongside KDE. Personal `zygalski` remains Arch. This directory
contains separate Fedora provisioning; do not run the Arch playbook on Fedora.
See [current post-install status](migration/POST-INSTALL.md) before repeating setup.
The inventory name `rivest` remains a local provisioning alias; no hostname change
is required. All native package profiles already resolve on the installed host.

## Provisioning

After a normal Fedora KDE installation, finish the initial user setup, run a full
`sudo dnf5 upgrade --refresh`, and reboot into the updated system. The release ISO
contains an older KDE package set; adding current components before this update
can cause package-file conflicts. Install `ansible` (including its community.general collection) using Fedora's package
manager, then run the Fedora playbook yourself with elevation:

```sh
cd ~/.config/fedora/ansible
ansible-playbook site.yml --limit rivest --ask-become-pass -e fedora_corporate=true
```

The playbook checks Fedora 44 and UID 1000, scopes additional RPM repositories,
installs the desktop and core corporate applications, preserves the native power
profile provider (`tuned-ppd` on KDE), and creates artwork storage.
It leaves Fedora's boot, display manager, PAM, firewall, and SELinux defaults in
place. No package pruning or automatic OS upgrade is performed. Repeating the
playbook must produce no changes once the requested packages and services exist.
Scherbius VM instructions are in `migration-lab/README.md`.

Apply selected desktop dotfiles through chezmoi. Do not apply every template in
a credential-free VM: existing rclone templates need a real Bitwarden vault.
Keep the Arch provisioning and updater available in the shared repository;
Berg selects its backend using `/etc/os-release`.

Berg's update IPC keeps `officialCount`, `aurCount`, `total`, `health`, `running`,
and `refreshPending` and adds `backend`. Fedora uses `officialCount` for unique
RPM name/architecture pairs across enabled repositories and `aurCount=0`.
The Fedora updater asks before invoking sudo and updates RPMs only. Use KDE
Discover/Flatpak and fwupd separately. Arch's combined Yay/firmware workflow is
unchanged. Pinned upstream CLI archives and vendor applications listed in
`ansible/packages.yml` and `ansible/applications.yml`
are versioned in the Fedora playbook and need deliberate version bumps; they are
not counted by the RPM badge. Hyprland services check the active desktop before taking notification
or compositor roles in Plasma. Portal/theme settings are scoped to Hyprland.

## Application parity and updates

`migration/packages.tsv` retains all 243 explicit Arch packages and records the
Fedora route and remaining acceptance checks. Deezer is omitted on corporate
Fedora and remains personal-only in Arch. ROCm SDKs are retired on all Arch
workstation profiles; they are not declared for Fedora. Native compiler/build
tools replace Arch's base-devel without installing an Arch package manager.

The full profile is the default. `-e fedora_full_parity=false` selects only the
smaller desktop/corporate baseline and skips the added parity archives and apps.
The verified-only per-user Flathub remote refuses an unexpected URL or subset.
Bitwarden's unsigned vendor RPM was rejected; its publisher-verified Flatpak is
used instead. VeraCrypt and Zoom retain RPM signature enforcement. Signal is the
vendor's signed AppImage, seeded once in the user's home for vendor updates.

| Software route | Update method |
| --- | --- |
| Fedora/COPR/vendor repository RPMs, including ChatGPT | DNF / Berg's Fedora RPM updater |
| Bitwarden, Discord, Telegram | `flatpak update --user` or KDE Discover; verified-only remote |
| Signal AppImage; user-owned Zotero bootstrap | Vendor application updater; keep data backed up |
| Pinned CLI archives, Framework tool, VeraCrypt, Zoom, NVM, VSCE, fonts, Vulkan SDK and Android rules | Review upstream version/hash/signature changes in the Fedora playbook, rehearse, then reapply |

The LunarG SDK supplements Fedora's native Vulkan packages. Enable it explicitly
in a development shell, without changing the default graphics environment:

```sh
source /opt/fedora-workstation/vulkan-sdk-1.4.363.0/1.4.363.0/setup-env.sh
vkprofiles --help
```

The gesture daemon has a user service available but disabled. Restore its user
configuration, review raw input permissions and test the physical touchpad before
opting in with `systemctl --user daemon-reload` and
`systemctl --user enable --now libinput-gestures.service`. Disable it with
`systemctl --user disable --now libinput-gestures.service`. The upstream setup
helper assumes distro-owned paths and is not exposed by this custom install.
Android USB rules use active-session uaccess; the user is not added to adbusers.

Application removal is separate from changing declarations: disable the gesture
service if enabled, remove selected Flatpaks with `flatpak uninstall --user APPID`,
or review `dnf5 remove PACKAGE` before confirming. Pinned tools live in versioned
`/opt/fedora-workstation` directories with `/usr/local/bin` links. Preserve an old
version until its replacement is accepted. Never remove application data as part
of package rollback. [Acceptance checks](migration/ACCEPTANCE.md) and the
[graphics reproductions](migration/GRAPHICS.md) cover remaining migration gates.

## Recovery data

NAS repository: `sftp:mediaserver:/mnt/media/backups/rivest-restic`. Its parent
is private to `vitorpy`; restic encrypts all repository contents. Repository
credentials belong in **Bitwarden**, never this repository or the NAS filesystem.
No retention/pruning command is configured during migration.

The local recovery inventory is `~/.local/state/fedora-migration/`. The protected
archive captures `/etc`, `/boot`, `/root`, NetworkManager, Bluetooth, fingerprint,
and artwork state. Recreate it yourself before the final backup:

```sh
umask 077
sudo ~/.config/fedora/migration/capture-root.sh > ~/.local/state/fedora-migration/root-reference.tar
```

This archive is private but unencrypted on the original laptop; restic encrypts
it on the NAS. It is a reference for Fedora migration, not a set of Arch system
files to extract over Fedora. Reinstall packages under `/opt`; preserve personal
configuration from home. Rootless container data under home is included. Rootful
container storage was empty at initial inspection. Re-audit any new storage or
mounts before cutover.

Use `migration/restic.sh` for init, backup, full data check, and snapshots after
supplying the password securely. Backups include home, hidden application state,
fonts, source trees, uncommitted files, and the protected archive. The exclusions
contain only disposable caches/runtime logs. Application data should be quiesced
for the final backup. A backup with unreadable files or unexplained errors is not
migration-ready.

## Current cutover: normal install and USB home recovery

Normal Fedora installation and home recovery are complete. The custom guided
installer is abandoned. The unencrypted USB recovery procedure remains in
[the install/restore reference](migration/SIMPLE-INSTALL.md); do not repeat the
installation or erase the backup as part of desktop setup. No new backup or
bootstrap password is needed.

Keep native KDE for the initial recovery. Arch session activation is excluded
from the initial extraction but remains in the archive. Apply Fedora provisioning
and Hyprland/Berg after data recovery. Personal Zygalski stays Arch.
Do not extract the protected Arch system reference over Fedora's `/etc` or `/boot`.
Preserve the USB until the recovered data is accepted.

## Sources

- [Framework Laptop 12 Fedora KDE 44 guide](https://guides.frame.work/Guide/Fedora+KDE+Plasma+Desktop+44+on+a+Framework+Laptop+12+(13th+Gen+Intel%C2%AE+Core%E2%84%A2)/857)
- [Fedora KDE download](https://fedoraproject.org/kde/download/)
- [Restic SFTP/encryption](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html)
- [Ghostty packages and community COPR](https://ghostty.org/docs/install/binary)
- [1Password RPM installation](https://support.1password.com/install-linux/)
- [Roam RPM installation](https://ro.am/download/linux)
- [VSCodium RPM repository](https://repo.vscodium.dev/)
- [Slack RPM installation](https://slack.com/intl/en-gb/help/articles/212924728-Download-Slack-for-Linux--beta-.)

Additional parity sources reviewed on 2026-10-14:

- [Bitwarden Linux biometric support and recommended channels](https://bitwarden.com/help/biometrics/)
- [Flathub verified-only remotes](https://docs.flathub.org/docs/for-users/verification)
- [Official Signal Linux AppImage and signing key](https://signal.org/download/linux/)
- [VeraCrypt Fedora builds and signatures](https://veracrypt.io/en/Downloads.html)
- [Zoom Linux signing-key rotation](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0063726)
- [ChatGPT Linux and Fedora installation](https://learn.chatgpt.com/docs/linux/linux-app)
- [Codex CLI](https://learn.chatgpt.com/docs/codex/cli)
- [VideoLAN Fedora installation and RPM Fusion](https://docs.videolan.me/vlc-user/desktop/3.0/en/gettingstarted/setup/linux/fedora.html)
- [LunarG Linux SDK environment](https://vulkan.lunarg.com/doc/view/latest/linux/getting_started.html)
- [Upstream Android USB rules](https://github.com/M0Rf30/android-udev-rules)
