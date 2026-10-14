#!/usr/bin/env bash
# Configure only the encrypted KDE VM's user session; retain Plasma Login Manager.
set -euo pipefail
[[ $EUID == 0 && $(uname -n) == fedora44-kde-lab ]] || { echo 'Run only as root inside fedora44-kde-lab.' >&2; exit 1; }
# shellcheck disable=SC1091
source /etc/os-release
[[ $ID == fedora && $VERSION_ID == 44 ]]
root=/home/vitorpy
if [[ ! -f $root/.config/hypr/hyprland.workstation.lua ]]; then
    cp "$root/.config/hypr/hyprland.lua" "$root/.config/hypr/hyprland.workstation.lua"
fi
python3 - <<'PY'
from pathlib import Path
import re
p=Path('/home/vitorpy/.config/hypr')
s=(p/'hyprland.workstation.lua').read_text()
s,count=re.subn(r'hl\.on\("hyprland\.start", function\(\)\n.*?\nend\)', '-- Personal application autostarts omitted only in this VM.',s,count=1,flags=re.S)
assert count==1, 'Expected a single workstation autostart block'
s=s.replace('output = "", mode = "preferred"','output = "", mode = "1280x800@60"',1)
s+='\n-- VM-only software rendering and UWSM startup completion.\nhl.config({ animations = { enabled = false }, decoration = { blur = { enabled = false } } })\nhl.on("hyprland.start", function() hl.exec_cmd("uwsm finalize") end)\n'
(p/'hyprland.lua').write_text(s)
p=Path('/home/vitorpy/.config/uwsm/env-hyprland')
s=p.read_text()
marker='\n# Software-rendered VM only.\n'
if marker not in s:
    p.write_text(s+marker+'export LIBGL_ALWAYS_SOFTWARE=1\nexport QT_QUICK_BACKEND=software\nexport AQ_NO_MODIFIERS=1\n')
PY
install -d "$root/.local/share/applications" "$root/.local/state/fedora-migration-lab"
cat > "$root/.local/share/applications/org.vitorpy.berg.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Berg
Exec=/usr/bin/qs -c berg
Icon=preferences-system-panel
NoDisplay=true
DESKTOP
chown -R vitorpy:vitorpy "$root/.config/hypr" "$root/.config/uwsm" "$root/.local"
restorecon -RF "$root/.config" "$root/.local"
runuser -u vitorpy -- env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
    systemctl --user daemon-reload
printf 'KDE VM user config ready; select the packaged Hyprland (uwsm-managed) session.\n'
