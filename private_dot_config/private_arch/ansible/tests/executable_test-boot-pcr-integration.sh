#!/usr/bin/env bash
# Build non-bootable test UKIs using the real ukify/systemd-measure toolchain.
set -euo pipefail
umask 077
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v ukify >/dev/null
test_root="$(mktemp -d /tmp/boot-pcr-integration.XXXXXX)"
trap 'rm -rf -- "$test_root"' EXIT

ukify --config=/dev/null \
  --pcr-private-key="$test_root/private.pem" \
  --pcr-public-key="$test_root/public.pem" genkey
sed -e "s|/etc/systemd/tpm2-pcr-private-key.pem|$test_root/private.pem|g" \
    -e "s|/etc/systemd/tpm2-pcr-public-key.pem|$test_root/public.pem|g" \
  "$repo_root/roles/boot/templates/uki.conf.j2" > "$test_root/uki.conf"
ukify --config="$test_root/uki.conf" --output=/dev/null --summary build > "$test_root/summary"

for image in default fallback; do
  printf 'Non-bootable %s fixture\n' "$image" > "$test_root/initrd"
  ukify --config="$test_root/uki.conf" \
    --linux=/usr/lib/systemd/boot/efi/linuxx64.efi.stub \
    --initrd="$test_root/initrd" --uname=pcr-test \
    --output="$test_root/$image.efi" build
  python3 "$repo_root/roles/boot/files/boot-pcr-check.py" \
    uki "$test_root/$image.efi" "$test_root/public.pem" | jq -e '.valid == true' >/dev/null
done

# The initial unsigned-PCR image must request a rebuild rather than crash.
ukify --config=/dev/null --linux=/usr/lib/systemd/boot/efi/linuxx64.efi.stub \
  --initrd="$test_root/initrd" --uname=pcr-test --output="$test_root/no-pcr.efi" build
python3 "$repo_root/roles/boot/files/boot-pcr-check.py" \
  uki "$test_root/no-pcr.efi" "$test_root/public.pem" | jq -e '.valid == false' >/dev/null

# Changing the expected key must reject an otherwise valid native image.
ukify --config=/dev/null \
  --pcr-private-key="$test_root/other-private.pem" \
  --pcr-public-key="$test_root/other-public.pem" genkey
python3 "$repo_root/roles/boot/files/boot-pcr-check.py" \
  uki "$test_root/default.efi" "$test_root/other-public.pem" | jq -e '.valid == false' >/dev/null
echo "Native ukify PCR signing and signature validation passed"
