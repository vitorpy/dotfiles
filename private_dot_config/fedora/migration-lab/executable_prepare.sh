#!/usr/bin/env bash
# Run as vitorpy on Scherbius; all generated state stays in the user account.
set -euo pipefail
umask 077

lab_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fedora-migration-lab"
image_name=Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2
checksum_name=Fedora-Cloud-44-1.7-x86_64-CHECKSUM
image_url=https://dl.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images
fedora_fingerprint=36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6
image_sha256=28680fe5b371a5a82ebf43a31926e086a168e59949d03969c5093e7071f90b7f

for tool in curl gpgv sha256sum ssh-keygen xorriso python3; do
    command -v "$tool" >/dev/null || { printf 'Missing prerequisite: %s\n' "$tool" >&2; exit 1; }
done
mkdir -p "$lab_dir" "$lab_dir/images" "$lab_dir/seed" "$lab_dir/run" "$lab_dir/verification"
chmod 700 "$lab_dir" "$lab_dir/run" "$lab_dir/verification"

curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 120 \
    https://fedoraproject.org/fedora.gpg -o "$lab_dir/verification/fedora.gpg"
curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 120 \
    "$image_url/$checksum_name" -o "$lab_dir/verification/$checksum_name"

# Require a valid signature from the Fedora 44 key published on Fedora's security page.
gpgv --homedir "$lab_dir/verification" --keyring "$lab_dir/verification/fedora.gpg" \
    --status-fd 1 "$lab_dir/verification/$checksum_name" \
    > "$lab_dir/verification/signature.status" 2> "$lab_dir/verification/signature.log"
grep -q "^\[GNUPG:\] VALIDSIG $fedora_fingerprint " "$lab_dir/verification/signature.status"
grep -Fqx "SHA256 ($image_name) = $image_sha256" "$lab_dir/verification/$checksum_name"

if [[ ! -f "$lab_dir/images/$image_name" ]]; then
    curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 1800 \
        "$image_url/$image_name" -o "$lab_dir/images/$image_name.part"
    printf '%s  %s\n' "$image_sha256" "$lab_dir/images/$image_name.part" | sha256sum --check
    mv "$lab_dir/images/$image_name.part" "$lab_dir/images/$image_name"
fi
printf '%s  %s\n' "$image_sha256" "$lab_dir/images/$image_name" | sha256sum --check
chmod 400 "$lab_dir/images/$image_name"

# This key only administers the disposable VM; personal keys and agent forwarding are unnecessary.
if [[ ! -f "$lab_dir/id_ed25519" ]]; then
    ssh-keygen -q -t ed25519 -N '' -C fedora-migration-lab -f "$lab_dir/id_ed25519"
fi
chmod 600 "$lab_dir/id_ed25519"
public_key=$(cat "$lab_dir/id_ed25519.pub")
if [[ ! -f "$lab_dir/seed/seed.iso" ]]; then
    cat > "$lab_dir/seed/meta-data" <<'EOF'
instance-id: fedora44-migration-lab-01
local-hostname: fedora44-lab
EOF
    cat > "$lab_dir/seed/user-data" <<EOF
#cloud-config
hostname: fedora44-lab
manage_etc_hosts: true
disable_root: false
ssh_pwauth: false
users:
  - name: root
    lock_passwd: true
    ssh_authorized_keys:
      - $public_key
  - name: vitorpy
    uid: 1000
    groups: [wheel]
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - $public_key
package_update: true
package_upgrade: true
packages:
  - git
  - rsync
  - jq
  - python3
runcmd:
  - [systemctl, enable, --now, sshd]
final_message: Fedora migration lab cloud-init finished.
EOF
    xorriso -as mkisofs -quiet -output "$lab_dir/seed/seed.iso" -volid CIDATA -joliet -rock \
        "$lab_dir/seed/user-data" "$lab_dir/seed/meta-data"
fi
printf 'Prepared Fedora 44 image and cloud-init seed in %s\n' "$lab_dir"
printf 'SHA256 and Fedora 44 OpenPGP signature verified.\n'
