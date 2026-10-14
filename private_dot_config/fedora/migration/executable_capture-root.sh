#!/usr/bin/env bash
# USER-RUN ONLY: sudo ~/.config/fedora/migration/capture-root.sh > root-reference.tar
# The caller must redirect to a private file on the laptop, then back it up encrypted.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run this read-only capture as root.' >&2; exit 1; }
paths=(etc boot root)
for path in var/lib/NetworkManager var/lib/bluetooth var/lib/fprint var/lib/arts-wallpaper; do
    [[ ! -e /$path ]] || paths+=("$path")
done
exec tar --acls --xattrs --numeric-owner -C / -cf - "${paths[@]}"
