#!/bin/bash
set -euo pipefail

HOME_MIGRATION_MARKER="$HOME/.local/state/arch-home-migration"
MIGRATED_HOME=false

if [[ -f "$HOME_MIGRATION_MARKER" ]]; then
  MIGRATED_HOME=true
fi

echo "==> Arch Linux User Bootstrap"
echo

echo "==> Installing bootstrap tools..."
sudo pacman -Syu --needed --noconfirm chezmoi bitwarden-cli git jq

echo "==> Configuring Bitwarden..."
bw config server https://vault.bitwarden.eu

echo "==> Unlocking Bitwarden..."
export BW_SESSION
BW_SESSION="$(bw unlock --raw)"

if [[ -z "$BW_SESSION" ]]; then
  echo "ERROR: Failed to unlock Bitwarden" >&2
  exit 1
fi

echo "==> Applying dotfiles..."
if [[ -d "$HOME/.local/share/chezmoi/.git" ]]; then
  chezmoi apply
else
  chezmoi init --apply https://tangled.sh/vitorpy.com/dotfiles
fi

if [[ "$MIGRATED_HOME" == true ]]; then
  echo "==> Home migration detected; skipping Bitwarden key restore."
else
  echo "==> Restoring SSH and GPG keys from Bitwarden..."
  "$HOME/.config/arch/restore-keys-from-bitwarden.sh"
fi

echo "==> Adding SSH keys to ssh-agent..."
eval "$(ssh-agent -s)"
for key_path in "$HOME/.ssh/github" "$HOME/.ssh/id_ed25519"; do
  if [[ -f "$key_path" ]]; then
    ssh-add "$key_path"
  fi
done

echo "==> Switching chezmoi remote to SSH..."
cd "$(chezmoi source-path)"
git remote set-url origin git@tangled.sh:vitorpy.com/dotfiles

echo "==> Installing user/session packages..."
"$HOME/.config/arch/install-packages.sh"

echo "==> Installing ly configuration..."
"$HOME/.config/arch/install-ly-config.sh"

echo "==> Setting up Docker..."
"$HOME/.config/arch/setup-docker.sh"

echo "==> Configuring keyboard layout..."
"$HOME/.config/arch/configure-keyboard.sh"

echo "==> Enabling ly display manager..."
sudo systemctl enable ly.service
sudo systemctl disable getty@tty2.service

echo
echo "==> User bootstrap complete!"
echo "Silent boot was already configured by the installer."
echo "Next steps:"
echo "  1. Install hyprcorners: cargo install hyprcorners"
echo "  2. Reboot to start Hyprland with ly display manager"
