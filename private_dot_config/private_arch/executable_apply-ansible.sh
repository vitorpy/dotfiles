#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYBOOK_DIR="$SCRIPT_DIR/ansible"

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "ERROR: ansible-playbook is not installed." >&2
  echo "Install it first with: pacman -S ansible" >&2
  exit 1
fi

echo "==> Refreshing sudo credentials..."
sudo -v

MISSING_AUR="$(bash -lc '
declared_aur=$(awk '\''/^arch_pacman_packages_[a-z_]+:$/ {mode="pacman"; next} /^arch_aur_packages_[a-z_]+:$/ {mode="aur"; next} /^[^ ]/ {mode=""} mode=="aur" && /^  - / {print substr($0,5)}'\'' "'"$PLAYBOOK_DIR"'/group_vars/all.yml" | sort -u)
for pkg in $declared_aur; do
  pacman -Q "$pkg" >/dev/null 2>&1 || echo "$pkg"
done
')"

if [[ -n "$MISSING_AUR" ]]; then
  echo "ERROR: Missing declared AUR packages detected:" >&2
  printf '  - %s\n' $MISSING_AUR >&2
  echo "This wrapper runs ansible itself as root to avoid localhost sudo/become issues." >&2
  echo "That is safe for package pruning, but not for bootstrapping missing AUR packages." >&2
  echo "Resolve the missing AUR packages first or refactor the AUR install path." >&2
  exit 1
fi

exec sudo ansible-playbook -e ansible_become=false "$PLAYBOOK_DIR/site.yml" "$@"
