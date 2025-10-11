#!/bin/bash
# Bootstrap script for fresh Arch Linux install
# Usage: curl -sSL https://your-site.com/bootstrap.sh | bash

set -e

echo "==> Arch Linux Bootstrap Script"
echo ""

# Install essential tools
echo "==> Installing essential packages..."
sudo pacman -Syu --needed --noconfirm chezmoi bitwarden-cli git jq

# Configure Bitwarden for EU server
echo "==> Configuring Bitwarden..."
bw config server https://vault.bitwarden.eu

# Unlock Bitwarden
echo "==> Unlocking Bitwarden..."
export BW_SESSION=$(bw unlock --raw)

if [ -z "$BW_SESSION" ]; then
    echo "ERROR: Failed to unlock Bitwarden"
    exit 1
fi

# Clone dotfiles via HTTPS (no SSH key needed yet)
echo "==> Cloning dotfiles..."
chezmoi init --apply https://tangled.sh/vitorpy.com/dotfiles

# Restore SSH and GPG keys from Bitwarden
echo "==> Restoring SSH and GPG keys from Bitwarden..."
~/.config/arch/restore-keys-from-bitwarden.sh

# Add SSH keys to agent
echo "==> Adding SSH keys to ssh-agent..."
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/github
ssh-add ~/.ssh/id_ed25519

# Switch chezmoi to SSH remote
echo "==> Switching chezmoi remote to SSH..."
cd $(chezmoi source-path)
git remote set-url origin git@tangled.sh:vitorpy.com/dotfiles

# Install all packages
echo "==> Installing all packages..."
~/.config/arch/install-packages.sh

# Install ly configuration
echo "==> Installing ly configuration..."
~/.config/arch/install-ly-config.sh

# Configure silent boot
echo "==> Configuring silent boot..."
~/.config/arch/configure-silent-boot.sh

# Setup Docker
echo "==> Setting up Docker..."
~/.config/arch/setup-docker.sh

# Enable ly display manager
echo "==> Enabling ly display manager..."
sudo systemctl enable ly.service
sudo systemctl disable getty@tty2.service

echo ""
echo "==> Bootstrap complete!"
echo ""
echo "Next steps:"
echo "  1. Install hyprcorners: cargo install hyprcorners"
echo "  2. Reboot to start Hyprland with ly display manager"
echo "  3. Enjoy your system!"
