# Frigate NVR (Podman exception)

Single-container Frigate on the mediaserver via **Podman Quadlet**.
Rest of the host stays pacman/AUR/Ansible-native.

## Goals

- Detect **person** + **cat** (OpenVINO on Intel N150 iGPU)
- Continuous retain ≈ **8 hours** (`arch_frigate_continuous_days: 0.34`)
- Event / motion / snapshot retain **24 hours** (`arch_frigate_event_days: 1`)
- One RTSP pull per camera via bundled go2rtc; detect on substream, record main

## Layout

| Path | Purpose |
|---|---|
| `/etc/frigate/config.yml` | Frigate config (mode 0640) |
| `/etc/containers/systemd/frigate.container` | Quadlet → `frigate.service` |
| `/mnt/media/cameras/frigate/` | Recordings, clips, exports |
| UI | `http://mediaserver:5000` (LAN / Tailscale) |
| go2rtc RTSP | `rtsp://127.0.0.1:8554/<cam>` (loopback only) |

## Ansible

Enabled for `media_servers` (`arch_frigate_enabled: true`).

```bash
cd ~/.local/share/chezmoi/private_dot_config/private_arch/ansible \
  || cd ~/dotfiles/private_dot_config/private_arch/ansible

ansible-playbook -i inventory site.yml --limit mediaserver --tags frigate,packages,security
# or full:
ansible-playbook -i inventory site.yml --limit mediaserver
```

Cameras: `host_vars/mediaserver.yml` → `arch_frigate_cameras`.

## Ops

```bash
sudo systemctl status frigate
sudo journalctl -u frigate -f
sudo podman logs -f frigate
sudo podman exec -it frigate frigate stats   # if CLI available in image
```

First UI visit: create admin user (Frigate built-in auth).

Auto-update: `podman-auto-update.timer` pulls newer `frigate:stable` when the Quadlet has `AutoUpdate=registry`.

## Jellyfin Live TV

Keep the existing M3U for now. Optional later: point M3U at go2rtc restreams so Jellyfin does not open a second session on each Tenda:

```
rtsp://127.0.0.1:8554/tenda_cp3_1
rtsp://127.0.0.1:8554/tenda_cp3_2
```

## Notes

- Factory camera passwords should be rotated; update M3U + `arch_frigate_cameras` together.
- If OpenVINO GPU fails, set `device: CPU` under `detectors.ov` temporarily.
- Frigate retention is day-based; `0.34` ≈ 8h continuous. If a release rejects floats, set `arch_frigate_continuous_days: 1`.
