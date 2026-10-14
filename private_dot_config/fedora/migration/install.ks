# Guarded physical installer: every destructive directive is generated in %pre.
text
url --url=https://dl.fedoraproject.org/pub/fedora/linux/releases/44/Everything/x86_64/os/
lang en_US.UTF-8
keyboard us
timezone Europe/Warsaw --utc
rootpw --lock
selinux --enforcing
firewall --enabled
firstboot --disable
reboot --eject
%include /run/rivest-migration/confirmed.ks

%pre --interpreter=/bin/bash --erroronfail
set -euo pipefail
umask 077
payload=
for base in /run/install/repo /run/install/source; do
    if [[ -f $base/migration-payload/installer.py ]]; then payload=$base/migration-payload; break; fi
done
[[ -n $payload ]]
# A separate controlling terminal lets age and getpass use hidden input. The
# Anaconda log never receives terminal keystrokes or generated secret directives.
setsid --wait /bin/bash -c 'exec </dev/tty1 >/dev/tty1 2>&1; exec python3 -u "$1/installer.py" pre "$1"' bash "$payload"
%end

%packages
@^kde-desktop-environment
ansible-core
ansible-collection-community-general
python3-libdnf5
python3-dbus
python3-psutil
rsync
restic
age
NetworkManager-tui
git
%end

%post --nochroot --interpreter=/bin/bash --erroronfail
set -euo pipefail
umask 077
payload=$(cat /run/rivest-migration/payload-path)
python3 -u "$payload/installer.py" post "$payload"
%end
