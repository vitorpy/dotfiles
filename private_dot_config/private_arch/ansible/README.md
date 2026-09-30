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
ansible-playbook --limit zygalski site.yml
```

`zygalski` is the personal workstation target in the included inventory and uses
`ansible_connection: local`. Always select the intended host with `--limit`;
an unfiltered playbook run targets every inventory host.

The `apply-ansible.sh` helper asks for the sudo password through Ansible's
`--ask-become-pass` (`BECOME password:` prompt). Enter your account password;
a fingerprint or a sudo timestamp established in another shell is not a
substitute for this prompt. The helper does not run a separate `sudo -v`
or require changes to sudo timestamp policy. Ansible handles the password;
the helper does not read, store, or export it.

Explicit `-K`/`--ask-become-pass` or `--become-password-file` options are passed
through unchanged. For passwordless hosts or credentials already supplied
through Ansible, set `ARCH_ANSIBLE_ASK_BECOME_PASS=0`. Syntax checks, help,
version, and list operations do not prompt automatically; check mode still
can require privilege escalation. Arguments and Ansible's exit status are
preserved. Regression test: `python3 ../tests/test_apply_ansible.py`.

Rollback of this authentication change: revert its dotfiles commit and apply
`~/.config/arch/apply-ansible.sh` through chezmoi. With the older helper, pass
`--ask-become-pass` explicitly if Ansible cannot reuse the shell's sudo ticket.

This playbook also manages a basic security baseline:

- `sshd` hardening drop-in
- `nftables` firewall
- sysctl hardening
- optional AppArmor enablement via systemd-boot entry parameters
- optional kernel lockdown mode via systemd-boot entry parameters

If AppArmor or kernel lockdown boot parameters change, reboot after applying the playbook.

## AUR authentication

AUR builds run as `arch_primary_user`. Yay and the makepkg bootstrap invoke
sudo again when installing packages or dependencies; Ansible's outer become
authentication does not automatically authenticate those nested calls.
The local `aur_command` action forwards the configured Ansible become
credential (including `-K`) to `ansible.builtin.expect`, which answers the
fixed `SUDO_PROMPT` over a pseudo-terminal with input echo disabled.
No password is put in command arguments, environment variables, or a separate
persistent password file; normal Ansible module transport and cleanup apply.
Both credential-bearing tasks require `no_log: true`, so their detailed output
is suppressed. Passwordless hosts use the normal command path.
No sudoers rule or timestamp policy is changed.

`python-pexpect` is included in the effective native package list whenever AUR
packages are declared, so it is installed before use and retained by package
pruning. Both the yay bootstrap and regular AUR install use this mechanism.
Check mode skips builds. Validate the action without sudo using
`python3 tests/test_aur_command.py`. If an AUR task fails after authentication,
run the same yay install interactively to inspect its unsuppressed build error.
Rollback: revert the AUR-authentication commit and apply the packages task and
action changes through chezmoi; the older path again requires an independently
usable sudo ticket. No system security configuration needs restoring.

## Corporate smart-contract tooling

Corporate workstations install `noirup-bin` and `foundry-bin` from the AUR.
`noirup-bin` supplies the Noir toolchain installer, not Nargo itself: run
`noirup` as your user to select/install the project-required Noir toolchain.
Foundry uses prebuilt binaries, avoiding a local Rust build.

The packages role also installs the original `huffc` from the official
[huff-language/huff-rs release](https://github.com/huff-language/huff-rs/releases/tag/nightly-4c4ae27378224b6a3a1afd35116f0da710ff1418).
This legacy upstream is archived; it is retained for `huffc` compatibility,
not represented as an actively maintained compiler or replaced with huff2.
The Linux x86_64 artifact reports `huffc 0.3.2`. Its immutable-style commit tag
and locally computed SHA-256 are pinned in `group_vars/all.yml`; upstream does
not publish an independent checksum. Ansible verifies that pin on download,
extracts into `/usr/local/lib/huffc/<release>/`, and links `/usr/local/bin/huffc`.
Unsupported architectures fail explicitly. No installer script is piped to a
shell, and no Rust compilation is required. `arch_huffc_enabled` defaults to
false and is enabled only by the corporate profile.

After applying the managed Ansible configuration, run as your user (the helper
asks Ansible for the become password):

```bash
~/.config/arch/apply-ansible.sh --limit rivest --tags packages
# To install/update only the managed Huff binary:
~/.config/arch/apply-ansible.sh --limit rivest --tags huffc
huffc --version
forge --version
noirup --help
```

The packages tag also performs the existing declared-package pruning. Review
the package changes before applying. To update Huff, change the release pin
and reviewed archive checksum together. Re-running the role is idempotent.
For rollback, remove the two AUR entries and apply the packages tag (the
existing pruning removes undeclared explicit packages); disable Huff in the
corporate profile and manually remove only its managed `/usr/local/bin/huffc`
symlink and `/usr/local/lib/huffc/<release>/` directory with administrator
privileges. Disabling the flag alone leaves an existing Huff install intact.
User-installed Noir toolchains are managed separately by noirup.

## Profiles

- `group_vars/workstation.yml` enables desktop, SDDM, and the full package set.
- `group_vars/personal_workstation.yml` inherits the workstation profile and
  adds personal-only tools, including QGIS, Claude Code, and the official Notion CLI.
  QGIS uses the official Arch `qgis` package for geographic data analysis.
  `zygalski` is currently the only member.
- `group_vars/corp_workstation.yml` inherits the workstation profile and adds
  corporate-only packages, including the Roam workplace app (`roam` from the
  AUR). Rivest is currently the only member.
- `group_vars/server.yml` keeps a smaller CLI-oriented package set and disables desktop roles.

To target a different host or profile, extend `inventory/hosts.yml`.

To install Roam on Rivest, run
`~/.config/arch/apply-ansible.sh --limit rivest --tags packages` and provide
the administrator password when prompted. The existing AUR package role
installs its dependencies. To roll back, remove `roam` from
`arch_aur_packages_corporate`, synchronize with Chezmoi, and rerun that command;
the workstation profile prunes undeclared explicit packages.

`framework-system` is included on all workstations for Framework hardware tools
and uses the Arch official repositories. Apply the package configuration with
`~/.config/arch/apply-ansible.sh --limit zygalski --tags packages` (use
`--limit rivest` on the corporate workstation). To roll back this addition,
remove its package entry, synchronize with Chezmoi, and run the same command;
the workstation profile prunes undeclared explicit packages.

Before pruning, the packages role promotes declared native packages from
dependency-installed to explicitly installed. This ensures a package newly
declared as top-level state is retained even when the package was already
present only as another package's dependency.

Install or update only the personal-workstation Notion CLI with:

```bash
~/.config/arch/apply-ansible.sh --limit zygalski --tags notion-cli
```

## Workstation Memory Pressure

The workstation profile manages a capped zram device and a conservative
systemd-oomd policy. The zram formula grows gradually to 32 GiB, uses zstd, and
keeps swap priority 100. systemd-oomd monitors only `app.slice` at the upstream
90% swap and 60%-for-30s memory-pressure thresholds. Session infrastructure is
kept outside that boundary: Berg runs in `session.slice`, while the GDrive
rclone mount runs in `background.slice`; both are additionally marked
`ManagedOOMPreference=omit`.

Apply the Chezmoi user-unit changes first, reload the user manager, and restart
the two services before enabling oomd:

```bash
chezmoi apply ~/.config/systemd/user/quickshell-berg.service \
  ~/.config/systemd/user/rclone-gdrive.service
systemctl --user daemon-reload
systemctl --user restart quickshell-berg.service rclone-gdrive.service
systemctl --user show quickshell-berg.service rclone-gdrive.service \
  -p Id -p Slice -p ManagedOOMPreference
~/.config/arch/apply-ansible.sh --limit zygalski --tags memory
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

## Workstation File Descriptor Limits

The workstation profile raises systemd's default soft open-file limit from
1024 to 65536 while preserving the existing 524288 hard limit. Both the system
and per-user manager defaults are managed so shells, UWSM application scopes,
and user services inherit the same policy after a complete activation boundary.

Apply the policy with:

```bash
~/.config/arch/apply-ansible.sh --limit zygalski --tags limits
```

The Ansible role deliberately does not reexecute either systemd manager or
restart the graphical session. Reboot after applying, then verify a fresh
shell, Berg, and Chrome with:

```bash
ulimit -Sn
ulimit -Hn
systemctl --user show quickshell-berg.service \
  -p LimitNOFILESoft -p LimitNOFILE
prlimit --pid "$(pgrep -o -x chrome)" --nofile
```

The expected soft and hard values are 65536 and 524288. For rollback, set
`arch_file_descriptor_limits_enabled: false` in the workstation variables,
re-run the `limits` tag, and reboot. The role removes both manager drop-ins,
restoring systemd's packaged `1024:524288` default.

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
ansible-playbook -K --limit zygalski \
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
