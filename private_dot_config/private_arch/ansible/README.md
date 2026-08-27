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

## Workstation Memory Pressure

The workstation profile manages a capped zram device and a conservative
systemd-oomd policy. The zram formula grows gradually to 32 GiB, uses zstd, and
keeps swap priority 100. systemd-oomd monitors only `app.slice` at the upstream
90% swap and 60%-for-30s memory-pressure thresholds. Session infrastructure is
kept outside that boundary: Berg runs in `session.slice`, while the Box rclone
mount runs in `background.slice`; both are additionally marked
`ManagedOOMPreference=omit`.

Apply the Chezmoi user-unit changes first, reload the user manager, and restart
the two services before enabling oomd:

```bash
chezmoi apply ~/.config/systemd/user/quickshell-berg.service \
  ~/.config/systemd/user/rclone-box.service
systemctl --user daemon-reload
systemctl --user restart quickshell-berg.service rclone-box.service
systemctl --user show quickshell-berg.service rclone-box.service \
  -p Id -p Slice -p ManagedOOMPreference
~/.config/arch/apply-ansible.sh --limit localhost --tags memory
```

The Ansible run installs the policy and starts `systemd-oomd`; reboot once to
recreate zram at the new size. After reboot, verify with:

```bash
swapon --show=NAME,TYPE,SIZE,USED,PRIO --bytes
systemctl is-enabled --quiet systemd-oomd.service
systemctl is-active --quiet systemd-oomd.service
systemctl --user show app.slice \
  -p ManagedOOMSwap -p ManagedOOMMemoryPressure \
  -p ManagedOOMMemoryPressureLimit -p ManagedOOMMemoryPressureDurationUSec
oomctl
```

For rollback, set `arch_memory_pressure_enabled: false` in the workstation
variables and re-run the `memory` tag. This disables and stops systemd-oomd,
removes both oomd drop-ins, and restores zram-generator's default 4 GiB cap for
the next reboot. Revert the Berg/rclone unit classification and reapply those
two Chezmoi targets only if their original `app.slice` placement is also
desired.

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
- `arch_root_kernel_cmdline`
- `arch_esp_uuid`
- optionally `arch_manage_secure_boot: true`

This role manages `/etc/kernel/cmdline`, the complete mkinitcpio configuration,
default and fallback UKIs, `systemd-boot`, ESP permissions, and optional `sbctl`
signing. It verifies the ESP UUID, generated UKI metadata, embedded root and
security parameters, signatures, and both loader entries before changing the
loader default.

The role validates the root-only ESP fstab policy before the first reboot. It
does not cycle the ESP under a running system; after a managed UKI boot, the
role requires those options to be active before it retires any legacy entry.

The initial migration is intentionally gated. First verify that an Arch
installation medium boots and that the encrypted-home passphrase or recovery
method works. Then run the scoped play with
`-e arch_boot_recovery_confirmed=true`. The existing split boot entries remain
available for that first reboot. Once the running session is the managed
default UKI, the next play removes only the explicitly configured legacy entry
and initramfs paths.

For this workstation, the scoped migration command is:

```bash
cd ~/.config/arch/ansible
ansible-playbook -K --limit localhost \
  --tags boot,pacnew,keyring \
  -e arch_boot_recovery_confirmed=true site.yml
```

After the first reboot, run the same command without the extra variable to
retire the accepted split boot entries. Verify the result with `bootctl status`
and `sbctl verify` as root.

## Pacnew Reconciliation

The `pacnew` role is fail-closed. Every pending path must have a reviewed
SHA-256 checksum and exactly one action: accept upstream, preserve the current
file, or defer to a managed role. Any new or changed pacnew aborts the play for
a fresh review. The role verifies `pacdiff -o` is empty after a real run; check
mode validates the paths and checksums without claiming live convergence.

## GNOME Keyring Activation

The `keyring` role installs higher-priority per-user D-Bus service files for all
three GNOME Keyring activation names. They retain the packaged executable as a
fallback and add `SystemdService=gnome-keyring-daemon.service`, ensuring D-Bus
activation joins the existing supervised user service instead of starting a
second secrets-only daemon. A reboot or fresh login clears any daemon created
before the override was installed.

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
