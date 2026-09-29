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

# A sudo timestamp from this shell may not be usable by Ansible's subprocesses.
# Let Ansible collect and supply the password in its own become context.
ask_become_pass="${ARCH_ANSIBLE_ASK_BECOME_PASS:-1}"
case "$ask_become_pass" in
  0|1) ;;
  *) echo "ERROR: ARCH_ANSIBLE_ASK_BECOME_PASS must be 0 or 1." >&2; exit 2 ;;
esac
for arg in "$@"; do
  case "$arg" in
    -K|--ask-become-pass|--become-password-file|--become-password-file=*|\
    --become-pass-file|--become-pass-file=*|\
    -h|--help|--version|--syntax-check|--list-hosts|--list-tasks|--list-tags)
      ask_become_pass=0
      ;;
  esac
done
become_args=()
if [[ "$ask_become_pass" == 1 && "$EUID" != 0 ]]; then
  become_args+=(--ask-become-pass)
fi

cd "$PLAYBOOK_DIR"
exec ansible-playbook -i "$INVENTORY_FILE" site.yml "${become_args[@]}" "$@"
