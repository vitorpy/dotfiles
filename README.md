# vitorpy's Dotfiles

Managed with [chezmoi](https://www.chezmoi.io/).

## Quick Start

### Fresh Arch Linux Installation

**Step 1: Install Arch Linux**

Do a normal Arch install first. Then follow the post-install steps in
[`ARCHINSTALL-GUIDE.md`](.config/arch/ARCHINSTALL-GUIDE.md).

**Step 2: Bootstrap Your System**

After Arch installation and first boot, run the bootstrap script to set up everything:

```bash
curl -sSL https://vitorpy.com/bootstrap.sh | bash
```

This single command will:
- Install chezmoi, bitwarden-cli, git, jq, and ansible
- Configure Bitwarden for EU server
- Clone dotfiles via HTTPS (no SSH key needed)
- Restore SSH and GPG keys from Bitwarden
- Switch to SSH remote
- Apply the Arch system configuration with Ansible
- Enable the Berg-themed SDDM display manager

After the bootstrap completes, reboot to start Hyprland.

### Manual Installation

On a new machine with chezmoi already installed:

```bash
chezmoi init --apply https://github.com/vitorpy/dotfiles.git
```

Or install chezmoi and apply in one command:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply https://github.com/vitorpy/dotfiles.git
```

## Managed Configurations

### Core System
- **Hyprland** (`~/.config/hypr/`) - Wayland compositor configuration
- **Quickshell** (`~/.config/quickshell/berg/`) - Panel and notification shell
- **Hyprpaper** - Wallpaper daemon
- **Hypridle** - Idle management
- **Hyprlock** - Screen locker

### Shell & Terminal
- **Zsh** (`~/.zshrc`) - Interactive shell configuration
- **Starship** (`~/.config/starship.toml`) - Cross-shell prompt
- **Ghostty** (`~/.config/ghostty/config`) - Terminal emulator

### Development
- **Neovim** (`~/.config/nvim/`) - Editor configuration with plugins
  - lazy.nvim plugin manager
  - nvim-tree, toggleterm, zenburn theme
  - codecompanion.nvim for AI assistance (ACP support)
  - Custom `:IDE` command for window layout
- **Git** (`~/.gitconfig`) - Git configuration

### Theming
- **GTK/Qt** - Dark theme configuration (Adwaita + Kvantum)
- **Fonts** (`~/.local/share/fonts/`) - CaskaydiaMono Nerd Fonts collection

### Arch Linux System Management
- **Ansible Playbook** (`~/.config/arch/ansible/`) - Declarative system configuration
- **Apply Script** (`~/.config/arch/apply-ansible.sh`) - Wrapper for the local Ansible run

## Arch Linux Scripts

### Arts Wallpaper

`~/.local/bin/arts-wallpaper` selects a random provider from Google Arts &
Culture, Rijksmuseum, the Cleveland Museum of Art, MASP, and Muzeum Narodowe w
Warszawie (MNW). If the first provider fails, it tries the remaining providers
before leaving the current wallpaper unchanged. Rijksmuseum and MASP progress
is persisted so their collection pages advance through the available flat
artwork over time. Rijksmuseum accepts only paintings and drawings while
rejecting photographic and printmaking classifications and techniques. MASP
uses the public JSON route behind its collection
website and is configured for personal, non-distributed use with museum and
photographer attribution. MNW uses its official digital-catalogue API and
accepts only public-domain paintings, drawings, prints, and photographs with
images.

The user timer runs daily at 08:00 with up to five minutes of randomized delay,
and one minute after boot when needed:

```bash
systemctl --user status arts-wallpaper.timer
journalctl --user -u arts-wallpaper.service
```

Test a provider without changing the wallpaper or saved cursor state:

```bash
arts-wallpaper rotate --provider google --dry-run
arts-wallpaper rotate --provider rijksmuseum --dry-run
arts-wallpaper rotate --provider cleveland --dry-run
arts-wallpaper rotate --provider masp --dry-run
arts-wallpaper rotate --provider mnw --dry-run
```

Published files are under `/var/lib/arts-wallpaper/`. Each successful rotation
atomically publishes `current.webp` for Hyprpaper and Quickshell,
`current.png` for SDDM's Qt image loader, plus `current.json` and `state.json`.
To rebuild only the SDDM derivative from the current wallpaper, run:

```bash
arts-wallpaper render-greeter
```

The service needs Python 3, ImageMagick, Hyprpaper, and network access; these
packages are managed by the Arch configuration.

To roll back, revert the wallpaper-service commit in the chezmoi source, apply
chezmoi, reload the user systemd manager, and re-enable the restored timer. The
legacy `~/.local/share/google-arts/` data is intentionally retained.

### System Reconciliation

Apply the declarative Arch system configuration:
```bash
~/.config/arch/apply-ansible.sh
```

Or run the playbook directly:
```bash
cd ~/.config/arch/ansible
ansible-playbook site.yml
```

### Bitwarden Backup & Restore

Backup SSH and GPG keys to Bitwarden:
```bash
export BW_SESSION=$(bw unlock --raw)
~/.config/arch/backup-keys-to-bitwarden.sh
```

Backup secrets directory to Bitwarden:
```bash
export BW_SESSION=$(bw unlock --raw)
~/.config/arch/backup-secrets-to-bitwarden.sh
```

Restore SSH and GPG keys from Bitwarden:
```bash
export BW_SESSION=$(bw unlock --raw)
~/.config/arch/restore-keys-from-bitwarden.sh
```

Test restore without affecting your system:
```bash
~/.config/arch/restore-keys-from-bitwarden.sh --dry-run
```

## Daily Usage

### Edit configurations
```bash
chezmoi edit ~/.config/hypr/hyprland.conf
chezmoi edit ~/.zshrc
chezmoi edit ~/.config/nvim/init.lua
```

### See what would change
```bash
chezmoi diff
```

### Apply changes from the repo
```bash
chezmoi apply
```

### Update from remote and apply
```bash
chezmoi update
```

### Add new files to management
```bash
chezmoi add ~/.config/newconfig
```

### Push changes to GitHub
```bash
chezmoi cd
git add .
git commit -m "Update configs"
git push
```

Or use the shortcut:
```bash
chezmoi re-add && cd $(chezmoi source-path) && git add . && git commit -m "Your message" && git push
```

## Configuration

Chezmoi is configured to use `nvim` as the default editor. Configuration file is at `~/.config/chezmoi/chezmoi.toml`.

## Security Notes

- SSH and GPG keys are stored in Bitwarden, not in the dotfiles repo
- Secrets are restored separately from Bitwarden and kept out of the repository
- Never commit secrets directly to the repository
- The dotfiles repository is public - keep it clean!

## Structure

- `private_dot_config/` - Maps to `~/.config/`
- `private_dot_local/` - Maps to `~/.local/`
- Files prefixed with `private_` are created with restricted permissions (readable only by owner)
- Files prefixed with `executable_` are created with execute permissions

## Migration Workflow

### From Fedora to Arch

1. **Backup** (on Fedora):
   ```bash
   export BW_SESSION=$(bw unlock --raw)
   ~/.config/arch/backup-keys-to-bitwarden.sh
   ~/.config/arch/backup-secrets-to-bitwarden.sh
   ```

2. **Install Arch Linux** (fresh install)

3. **Bootstrap** (on fresh Arch):
   ```bash
   curl -sSL https://vitorpy.com/bootstrap.sh | bash
   sudo reboot
   ```

4. **Done!** All configs, packages, and keys restored.

## Troubleshooting

If configurations don't apply correctly:

1. Check the diff: `chezmoi diff`
2. Force re-apply: `chezmoi apply --force`
3. Verify managed files: `chezmoi managed`
4. Check chezmoi status: `chezmoi status`

For package installation issues:
```bash
# Check package source
yay -Ss package-name     # Search AUR
pacman -Ss package-name  # Search official repos
```

## License

Personal configuration files - use at your own discretion.
