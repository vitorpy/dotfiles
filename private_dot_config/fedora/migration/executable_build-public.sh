#!/usr/bin/env bash
# Root only INSIDE the Fedora build guest. Public inputs only.
set -euo pipefail
[[ $EUID == 0 && $(hostname -s) == fedora44-kde-lab ]]
work=${1:?Usage: build-public.sh WORK_DIRECTORY INPUT_ISO}
input=${2:?}
[[ -d $work/migration-payload && -f $work/install.ks && -f $input ]]
# Pinned from the Fedora 44 signed Everything checksum verified during preparation.
printf '%s  %s\n' bd285201494dd0ba09b54d05ac707de1401668b8512a573edb5922dcf9d7067e "$input" | sha256sum --check --status
install -d "$work/migration-payload/bin"
install -m 755 /usr/bin/age "$work/migration-payload/bin/age"
install -m 755 /usr/bin/implantisomd5 /usr/bin/checkisomd5 "$work/migration-payload/bin/"
# Restic is supplied from the already verified upstream static binary, avoiding
# a dependency on a newer Fedora libc in the older installer runtime.
[[ -x $work/migration-payload/bin/restic ]]
rpm -V age isomd5sum
rpm -q age isomd5sum lorax pykickstart > "$work/migration-payload/build-packages.txt"
python3 - "$work/migration-payload" <<'PY'
import hashlib,json,sys
from pathlib import Path
p=Path(sys.argv[1])
h={str(f.relative_to(p)):hashlib.file_digest(f.open('rb'),'sha256').hexdigest()
   for f in sorted(p.rglob('*')) if f.is_file() and f.name != 'files.json'}
(p/'files.json').write_text(json.dumps(h,indent=2,sort_keys=True)+'\n')
PY
# The generated include only exists after the guard succeeds. Supply a harmless
# empty file solely for parser validation, not for booting or partitioning.
mkdir -p /run/rivest-migration
touch /run/rivest-migration/confirmed.ks
ksvalidator --version F44 "$work/install.ks"
mkksiso --ks "$work/install.ks" --add "$work/migration-payload" \
    --cmdline 'inst.text console=tty1 inst.nosave=all' --rm-args 'quiet' \
    "$input" "$work/rivest-guided.iso"
checkisomd5 "$work/rivest-guided.iso" </dev/null > "$work/iso-media-check.log" 2>&1
sha256sum "$work/rivest-guided.iso" > "$work/rivest-guided.iso.sha256"
