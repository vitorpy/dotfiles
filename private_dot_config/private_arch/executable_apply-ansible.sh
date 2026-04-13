#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYBOOK_DIR="$SCRIPT_DIR/ansible"
INVENTORY_FILE="$PLAYBOOK_DIR/inventory/hosts.yml"

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "ERROR: ansible-playbook is not installed." >&2
  echo "Install it first with: pacman -S ansible" >&2
  exit 1
fi

echo "==> Refreshing sudo credentials..."
sudo -v

if ! sudo -n true >/dev/null 2>&1; then
  echo "ERROR: sudo credentials are not reusable non-interactively." >&2
  echo "Ansible localhost become needs a reusable sudo ticket." >&2
  echo "If you use fingerprint sudo, ensure 'sudo -n true' succeeds after 'sudo -v'." >&2
  echo "Otherwise run 'ansible-playbook -K site.yml' directly from $PLAYBOOK_DIR." >&2
  exit 1
fi

cd "$PLAYBOOK_DIR"
exec ansible-playbook -i "$INVENTORY_FILE" site.yml "$@"
