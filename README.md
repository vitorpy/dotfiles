# vitorpy's Dotfiles

Managed with [chezmoi](https://www.chezmoi.io/).

## Installation

### On a new machine

Install chezmoi and apply dotfiles in one command:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply git@github.com:vitorpy/dotfiles.git
```

Or if you already have chezmoi installed:

```bash
chezmoi init --apply git@github.com:vitorpy/dotfiles.git
```

## Managed Configurations

- **Fish shell** (`~/.config/fish/`) - Terminal shell configuration with custom functions and plugins
- **Ghostty** (`~/.config/ghostty/config`) - Terminal emulator settings
- **Fonts** (`~/.local/share/fonts/`) - CaskaydiaMono Nerd Fonts collection

## Daily Usage

### Edit configurations
```bash
chezmoi edit ~/.config/fish/config.fish
chezmoi edit ~/.config/ghostty/config
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

## Configuration

Chezmoi is configured to use `nvim` as the default editor. Configuration file is at `~/.config/chezmoi/chezmoi.toml`.

## Security Notes

- API keys and sensitive data should use chezmoi's template feature or encrypted files
- Never commit secrets directly to the repository
- Use environment variables or secure secret management for sensitive values

## Structure

- `private_dot_config/` - Maps to `~/.config/`
- `private_dot_local/` - Maps to `~/.local/`
- Files prefixed with `private_` are created with restricted permissions (readable only by owner)

## Troubleshooting

If configurations don't apply correctly:

1. Check the diff: `chezmoi diff`
2. Force re-apply: `chezmoi apply --force`
3. Verify managed files: `chezmoi managed`
4. Check chezmoi status: `chezmoi status`

## License

Personal configuration files - use at your own discretion.