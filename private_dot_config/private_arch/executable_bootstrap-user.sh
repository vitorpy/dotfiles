#!/bin/bash
set -euo pipefail

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
chezmoi init --apply https://tangled.sh/vitorpy.com/dotfiles

echo "==> Restoring SSH and GPG keys from Bitwarden..."
"$HOME/.config/arch/restore-keys-from-bitwarden.sh"

echo "==> Adding SSH keys to ssh-agent..."
eval "$(ssh-agent -s)"
ssh-add "$HOME/.ssh/github"
ssh-add "$HOME/.ssh/id_ed25519"

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
