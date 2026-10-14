#!/usr/bin/env bash
# Public vendor key only; never read the user's GnuPG directory.
set -euo pipefail
[[ $# == 4 ]] || exit 2
artifact=$1 signature=$2 public_key=$3 fingerprint=$4
scratch=$(mktemp -d /tmp/fedora-artifact-verify.XXXXXX)
trap 'rm -rf -- "$scratch"' EXIT
gpg --batch --no-options --yes --homedir "$scratch" --dearmor \
    --output "$scratch/vendor.gpg" "$public_key"
status=$(gpgv --homedir "$scratch" --status-fd=1 --keyring "$scratch/vendor.gpg" \
    "$signature" "$artifact")
awk -v expected="$fingerprint" '$2 == "VALIDSIG" && ($3 == expected || $NF == expected) { valid=1 } END { exit !valid }' <<< "$status"
