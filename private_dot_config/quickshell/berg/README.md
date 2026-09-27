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

### Preferred audio hardware

WirePlumber policy in
`~/.config/wireplumber/wireplumber.conf.d/51-prefer-jabra.conf` prefers Jabra
ALSA sinks and sources whenever they are connected. It matches the stable card
family name rather than a USB serial number or transient PipeWire node ID. The
session priority is deliberately higher than WirePlumber's remembered-default
bonus, so an external route change cannot silently leave the internal audio
device selected while the Jabra is available. Normal automatic fallback still
applies while the Jabra is disconnected.

After changing this policy, restart the user service with
`systemctl --user restart wireplumber.service`. To roll it back, remove the
fragment through chezmoi, apply that removal, and restart WirePlumber again.

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

## Travel-aware clock

The workstation system timezone stays at `Europe/Warsaw`. Berg formats its
primary clock and calendar in the automatically detected timezone from
`$XDG_CACHE_HOME/quickshell-berg/location.json` (default `~/.cache`). Warsaw is
secondary when the zones differ; its date is shown when the local date differs.
The top bar marks Warsaw with the SF Symbols `house.fill` home icon; tooltips
and the expanded clock retain the city name. The glyph comes from the generated
`SfSymbols.qml` constants and the pinned `sf-symbols.json` specification. The
home glyph and time share a text baseline inside a fixed-height row, so the
SF Symbols and Avenir line metrics cannot independently shift their alignment.
To undo this alignment change, revert its focused commit, apply these managed
files with `chezmoi apply`, then run `qs -c berg ipc call shell reload`.
Other applications retain their own timezone settings or the system default.

`scripts/clock-time.py` uses Python's standard-library `zoneinfo` and installed
`tzdata`. Each minute it formats both clocks from one epoch; civil calendar dates
stay separate from the real timestamps used for weather freshness. The formatter
also runs when the location file changes, independently of weather success.
No global or process-wide `TZ` override is used.

Location detection is automatic only, using the existing providers and one-hour
cache. The weather timer refreshes every 15 minutes; the service retries failures
after 60 seconds. Failed geolocation still returns failure when weather for the
cached location succeeds. Default locations never count as fresh detections.
Connection errors are recorded in the journal.

Offline, time continues in the last known valid timezone, with a "last known
location" note in the panel and tooltip after the cache expires. Without a valid
location it displays Warsaw with "location unavailable". Invalid/missing caches
retain the last valid location in the running shell. On shell restart, a valid
persisted cache is used; otherwise Warsaw is the fallback. These location notes
alone do not put the clock into an error state.

The old `auto-timezone.service` and `.timer` are masked through chezmoi. Their
legacy updater and regression test remain solely for rollback; do not invoke the
updater during normal operation. Stop/disable both old units before applying
the masks, reload the user manager, and set the system timezone once:

```bash
systemctl --user disable --now auto-timezone.timer auto-timezone.service
timedatectl set-timezone Europe/Warsaw
systemctl --user daemon-reload
systemctl --user restart quickshell-berg-weather.service
qs -c berg ipc call shell refreshClock
qs -c berg ipc call shell clockStatus
```

`clockStatus` is a read-only diagnostic returning the display timezone, local
civil date and labels, Warsaw time, location freshness, and health. The timezone
change uses timedated authorization; if it needs an administrator, have the user
perform the privileged command.

For timezone rollback, revert the focused dotfiles commit, apply the restored
units and Berg files, run `systemctl --user daemon-reload`, and
`systemctl --user enable --now auto-timezone.timer`. That resumes automatic system
timezone changes. Leave other hosts' explicit Ansible timezone overrides intact.

## Development and verification

Run static and deterministic checks before reloading the live shell. Lint every
changed QML file and run the repository tests:

```bash
/usr/lib/qt6/bin/qmllint path/to/Changed.qml
~/.config/quickshell/berg/tests/executable_test-package-updates.sh
python ~/.config/quickshell/berg/tests/test_berg_crash_watch.py
python -m pytest ~/.config/quickshell/berg/tests/test_gmail_unread.py
python3 -m unittest discover -s ~/.config/quickshell/berg/tests -p 'test_clock_*.py'
bash ~/.config/systemd/user/tests/test-auto-timezone.sh
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

Before applying clock changes, also run the isolated real-ClockState smoke test
from the host Wayland session:

```bash
python3 ~/.config/quickshell/berg/tests/test-clock-runtime.py
```

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
