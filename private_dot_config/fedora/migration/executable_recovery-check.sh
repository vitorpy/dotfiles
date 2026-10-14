#!/usr/bin/env bash
# Run on a separate device; restore only the known public migration fixture.
set -euo pipefail
umask 077
case $(hostname -s) in
  rivest|scherbius|fedora44-*) echo 'Run this recovery check on a separate personal device.' >&2; exit 2 ;;
esac
command -v restic >/dev/null || { echo 'Install restic using the package manager on this device first.' >&2; exit 2; }
repo=sftp:mediaserver:/mnt/media/backups/rivest-restic
snapshot=${1:-7828297443a93c8614c7e856cf04c28066e0341bfcd7cdffee9808b13eb5b0a1}
fixture=/home/vitorpy/.local/state/fedora-migration/restore-fixture/record.txt
scratch=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/fedora-recovery-check.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
printf 'Open Bitwarden independently and find "Rivest migration backup".\n'
read -r -s -p 'Repository password: ' migration_password
printf '\n'
printf '%s\n' "$migration_password" > "$scratch/password"
unset migration_password
export RESTIC_REPOSITORY=$repo RESTIC_PASSWORD_FILE=$scratch/password
restic snapshots --host rivest --tag fedora-migration
restic restore "$snapshot" --include "$fixture" --verify --target "$scratch/restore"
printf '%s  %s\n' e7eb1d6fb7fae35e74c9867bfbee0b9de221242b3484af40edebf06f89f4a775 "$scratch/restore$fixture" | sha256sum --check --status
printf 'Independent recovery check passed for snapshot %s\n' "$snapshot"
