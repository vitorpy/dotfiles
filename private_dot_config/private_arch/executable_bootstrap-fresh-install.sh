#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_USER_SCRIPT="$SCRIPT_DIR/bootstrap-user.sh"

if [[ ! -f "$BOOTSTRAP_USER_SCRIPT" ]]; then
  BOOTSTRAP_USER_SCRIPT="$SCRIPT_DIR/executable_bootstrap-user.sh"
fi

if [[ ! -f "$BOOTSTRAP_USER_SCRIPT" ]]; then
  echo "ERROR: bootstrap-user.sh not found next to $0" >&2
  exit 1
fi

echo "==> bootstrap-fresh-install.sh is now a compatibility wrapper"
"$BOOTSTRAP_USER_SCRIPT"
