#!/usr/bin/env bash
# Explicit migration backups; no retention pruning or unattended secret access.
set -euo pipefail
umask 077
repo=sftp:mediaserver:/mnt/media/backups/rivest-restic
state=${XDG_STATE_HOME:-$HOME/.local/state}/fedora-migration
mkdir -p "$state"
chmod 700 "$state"
export RESTIC_REPOSITORY=$repo
if [[ -z ${RESTIC_PASSWORD_COMMAND:-} && -z ${RESTIC_PASSWORD_FILE:-} && -z ${RESTIC_PASSWORD:-} ]]; then
    echo 'Supply RESTIC_PASSWORD_FILE or RESTIC_PASSWORD_COMMAND using the password saved in Bitwarden.' >&2
    exit 2
fi
restic_bin=$(command -v restic || true)
[[ -n $restic_bin ]] || restic_bin=$HOME/.local/bin/restic
restic_options=()
if [[ -n ${RESTIC_SFTP_ARGS:-} ]]; then
    restic_options=(-o "sftp.args=$RESTIC_SFTP_ARGS")
fi
case ${1:-} in
    init) exec "$restic_bin" "${restic_options[@]}" init ;;
    backup)
        "$restic_bin" "${restic_options[@]}" backup --host rivest --tag fedora-migration --one-file-system \
            --exclude-file "$(dirname "$0")/backup-excludes" --json \
            "$HOME" | tee "$state/backup-$(date +%Y%m%dT%H%M%S).jsonl"
        ;;
    check) exec "$restic_bin" "${restic_options[@]}" check --read-data ;;
    snapshots) exec "$restic_bin" "${restic_options[@]}" snapshots --host rivest --tag fedora-migration ;;
    *) printf 'Usage: %s {init|backup|check|snapshots}\nFor restore, use restic with RESTIC_REPOSITORY=%s and the recorded snapshot ID.\n' "$0" "$repo" >&2; exit 2 ;;
esac
