# Arch Linux Installation Guide

This guide reflects the current setup model:

- install a working Arch base system using your preferred installer
- apply dotfiles with `chezmoi`
- configure system-wide state with the Ansible playbook in `~/.config/arch/ansible`

There is no static machine-install JSON checked into this repo. The Framework
12 media builder generates a reviewed partial Archinstall configuration at
build time while leaving destructive and credential-bearing choices to the TUI.

## Recommended Install Target

The post-install playbook assumes:

- Arch Linux
- a normal user account already exists
- `sudo` works for that user
- networking works after first boot

The playbook will then handle:

- hostname, timezone, locale, and `/etc/hosts`
- package installation from `pacman` and AUR
- core services like `NetworkManager` and `sshd`
- desktop/session setup such as keyboard defaults and SDDM
- optional bootloader and Secure Boot state if you enable that role explicitly

## Base Install

Use either:

1. `archinstall`
2. the manual Arch install process

The repo no longer dictates disk layout through a checked-in installer profile, so pick the install method that matches the machine.

### Framework 12 Guided ISO

The Framework Laptop 12 has a separate guided ArchISO profile under:

```bash
~/.config/arch/archiso/framework12
```

It is intentionally separate from the destructive mediaserver profile. The
default boot entry starts Archinstall with reviewed workstation defaults, but
disk selection, partitioning, encryption, credentials, and the final install
confirmation remain interactive. A normal Arch rescue entry remains in the
boot menu.

The live image and installed-system package request contain:

- the stock ArchISO releng packages
- every official-repository package declared by the workstation Ansible profile
- the Framework 12 Intel graphics, Wi-Fi, touchscreen/sensor, audio, Bluetooth,
  webcam, fingerprint, and firmware support packages
- no AUR packages

The build refuses kernels older than 7.1 and `libfprint` older than 1.94.100 so
the image covers both the 13th Gen Intel and Core Series 3 Framework 12 models.
It also requires Archinstall 4.4 and arch-install-scripts 31 or newer for the
read-only post-install payload handoff used by the target chroot.

Validate the profile without reading credentials or building an image:

```bash
~/.config/arch/archiso/framework12/tests/test-profile.sh
```

Build it from a clean chezmoi source checkout:

```bash
sudo ~/.config/arch/archiso/framework12/build.sh \
  --dotfiles-source "$(chezmoi source-path)"
```

The user must run that `sudo` command; the assistant must not execute it. The
build needs root because `mkarchiso` constructs the live root filesystem. Its
large temporary work tree defaults to `/var/tmp/archiso-framework12`, not the
smaller `/tmp` tmpfs, and each individual build directory is removed on exit.

Outputs are written below `~/.config/arch/archiso/framework12/out/`:

- `rivest-framework12-*.iso`
- the matching `.sha256`
- a non-secret `.build-manifest.json`

The output directory is mode `0700`; the ISO and checksum are mode `0600` and
owned by the invoking user after a successful sudo build.

#### Embedded Wi-Fi and config snapshot

At build time, the script reads the saved NetworkManager profiles by UUID and
regenerates minimal WPA-PSK profiles for the canonical SSIDs `DomGromek` and
`DomGromek_5GHz`. Nothing secret is written into Git or the external build
manifest. The generated ISO does contain recoverable Wi-Fi credentials, so
treat it as private media and rotate the PSK if it is lost.

The build also embeds a zstd tar archive of the clean chezmoi `HEAD`, recording
its commit and SHA-256. After Archinstall has created the sudo-enabled
`vitorpy` account, the post-install hook:

1. installs both NetworkManager profiles into the target with mode `0600`
2. preserves the snapshot metadata under `/var/lib/vitorpy-bootstrap`
3. applies and verifies the snapshot for `/home/vitorpy`

Archinstall runs that hook inside its target chroot. The launcher stages the
payload below `/run/udev/framework12-bootstrap`, the read-only live path that
arch-install-scripts 31 exposes to an `arch-chroot -S` target.

It deliberately does not run the system Ansible playbook or restore Bitwarden
keys. The normal `bootstrap-user.sh` remains available after the first boot.

#### Installing on the Framework 12

1. Disable Secure Boot in firmware. The custom Arch ISO is not signed.
2. Write the ISO only after identifying the USB device with `lsblk`. Never use
   an unresolved glob or an assumed `/dev/sdX` target.
3. Boot the `Rivest Framework 12 guided installer` entry.
4. Confirm that NetworkManager connected to either saved home SSID.
5. In Archinstall, choose the target disk, layout, filesystem, and encryption.
6. Create the sudo-enabled user exactly as `vitorpy` and set its password.
7. Review the final Archinstall summary before approving disk changes.
8. Reboot into host `rivest` and verify networking, the UKI boot, SDDM, and the
   applied user configuration.

Only re-enable Secure Boot after generating or restoring the intended signing
keys, enrolling them in firmware, signing the installed UKIs, and proving a
successful signed boot. Running the Ansible boot role also requires replacing
the existing machine-specific ESP and root identifiers with Rivest's values.

For rollback before installation, select the normal Arch rescue boot entry or
discard the ISO. After installation, boot the rescue entry to repair the target
without running the guided launcher. Deleting the ISO is not sufficient if it
was lost; rotate the embedded Wi-Fi credential as well.

### Mediaserver Unattended ISO

The mediaserver has a separate, destructive ArchISO profile under:

```bash
~/.config/arch/archiso
```

Build it with:

```bash
~/.config/arch/archiso/build.sh
```

Validate the profile without building an ISO with:

```bash
~/.config/arch/archiso/build.sh --check
```

The generated ISO boots into an unattended installer that wipes the configured target disk, installs a minimal SSH-capable Arch system, creates the `vitorpy` user, enables `NetworkManager` plus `sshd`, and installs a first-boot service that applies the `mediaserver` Ansible profile locally.

Installer settings live in:

```bash
~/.config/arch/archiso/airootfs/etc/mediaserver-install.conf
```

Leave `INSTALL_TARGET_DISK` empty to use the first NVMe disk, or set it to a full path such as `/dev/nvme0n1` before building the ISO.

Do not write this ISO to a USB drive until you have confirmed the target block device with `lsblk`. The installer itself is intentionally destructive once booted.

After the first boot, the host should converge itself with the `media_servers` Ansible group. Logs are written to `/var/log/mediaserver-firstboot.log`. The `/mnt/media` mount is present in host vars but disabled until the real media disk UUID replaces `UUID=CHANGEME`.

### Minimum Requirements During Install

Make sure the installed system includes at least:

- `base`
- `linux`
- `linux-firmware`
- `networkmanager`
- `sudo`
- `git`

Also ensure:

- your user is created during install
- that user is in `wheel`
- `sudo` is usable after first boot

## First Boot

After rebooting into the installed system:

1. connect to the network if needed
2. install the bootstrap tools if they are not already present:

```bash
sudo pacman -Syu --needed ansible chezmoi bitwarden-cli git jq
```

3. run the bootstrap entrypoint:

```bash
curl -sSL https://vitorpy.com/bootstrap.sh | bash
```

That script now:

- configures Bitwarden
- applies dotfiles with `chezmoi`
- restores SSH and GPG keys from Bitwarden
- runs `~/.config/arch/apply-ansible.sh`

## Manual Alternative

If you do not want to use the bootstrap wrapper, the equivalent flow is:

```bash
chezmoi init --apply https://github.com/vitorpy/dotfiles.git
~/.config/arch/apply-ansible.sh
```

If you also want keys restored from Bitwarden:

```bash
bw config server https://vault.bitwarden.eu
export BW_SESSION="$(bw unlock --raw)"
~/.config/arch/restore-keys-from-bitwarden.sh
```

## Running the Playbook Directly

From `~/.config/arch/ansible`:

```bash
ansible-playbook site.yml
```

Or use the wrapper:

```bash
~/.config/arch/apply-ansible.sh
```

If `sudo` authenticates via fingerprint, make sure that `sudo -n true` succeeds after `sudo -v`. On this machine that is handled with a sudoers override using `timestamp_type=global`.

If your sudo setup still cannot provide a reusable non-interactive ticket, run:

```bash
ansible-playbook -K site.yml
```

## Boot Role

The playbook includes an optional `boot` role, but it is disabled by default.

Enable it only after setting machine-specific variables such as:

- `arch_boot_enabled: true`
- `arch_luks_uuid`
- optionally `arch_manage_secure_boot: true`

Those values live in the Ansible vars, not in a separate installer script.

## Troubleshooting

### No network after first boot

```bash
nmcli device status
nmcli device wifi list
nmcli device wifi connect "SSID" password "password"
```

### `ansible-playbook` not found

```bash
sudo pacman -S ansible
```

### Apply only the current `arch` subtree from chezmoi

```bash
chezmoi apply ~/.config/arch
```

## Ongoing Use

For ongoing machine configuration changes:

1. edit the Ansible vars or roles under `~/.config/arch/ansible`
2. re-apply with `~/.config/arch/apply-ansible.sh`
3. re-add and commit through the `chezmoi` source repo
