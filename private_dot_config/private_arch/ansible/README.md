# Arch Ansible Bootstrap

This directory is the first pass of migrating the system-wide Arch bootstrap flow to Ansible.

## Scope

This playbook is intended for **post-install host configuration**:

- timezone, locale, hostname, hosts file
- primary user and wheel sudoers drop-in
- pacman and AUR packages
- system services
- X11 keyboard defaults
- `ly` deployment from `~/.config/ly`
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

## Profiles

- `group_vars/workstation.yml` enables desktop, `ly`, and the full package set.
- `group_vars/server.yml` keeps a smaller CLI-oriented package set and disables desktop roles.

To target a different host or profile, extend `inventory/hosts.yml`.

## Boot Role

The `boot` role is off by default because it needs machine-specific values.

Before enabling it, set:

- `arch_boot_enabled: true`
- `arch_luks_uuid`
- optionally `arch_manage_secure_boot: true`

This role manages `/etc/kernel/cmdline`, mkinitcpio hooks, UKI preset, `systemd-boot`, and optional `sbctl` signing.

## Open Gaps

- Password prompting is intentionally left out.
- Bitwarden restore remains a separate explicit step.
- AUR management still depends on `yay`, which this playbook bootstraps if missing.
