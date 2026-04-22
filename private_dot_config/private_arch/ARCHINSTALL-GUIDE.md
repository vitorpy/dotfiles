# Arch Linux Installation Guide

This guide reflects the current setup model:

- install a working Arch base system using your preferred installer
- apply dotfiles with `chezmoi`
- configure system-wide state with the Ansible playbook in `~/.config/arch/ansible`

There is no longer a managed `archinstall` JSON profile in this repo.

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
- desktop/session setup such as keyboard defaults and `ly`
- optional bootloader and Secure Boot state if you enable that role explicitly

## Base Install

Use either:

1. `archinstall`
2. the manual Arch install process

The repo no longer dictates disk layout through a checked-in installer profile, so pick the install method that matches the machine.

### Mediaserver Unattended ISO

The mediaserver has a separate, destructive ArchISO profile under:

```bash
~/.config/arch/archiso
```

Build it with:

```bash
~/.config/arch/archiso/build.sh
```

The generated ISO boots into an unattended installer that wipes the first NVMe disk, installs a minimal SSH-capable Arch system, creates the `vitorpy` user, and enables `NetworkManager` plus `sshd` for first-boot access.

Do not write this ISO to a USB drive until you have confirmed the target block device with `lsblk`. The installer itself is intentionally destructive once booted.

After the first boot, converge the host with the `media_servers` Ansible group. The `/mnt/media` mount is present in host vars but disabled until the real media disk UUID replaces `UUID=CHANGEME`.

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
