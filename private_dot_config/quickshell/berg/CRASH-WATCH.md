# Berg crash notifications

`berg-crash-watch.service` follows only new structured `systemd-coredump`
records for the current user. It sends Berg a critical notification containing
the process name, signal, PID, and a copyable `coredumpctl info PID` inspection
command. It never launches a terminal, diagnostic process, or AI agent.

The watcher starts with `graphical-session.target`, keeps a 60-second in-memory
deduplication window per executable, and waits up to six seconds for Berg's
notification service to return after a Quickshell crash. `journalctl --lines=0`
prevents historical coredumps from being replayed when the service starts.

## Muting a program

Add one exact process name (`COREDUMP_COMM`) or full executable path
(`COREDUMP_EXE`) per line to `crash-watch-muted.txt`. Blank lines and lines
starting with `#` are ignored. Changes take effect on the next crash event; the
service does not need to be restarted.

## Safe fixture check

Formatting can be checked without sending a notification or crashing a process:

```bash
~/.config/quickshell/berg/scripts/berg_crash_watch.py \
  --format-event ~/.config/quickshell/berg/tests/fixtures/coredump-event.json \
  --uid 1000
```

Replace `--format-event` with `--notify-event` to send that controlled fixture
through the live notification service.

## Ownership and rollback

Chezmoi owns this script, the mute list, the systemd user unit, and its
`graphical-session.target.wants` symlink. Ansible owns the direct `python` and
`libnotify` package dependencies.

Disable the watcher without removing managed files:

```bash
systemctl --user disable --now berg-crash-watch.service
```

Re-enable it with:

```bash
systemctl --user enable --now berg-crash-watch.service
```
