#!/usr/bin/env bash
set -euo pipefail
lab=${XDG_DATA_HOME:-$HOME/.local/share}/fedora-kde-rehearsal
[[ ${1:-} == root || ${1:-} == vitorpy ]] || { echo "Usage: $0 {root|vitorpy} [command ...]" >&2; exit 2; }
guest_user=$1; shift
exec ssh -i "${XDG_DATA_HOME:-$HOME/.local/share}/fedora-migration-lab/id_ed25519" -p 22245 \
    -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o ForwardAgent=no \
    -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$lab/known_hosts" \
    "$guest_user@127.0.0.1" "$@"
