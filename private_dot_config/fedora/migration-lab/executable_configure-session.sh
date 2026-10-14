#!/usr/bin/env bash
# Configure only the disposable guest after its desktop packages and test payload exist.
set -euo pipefail
if [[ $EUID -ne 0 || $(hostname) != fedora44-lab ]]; then
    printf 'This script requires root inside fedora44-lab.\n' >&2
    exit 1
fi
# shellcheck disable=SC1091
source /etc/os-release
[[ $ID == fedora && $VERSION_ID == 44 ]] || exit 1
for tool in Hyprland qs uwsm greetd agreety; do command -v "$tool" >/dev/null; done
guest_config=/home/vitorpy/.config
test -f "$guest_config/hypr/hyprland.lua"
test -f "$guest_config/quickshell/berg/shell.qml"
test -f "$guest_config/systemd/user/quickshell-berg.service"

# Preserve the exact workstation configuration for a separate compatibility check.
if [[ ! -f "$guest_config/hypr/hyprland.workstation.lua" ]]; then
    cp "$guest_config/hypr/hyprland.lua" "$guest_config/hypr/hyprland.workstation.lua"
fi
python3 - <<'PY'
from pathlib import Path
import re
root = Path('/home/vitorpy/.config/hypr')
original = (root / 'hyprland.workstation.lua').read_text()
# Omit personal application autostarts in the lab; keep the remaining desktop rules.
pattern = r'hl\.on\("hyprland\.start", function\(\)\n.*?\nend\)'
configured, count = re.subn(pattern, '-- Personal autostarts omitted in the disposable VM.', original, count=1, flags=re.S)
if count != 1:
    raise SystemExit('Expected one personal-autostart block; review the source configuration')
configured = configured.replace('output = "", mode = "preferred"', 'output = "", mode = "1280x800@60"', 1)
configured += '''
-- VM-only software rendering and UWSM session finalization.
hl.config({ animations = { enabled = false }, decoration = { blur = { enabled = false } } })
hl.on("hyprland.start", function()
    hl.exec_cmd("uwsm finalize")
end)
'''
(root / 'hyprland.lua').write_text(configured)
PY

install -d "$guest_config/uwsm" "$guest_config/systemd/user/graphical-session.target.wants" \
    /home/vitorpy/.local/bin /home/vitorpy/.local/state/fedora-migration-lab \
    /home/vitorpy/.local/share/applications
cat > "$guest_config/uwsm/env" <<'EOF'
# This server has no 3D GPU assigned to the VM.
export LIBGL_ALWAYS_SOFTWARE=1
export QT_QUICK_BACKEND=software
export AQ_NO_MODIFIERS=1
EOF
ln -sfn ../quickshell-berg.service \
    "$guest_config/systemd/user/graphical-session.target.wants/quickshell-berg.service"
cat > /home/vitorpy/.local/bin/fedora-lab-session <<'EOF'
#!/bin/sh
set -eu
exec >> "$HOME/.local/state/fedora-migration-lab/session.log" 2>&1
exec /usr/bin/uwsm start -e -D Hyprland -F -- /usr/bin/Hyprland \
    --config /home/vitorpy/.config/hypr/hyprland.lua
EOF
chmod 755 /home/vitorpy/.local/bin/fedora-lab-session
cat > /home/vitorpy/.local/share/applications/org.vitorpy.berg.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Berg
Comment=Quickshell desktop bar
Exec=/usr/bin/qs -c berg
Icon=preferences-system-panel
Terminal=false
NoDisplay=true
StartupNotify=false
Categories=Utility;
EOF
chown -R vitorpy:vitorpy "$guest_config" /home/vitorpy/.local

# Console autologin is limited to this disposable guest behind localhost-only VNC.
# Keep Fedora's SELinux policy enabled; greetd creates the normal PAM/seat session.
if [[ ! -f /etc/greetd/config.toml.before-fedora-lab ]]; then
    cp /etc/greetd/config.toml /etc/greetd/config.toml.before-fedora-lab
fi
cat > /etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
command = "/usr/bin/agreety --cmd /bin/bash"
user = "greetd"

[initial_session]
command = "/home/vitorpy/.local/bin/fedora-lab-session"
user = "vitorpy"
EOF
chmod 644 /etc/greetd/config.toml
systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service
systemctl enable greetd.service
systemctl set-default graphical.target
printf 'Guest session configured. Run config/model checks before starting greetd.\n'
