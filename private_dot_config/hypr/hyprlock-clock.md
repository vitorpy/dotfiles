# Hyprlock local clock

The time/date label uses `hyprlock-clock.sh` to display the timezone detected by
Berg, independently of the workstation's fixed `Europe/Warsaw` system timezone.
Its existing Pango sizes, line gap, date format, and one-second refresh are kept.

The helper reads `${XDG_CACHE_HOME:-~/.cache}/quickshell-berg/location.json` through
Berg's `scripts/clock-time.py`, reusing its timezone validation and fallback.
A valid stale location continues to work offline. Missing, invalid, or default
location data falls back to Warsaw. No network request is made by the lock screen.

Dependencies: the managed Berg clock helper, Python 3 with system tzdata, Bash,
jq, and GNU date. `XDG_CONFIG_HOME` and `XDG_CACHE_HOME` are honored. The `TZ`
setting applies only to the date-formatting command, not to Hyprlock or the system.

Check the label output with `~/.config/hypr/hyprlock-clock.sh`. The updated config
is read on the next normal lock; verify the visible time/date then. Authentication,
background, and all other widget settings are unchanged.

Rollback: revert the local-clock commit in the chezmoi repository and apply the
restored `~/.config/hypr/hyprlock.conf`. The original date command will once again
follow the system timezone. The unused helper can then be removed from source and
live state with chezmoi.
