# Arch Ansible Bootstrap

This directory is the source of truth for system-wide Arch host configuration on this machine.

## Scope

This playbook is intended for **post-install host configuration**:

- timezone, locale, hostname, hosts file
- primary user and wheel sudoers drop-in
- pacman and AUR packages
- system services
- SSH, firewall, and sysctl hardening
- X11 keyboard defaults
- SDDM deployment with a Wayland-native Berg greeter
- shared artwork wallpaper state under `/var/lib/arts-wallpaper`
- optional bootloader and mkinitcpio management

The old destructive LUKS/bootstrap installer has been removed from this tree.

## Recommended Flow

1. Install Arch using your preferred base install flow.
2. Boot into the installed system.
3. Apply dotfiles with `chezmoi`.
4. Run this playbook for ongoing system state.
5. Restore keys and secrets separately if needed.

## Usage

From `~/.config/arch/ansible`:

```bash
ansible-playbook site.yml
```

`localhost` is the default workstation target via the included inventory.

On this machine, `sudo` may authenticate via fingerprint. For localhost `become` to work reliably, `sudo -n true` must succeed after `sudo -v`. If needed, configure sudo with `timestamp_type=global` or fall back to `ansible-playbook -K site.yml`.

This playbook also manages a basic security baseline:

- `sshd` hardening drop-in
- `nftables` firewall
- sysctl hardening
- optional AppArmor enablement via systemd-boot entry parameters
- optional kernel lockdown mode via systemd-boot entry parameters

If AppArmor or kernel lockdown boot parameters change, reboot after applying the playbook.

## Profiles

- `group_vars/workstation.yml` enables desktop, SDDM, and the full package set.
- `group_vars/server.yml` keeps a smaller CLI-oriented package set and disables desktop roles.

To target a different host or profile, extend `inventory/hosts.yml`.

## SDDM and Recovery

The workstation uses the Berg SDDM theme on a minimal Wayland Hyprland Lua
greeter. Artwork and its public metadata live in
`/var/lib/arts-wallpaper`, which is writable by the primary user and readable
by the `sddm` user through the `arts-wallpaper` group. Hyprpaper and Quickshell
use `current.webp`; the wallpaper publisher also atomically renders
`current.png` for SDDM's Qt image loader.

The `sddm` role creates and maintains the shared artwork directory, installs the
Berg theme and greeter configuration, enables SDDM, and keeps tty2 enabled as a
recovery console. Applying the role does not start or restart SDDM in the active
desktop session.

If the graphical greeter fails, switch to tty2 and inspect SDDM from there:

```bash
sudo systemctl status sddm.service
sudo journalctl -b -u sddm.service
sudo systemctl restart sddm.service
```

To keep graphical login disabled across a reboot while repairing it, run
`sudo systemctl disable sddm.service`. Re-enable it with
`sudo systemctl enable sddm.service` after the repair; tty2 remains enabled.

## Boot Role

The `boot` role is off by default because it needs machine-specific values.

Before enabling it, set:

- `arch_boot_enabled: true`
- `arch_luks_uuid`
- optionally `arch_manage_secure_boot: true`

This role manages `/etc/kernel/cmdline`, mkinitcpio hooks, UKI preset, `systemd-boot`, and optional `sbctl` signing.

## BitMagnet Role

The optional `bitmagnet` role runs BitMagnet and PostgreSQL as rootless Podman
Quadlets for the primary user. It keeps the HTTP API bound to the configured
private address while publishing only the BitTorrent/DHT port publicly. It does
not create or modify an nginx virtual host, and PostgreSQL is reachable only on
the private container network.

Enable it in host variables with:

```yaml
arch_bitmagnet_enabled: true
arch_bitmagnet_http_bind: 100.x.y.z
```

`arch_bitmagnet_dht_bootstrap_nodes` can provide an explicit list of bootstrap
endpoints when the upstream hostname defaults are not reachable. An empty list
keeps the upstream defaults.

BitMagnet v0.10.0 has an upstream IPv4-mapped address bug that prevents DHT
bootstrap on affected hosts. With `arch_bitmagnet_build_patched_image: true`,
the role builds a local image from the exact v0.10.0 release commit, applies the
focused fix and regression test from upstream PR 510, and runs the full Go test
suite during the image build. The final runtime layer is pinned by digest.

Rootless Podman may not return DHT replies when the published host port and the
container's UDP source port are identical. Set
`arch_bitmagnet_container_bittorrent_port` to a different internal port; the
role configures `DHT_SERVER_PORT` and preserves the public host port through the
Quadlet mapping.

If `arch_bitmagnet_tmdb_source_host` is set, the role copies only a v3
`TMDB_API_KEY` from that host and stores it in a mode-`0600` runtime environment
file. If it is unset, BitMagnet uses its built-in shared key. TMDB v4 bearer
tokens such as `TMDB_API_TOKEN` are not compatible with BitMagnet v0.10.0.

The PostgreSQL password is generated on the destination host and is never
committed. An hourly user timer warns in the journal when root filesystem usage
reaches `arch_bitmagnet_disk_warning_percent`.

To roll back the running service without changing nginx, stop
`bitmagnet.service`, `bitmagnet-postgres.service`, and
`bitmagnet-disk-monitor.timer` in the primary user's systemd manager. Remove the
Quadlets only after deciding whether the `bitmagnet-postgres` volume should be
retained or deleted.

## Open Gaps

- Password prompting is intentionally left out.
- Bitwarden restore remains a separate explicit step.
- AUR management still depends on `yay`, which this playbook bootstraps if missing.
