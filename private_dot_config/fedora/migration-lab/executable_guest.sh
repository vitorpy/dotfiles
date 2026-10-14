#!/usr/bin/env bash
set -euo pipefail
lab_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fedora-migration-lab"
if [[ $# -lt 1 || ( "$1" != root && "$1" != vitorpy ) ]]; then
    printf 'Usage: %s {root|vitorpy} [guest command ...]\n' "$0" >&2
    exit 2
fi
guest_user=$1
shift
exec ssh -i "$lab_dir/id_ed25519" -p 22244 \
    -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 \
    -o ForwardAgent=no -o StrictHostKeyChecking=accept-new \
    -o "UserKnownHostsFile=$lab_dir/known_hosts" \
    "$guest_user@127.0.0.1" "$@"
