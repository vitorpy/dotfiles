#!/usr/bin/env bash
# Run as the unprivileged Scherbius user. Never replaces an existing guest disk.
set -euo pipefail
umask 077
[[ $(uname -n) == scherbius ]] || { echo 'Run this helper on Scherbius.' >&2; exit 1; }
lab=${XDG_DATA_HOME:-$HOME/.local/share}/fedora-kde-rehearsal
cloud=${XDG_DATA_HOME:-$HOME/.local/share}/fedora-migration-lab
mkdir -p "$lab/images" "$lab/run" "$lab/seed"
[[ -f $cloud/id_ed25519.pub ]]
for edition in KDE Everything; do
    checksum=Fedora-$edition-44-1.7-x86_64-CHECKSUM
    if [[ $edition == KDE ]]; then
        image=Fedora-KDE-Desktop-Live-44-1.7.x86_64.iso
    else
        image=Fedora-Everything-netinst-x86_64-44-1.7.iso
    fi
    url=https://dl.fedoraproject.org/pub/fedora/linux/releases/44/$edition/x86_64/iso
    curl -fsSL --retry 3 "$url/$checksum" -o "$lab/images/$checksum"
    gpgv --homedir "$cloud/verification" --keyring "$cloud/verification/fedora.gpg" \
        --status-fd 1 "$lab/images/$checksum" > "$lab/images/$edition-signature.status" 2> "$lab/images/$edition-signature.log"
    grep -q 'VALIDSIG 36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6 ' "$lab/images/$edition-signature.status"
    sha=$(sed -n "s/^SHA256 ($image) = //p" "$lab/images/$checksum")
    [[ $sha =~ ^[0-9a-f]{64}$ ]]
    if [[ ! -f $lab/images/$image ]]; then
        curl -fsSL --retry 3 --connect-timeout 15 --max-time 1800 "$url/$image" -o "$lab/images/$image.part"
        printf '%s  %s\n' "$sha" "$lab/images/$image.part" | sha256sum -c
        mv "$lab/images/$image.part" "$lab/images/$image"
    fi
    printf '%s  %s\n' "$sha" "$lab/images/$image" | sha256sum -c
done
if [[ ! -f $lab/images/vmlinuz || ! -f $lab/images/initrd.img ]]; then
    xorriso -osirrox on -indev "$lab/images/Fedora-Everything-netinst-x86_64-44-1.7.iso" \
        -extract /images/pxeboot/vmlinuz "$lab/images/vmlinuz" \
        -extract /images/pxeboot/initrd.img "$lab/images/initrd.img" >/dev/null 2>&1
fi
python3 - <<'PY'
import os
from pathlib import Path
import secrets
import subprocess
lab=Path(os.environ.get('XDG_DATA_HOME', str(Path.home()/'.local/share')))/'fedora-kde-rehearsal'
cloud=lab.parent/'fedora-migration-lab'
p=lab/'console-password'
if not p.exists():
    p.write_text(secrets.token_hex(20)+'\n'); p.chmod(0o600)
password=p.read_text().strip()
hashed=subprocess.check_output(['openssl','passwd','-6','-stdin'],input=password.encode()).decode().strip()
key=(cloud/'id_ed25519.pub').read_text().strip()
(lab/'seed/install.ks').write_text(f'''# ONLY for the dedicated empty rehearsal VM; vda is its private virtual disk.
cmdline
url --url=https://dl.fedoraproject.org/pub/fedora/linux/releases/44/Everything/x86_64/os/
lang en_US.UTF-8
keyboard us
timezone Europe/Warsaw --utc
network --bootproto=dhcp --device=link --activate --hostname=fedora44-kde-lab
rootpw --lock
user --name=vitorpy --uid=1000 --groups=wheel --password={hashed} --iscrypted
selinux --enforcing
firewall --enabled --service=ssh
ignoredisk --only-use=vda
zerombr
clearpart --all --initlabel --drives=vda
autopart --type=btrfs --encrypted --passphrase={password}
services --enabled=sshd
shutdown
%packages
@^kde-desktop-environment
openssh-server
python3
%end
%post --erroronfail
install -d -m 700 /root/.ssh /home/vitorpy/.ssh
printf '%s\\n' '{key}' > /root/.ssh/authorized_keys
cp /root/.ssh/authorized_keys /home/vitorpy/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys /home/vitorpy/.ssh/authorized_keys
chown -R 1000:1000 /home/vitorpy/.ssh
restorecon -RF /root/.ssh /home/vitorpy/.ssh
systemctl enable sshd
# The initial user was created by Kickstart rather than the setup wizard.
touch /etc/plasma-setup-done
systemctl set-default graphical.target
%end
''')
(lab/'seed/install.ks').chmod(0o600)
PY
printf 'Verified media and private VM recipe ready. Start a loopback HTTP server on 48765 for --install.\n'
