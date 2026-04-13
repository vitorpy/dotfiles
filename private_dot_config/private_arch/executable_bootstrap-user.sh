#!/bin/bash
set -euo pipefail

echo "==> Arch Linux User Bootstrap"
echo

echo "==> Installing bootstrap tools..."
sudo pacman -Syu --needed --noconfirm ansible chezmoi bitwarden-cli git jq

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

echo "==> Restoring SSH and GPG keys from Bitwarden..."
"$HOME/.config/arch/restore-keys-from-bitwarden.sh"

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

echo "==> Applying system configuration with Ansible..."
"$HOME/.config/arch/apply-ansible.sh"

echo
echo "==> User bootstrap complete!"
echo "Next step: reboot to start Hyprland with ly display manager"
