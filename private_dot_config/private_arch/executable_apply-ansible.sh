#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYBOOK_DIR="$SCRIPT_DIR/ansible"

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "ERROR: ansible-playbook is not installed." >&2
  echo "Install it first with: pacman -S ansible" >&2
  exit 1
fi

exec ansible-playbook -K "$PLAYBOOK_DIR/site.yml" "$@"
