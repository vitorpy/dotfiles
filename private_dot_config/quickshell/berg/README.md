# Berg

Berg is the Quickshell desktop shell used with Hyprland. It provides the bar,
popouts, notifications, on-screen displays, media and audio controls, package
update status, weather, Gmail unread status, and power-aware display handling.

The configuration is managed by chezmoi. Runtime state and credentials are
deliberately kept outside the dotfiles repository.

## Fresh-machine setup

1. Apply the Berg configuration and its user units from the chezmoi source:

   ```bash
   chezmoi apply ~/.config/quickshell/berg ~/.config/systemd/user
   systemctl --user daemon-reload
   ```

2. Reconcile the workstation packages with the Arch/Ansible configuration.
   Berg expects `quickshell`, `hyprland`, `brightnessctl`, `playerctl`,
   `libnotify`, `pipewire-pulse`, `wireplumber`, `jq`, `curl`, `pacman-contrib`,
   `yay`, `ghostty`, and Python to be available.

3. Enable and start the managed units:

   ```bash
   systemctl --user enable --now quickshell-berg.service
   systemctl --user enable --now berg-crash-watch.service
   systemctl --user enable --now quickshell-berg-weather.timer
   ```

4. Verify the shell from the active Hyprland session:

   ```bash
   qs -c berg ipc call shell ping
   qs -c berg ipc call actions status
   systemctl --user --no-pager status quickshell-berg.service
   ```

The enabled-state symlinks are also managed by chezmoi, so the explicit enable
commands are safe verification for a new workstation rather than hidden setup.

## Machine-local state

These files are intentionally not portable dotfiles:

| Feature | Location | Setup |
| --- | --- | --- |
| Gmail unread | `~/.config/gmail-unread/` and `~/.local/state/gmail-unread/` | Follow [GMAIL-UNREAD.md](GMAIL-UNREAD.md). Credentials and OAuth tokens must remain private. |
| Weather location/cache | `~/.cache/quickshell-berg/location.json` and `weather.json` | Created and refreshed by the weather service. |
| Wallpaper metadata | `/var/lib/arts-wallpaper/current.json` | Supplied by the separate artwork/wallpaper service. |
| Shell preferences | Quickshell's state directory | Created automatically for DND, keyboard layout, and session-scoped stay-awake state. |

Audio devices, brightness devices, media players, monitors, and power state are
discovered at runtime. They do not require per-host identifiers in Berg.

### Internal display policy

Berg only changes an active internal `eDP-*` panel. It discovers the panel's
largest advertised resolution, targets 48 Hz on battery and 60 Hz on external
power, and preserves the current position and scale. The result is verified;
if the requested refresh rate is rejected, Berg falls back to an advertised
native-resolution mode. External monitors are left untouched.

This makes the policy portable across devices with different panel aspect
ratios. Inspect the selected mode with:

```bash
hyprctl -j monitors | jq '.[] | {name, width, height, refreshRate, scale}'
```

## Operations

Berg watches its QML files and normally reloads automatically. For a
deterministic deployment or smoke test, request an explicit reload:

```bash
qs -c berg ipc call shell reload
```

Useful health and control calls include:

```bash
qs -c berg ipc call shell ping
qs -c berg ipc call actions status
qs -c berg ipc call shell updatesStatus
qs -c berg ipc call shell gmailUnreadStatus
qs -c berg ipc call stay-awake status
```

On Quickshell 0.3.1, use `qs msg` for functions that take arguments because
the `qs ipc call` CLI parser rejects positional function arguments:

```bash
qs msg -c berg <target> <function> <arguments...>
```

Service and log checks:

```bash
systemctl --user show quickshell-berg.service \
  -p ActiveState -p SubState -p NRestarts
systemctl --user status berg-crash-watch.service
systemctl --user status quickshell-berg-weather.timer
journalctl --user -u quickshell-berg.service -b --no-pager -n 100
hyprctl configerrors
```

See [CRASH-WATCH.md](CRASH-WATCH.md) for crash capture and recovery details.

## Development and verification

Run static and deterministic checks before reloading the live shell. Lint every
changed QML file and run the repository tests:

```bash
/usr/lib/qt6/bin/qmllint path/to/Changed.qml
~/.config/quickshell/berg/tests/executable_test-package-updates.sh
python ~/.config/quickshell/berg/tests/test_berg_crash_watch.py
python -m pytest ~/.config/quickshell/berg/tests/test_gmail_unread.py
```

Run the QML tests from the active Hyprland session with the Qt 6 Wayland
runner. `/usr/bin/qmltestrunner` is Qt 5 on this workstation and must not be
used:

```bash
timeout 5 hyprctl -j monitors >/dev/null
env -u DISPLAY -u GTK_THEME -u QT_QPA_PLATFORMTHEME -u QT_STYLE_OVERRIDE \
  QT_QPA_PLATFORM=wayland \
  /usr/lib/qt6/bin/qmltestrunner \
  -input ~/.config/quickshell/berg/tests
```

After those checks pass, apply the managed files, reload Berg, exercise each
changed IPC interaction, and visually inspect UI changes. Do not smoke-test
logout, reboot, or poweroff actions. Finish with bounded service, journal,
Hyprland error, chezmoi parity, and focused Git diff checks.

## Troubleshooting

- If IPC is unavailable, check `qs list` and the `quickshell-berg.service`
  journal before restarting anything.
- If a UI test cannot reach Wayland or the user bus in a sandbox, rerun it from
  the active host session; a headless failure is not evidence of a Berg bug.
- If the internal display has the wrong geometry, inspect `hyprctl -j monitors`
  and confirm the panel advertises its native mode.
- For Gmail authorization or account changes, use the dedicated Gmail guide;
  never add its client secret or token cache to chezmoi.

## Rollback

Revert the relevant commit in the chezmoi source repository, then apply only
the affected Berg paths. If a user unit changed, run
`systemctl --user daemon-reload`; finally reload Berg and repeat the health
checks above.
